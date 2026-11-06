// Real handlers with synthetic Auth/REST/provider fixtures; no network permission.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

const userId = "23456789-2345-4345-8345-23456789abcd";
const conversationId = "34567890-3456-4456-8456-34567890abcd";
const messageId = "45678901-4567-4567-8567-45678901abcd";

Deno.test("content and rewrites: monthly admission precedes quota and paid submission", async () => {
  const originalFetch = globalThis.fetch;
  const originalServe = Deno.serve;
  const env = {
    SUPABASE_URL: "http://127.0.0.1:59998",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-only",
    SUPABASE_ANON_KEY: "synthetic-anon-only",
    XAI_API_KEY: "synthetic-only",
    GOOGLE_CLOUD_TTS_KEY: "synthetic-only",
    DEBUG: "false",
  };
  const previous = Object.keys(env).map((key) => Deno.env.get(key));
  const freshState = () => ({
    premium: false,
    mode: "allowed",
    textCalls: 0,
    googleCalls: 0,
    contentQuotaCalls: 0,
    synthesisQuotaCalls: 0,
    rewriteQuotaCalls: 0,
    contentRows: [] as { id: string; status: string }[],
    budgetFeatures: [] as string[],
    events: [] as string[],
    cancellation: undefined as AbortController | undefined,
  });
  let state = freshState();
  let endpoint = "generate-content";
  let handler: (req: Request) => Promise<Response> = () => {
    throw new Error("Handler not registered");
  };
  async function invoke() {
    const body = endpoint === "generate-content"
      ? {
        contentType: "affirmation",
        params: { duration: 300, theme: "calm reflection" },
      }
      : {
        conversationId,
        messageId,
        messageText: "A calm synthetic thought",
        rewriteType: "more_balanced",
      };
    return await handler(
      new Request(`http://localhost/${endpoint}`, {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic-user",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: state.cancellation?.signal,
      }),
    );
  }
  try {
    for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (registered: typeof handler) => {
        handler = registered;
      },
    });
    // Preserve fetch's Promise contract while every fixture stays in memory.
    // deno-lint-ignore require-await
    globalThis.fetch = (async (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const body = typeof init?.body === "string"
        ? JSON.parse(init.body)
        : undefined;
      if (url.hostname === "api.x.ai") {
        state.textCalls++;
        state.events.push("provider:text");
        assert(
          state.budgetFeatures.at(-1) ===
            (endpoint === "generate-content"
              ? "content.text"
              : "rewrite.generate"),
          "Text provider lacked monthly admission",
        );
        assert(
          endpoint === "generate-content"
            ? state.contentQuotaCalls === 1 && state.contentRows.length === 1
            : state.premium || state.rewriteQuotaCalls === 1,
          "Text provider preceded quota reservation",
        );
        const content = endpoint === "generate-content"
          ? "Breathe gently and relax. ".repeat(300)
          : JSON.stringify([{
            text: "A balanced synthetic thought",
            explanation: "Synthetic perspective",
          }]);
        return Response.json({ choices: [{ message: { content } }] });
      }
      if (url.hostname === "texttospeech.googleapis.com") {
        state.googleCalls++;
        state.events.push("provider:tts");
        assert(
          state.budgetFeatures.at(-1) === "content.tts" &&
            state.synthesisQuotaCalls === 1,
          "Google provider preceded monthly/daily reservations",
        );
        return Response.json({ audioContent: btoa("synthetic-audio") });
      }
      assert(url.origin === env.SUPABASE_URL, "Unexpected external request");
      if (url.pathname === "/auth/v1/user") {
        return Response.json({
          id: userId,
          aud: "authenticated",
          role: "authenticated",
        });
      }
      if (url.pathname === "/rest/v1/rpc/check_rate_limit") {
        return Response.json([{
          allowed: true,
          remaining: 9,
          reset_at: new Date(Date.now() + 60_000).toISOString(),
        }]);
      }
      if (url.pathname === "/rest/v1/rpc/reserve_monthly_ai_budget") {
        const feature = body.p_feature;
        state.budgetFeatures.push(feature);
        state.events.push(`monthly:${feature}`);
        assert(
          body.p_user_id === userId,
          "Monthly receipt lost verified owner",
        );
        if (
          state.mode === "unavailable" ||
          (state.mode === "tts-unavailable" && feature === "content.tts")
        ) {
          return Response.json({ message: "Synthetic unavailable" }, {
            status: 500,
          });
        }
        const allowed = state.mode !== "exhausted" &&
          !(state.mode === "tts-exhausted" && feature === "content.tts");
        if (state.mode === "abort") state.cancellation!.abort();
        const reserved = allowed ? body.p_reserve_microdollars : 10_000_000;
        return Response.json({
          allowed,
          reason: allowed ? "reserved" : "exhausted",
          request_id: body.p_request_id,
          user_id: body.p_user_id,
          feature,
          reserve_microdollars: body.p_reserve_microdollars,
          month_start: "2026-10-01",
          reserved_microdollars: reserved,
          limit_microdollars: 10_000_000,
          remaining_microdollars: 10_000_000 - reserved,
        });
      }
      if (url.pathname === "/rest/v1/rpc/check_and_increment_content_quota") {
        state.contentQuotaCalls++;
        state.events.push("quota:content");
        assert(
          state.budgetFeatures.at(-1) === "content.text",
          "Content quota preceded monthly admission",
        );
        const used = state.contentRows.filter((row) =>
          row.status !== "failed"
        ).length;
        return Response.json([{
          allowed: state.premium || used < 1,
          quota_used: used,
          quota_limit: state.premium ? -1 : 1,
        }]);
      }
      if (url.pathname === "/rest/v1/rpc/check_tts_monthly_budget") {
        return Response.json([{ allowed: true }]);
      }
      if (url.pathname === "/rest/v1/rpc/check_and_increment_synthesis_quota") {
        state.synthesisQuotaCalls++;
        state.events.push("quota:tts");
        assert(
          state.budgetFeatures.at(-1) === "content.tts",
          "Synthesis quota preceded monthly admission",
        );
        return Response.json([{ allowed: state.mode !== "tts-quota-denied" }]);
      }
      if (url.pathname === "/rest/v1/rpc/check_and_increment_rewrite_quota") {
        state.rewriteQuotaCalls++;
        state.events.push("quota:rewrite");
        assert(
          state.budgetFeatures.at(-1) === "rewrite.generate",
          "Rewrite quota preceded monthly admission",
        );
        return Response.json(state.mode !== "rewrite-quota-denied");
      }
      if (url.pathname === "/rest/v1/profiles") {
        return Response.json({
          subscription_tier: state.premium ? "premium" : "free",
        });
      }
      if (url.pathname === "/rest/v1/generated_content") {
        if (init?.method === "POST") {
          const row = { id: crypto.randomUUID(), status: body.status };
          state.contentRows.push(row);
          state.events.push("record:content");
          return Response.json({ id: row.id });
        }
        if (init?.method === "PATCH") {
          const id = url.searchParams.get("id")?.replace("eq.", "");
          const row = state.contentRows.find((value) => value.id === id);
          if (row && body.status) row.status = body.status;
          return new Response(null, { status: 204 });
        }
      }
      if (url.pathname === "/rest/v1/gen_content_requests") {
        return new Response(null, { status: 204 });
      }
      if (url.pathname === "/rest/v1/conversations") {
        return Response.json({ id: conversationId });
      }
      if (url.pathname === "/rest/v1/subscriptions") {
        return Response.json(state.premium ? { status: "active" } : null);
      }
      if (url.pathname === "/rest/v1/rewrite_types") {
        return Response.json({
          system_prompt_suffix: "Use a balanced perspective.",
        });
      }
      if (url.pathname === "/rest/v1/rewrite_history") {
        return Response.json({ id: crypto.randomUUID() });
      }
      if (url.pathname === "/rest/v1/rewrite_quota") {
        return Response.json({ daily_count: state.rewriteQuotaCalls });
      }
      if (url.pathname.startsWith("/storage/v1/object/sign/")) {
        return Response.json({
          signedURL: "/object/sign/generated-audio/synthetic?token=synthetic",
        });
      }
      if (url.pathname.startsWith("/storage/v1/object/")) {
        return Response.json({ Key: "synthetic" });
      }
      throw new Error(`Unexpected local fixture path: ${url.pathname}`);
    }) as typeof fetch;
    await import("../functions/generate-content/index.ts");
    for (const mode of ["exhausted", "unavailable", "abort"]) {
      state = freshState();
      state.mode = mode;
      state.cancellation = new AbortController();
      const response = await invoke();
      assert(!response.ok, "Denied text admission unexpectedly succeeded");
      await response.text();
      assert(
        state.contentQuotaCalls === 0 && state.contentRows.length === 0 &&
          state.textCalls === 0,
        "Monthly text denial consumed quota or submitted",
      );
    }
    state = freshState();
    let response = await invoke();
    const free = await response.json();
    assert(
      response.ok && free.textContent && free.quotaUsed === 1 &&
        free.quotaLimit === 1 && !free.audioUrl,
      "First free text-only generation regressed",
    );
    assert(
      state.events.slice(0, 4).join() ===
        "monthly:content.text,quota:content,record:content,provider:text",
      "Content quota order changed",
    );
    assert(
      state.contentQuotaCalls === 1 && state.synthesisQuotaCalls === 0 &&
        state.googleCalls === 0,
      "Free generation used speech quota/provider",
    );
    response = await invoke();
    assert(
      response.status === 429 &&
        (await response.json()).error === "AI_QUOTA_EXCEEDED",
      "Existing free content limit was not preserved",
    );
    assert(
      Number(state.textCalls) === 1 && state.contentRows.length === 1,
      "Denied free quota submitted or created another counted row",
    );
    for (const mode of ["tts-exhausted", "tts-unavailable"]) {
      state = freshState();
      state.premium = true;
      state.mode = mode;
      response = await invoke();
      const result = await response.json();
      assert(
        response.ok && result.textContent && !result.audioUrl,
        "Denied TTS did not preserve generated text",
      );
      assert(
        state.textCalls === 1 && state.contentQuotaCalls === 1 &&
          state.synthesisQuotaCalls === 0 && state.googleCalls === 0,
        "Monthly TTS denial consumed speech quota or submitted Google",
      );
    }
    state = freshState();
    state.premium = true;
    response = await invoke();
    const premium = await response.json();
    assert(response.ok && premium.audioUrl, "Admitted premium speech failed");
    assert(
      state.googleCalls > 1 && state.synthesisQuotaCalls === 1 &&
        state.contentQuotaCalls === 1,
      "Chunked speech double-debited daily quota",
    );
    assert(
      state.budgetFeatures.filter((feature) => feature === "content.tts")
        .length === state.googleCalls,
      "Speech chunks shared monthly admission",
    );
    state = freshState();
    state.premium = true;
    state.mode = "tts-quota-denied";
    response = await invoke();
    assert(
      response.ok && !(await response.json()).audioUrl &&
        state.synthesisQuotaCalls === 1 && state.googleCalls === 0,
      "Daily speech quota no longer preserves text-only fallback",
    );
    endpoint = "generate-rewrites";
    await import("../functions/generate-rewrites/index.ts");
    for (const mode of ["exhausted", "unavailable", "abort"]) {
      state = freshState();
      state.mode = mode;
      state.cancellation = new AbortController();
      response = await invoke();
      assert(!response.ok, "Denied rewrite admission succeeded");
      await response.text();
      assert(
        state.rewriteQuotaCalls === 0 && state.textCalls === 0,
        "Monthly rewrite denial consumed daily quota or submitted",
      );
    }
    state = freshState();
    response = await invoke();
    assert(
      response.ok && (await response.json()).rewrites.length === 1,
      "Admitted free rewrite failed",
    );
    assert(
      state.events.join() ===
        "monthly:rewrite.generate,quota:rewrite,provider:text",
      "Rewrite admission/quota/provider order changed",
    );
    state = freshState();
    state.mode = "rewrite-quota-denied";
    response = await invoke();
    assert(
      response.status === 403 && (await response.json()).remainingQuota === 0 &&
        state.textCalls === 0,
      "Existing free rewrite limit was not preserved",
    );
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: originalServe,
    });
    Object.keys(env).forEach((key, i) =>
      previous[i] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, previous[i]!)
    );
  }
});
