// Run the actual handlers and SDK against synthetic HTTP responses, with no net permission.
import { assertEquals, assertExists } from "jsr:@std/assert@1.0.19";
import { BACKEND_WORKLOAD_BUDGET_PRINCIPAL } from "../functions/_shared/monthly-ai-budget.ts";

type Handler = (request: Request) => Response | Promise<Response>;
const handlers: Handler[] = [];
const originalServe = Deno.serve;
try {
  Object.defineProperty(Deno, "serve", {
    configurable: true,
    value: (handler: Handler) => handlers.push(handler),
  });
  await import("../functions/synthesize-voice/index.ts");
  await import("../functions/flag-content/index.ts");
  await import("../functions/generate-meditation-audio/index.ts");
} finally {
  Object.defineProperty(Deno, "serve", { value: originalServe });
}
const [synthesizeVoice, flagContent, generateMeditation] = handlers;
assertEquals(handlers.length, 3);

const userId = "00000000-0000-4000-8000-000000000001";
const contentId = "00000000-0000-4000-8000-000000000002";
const flagId = "00000000-0000-4000-8000-000000000003";
const baseURL = "https://mindfriend.invalid";
const marker = "user_reported_safety_concern";
const dbError = { code: "XX000", message: "Synthetic persistence failure" };

interface Call {
  path: string;
  method: string;
  body?: Record<string, unknown>;
  headers: Headers;
}

class Fixture {
  calls: Call[] = [];
  unexpected: string[] = [];
  content: Record<string, unknown> = {
    id: contentId,
    user_id: userId,
    content_type: "meditation",
    text_content: "Take a slow breath and notice the ground beneath your feet.",
    voice_id: "meditation",
    status: "completed",
    safety_flags: ["existing_safety_marker"],
  };
  flags: Record<string, unknown>[] = [];
  premium = true;
  rateAllowed = true;
  budgetAllowed = true;
  quotaAllowed = true;
  budgetError = false;
  quotaError = false;
  updateError = false;
  updateMissing = false;
  insertError = false;
  insertMissing = false;
  duplicateReadError = false;
  uploadError = false;
  authRejected = false;
  monthlyAllowed = true;
  monthlyError = false;
  libraryMode = false;
  denyAfterFirstSegment = false;

  async fetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    const request = new Request(input, init);
    const url = new URL(request.url);
    const path = url.pathname;
    const call: Call = {
      path,
      method: request.method,
      headers: request.headers,
    };
    if (request.headers.get("content-type")?.includes("application/json")) {
      call.body = await request.json();
    }
    this.calls.push(call);
    const json = (value: unknown, status = 200) =>
      new Response(JSON.stringify(value), {
        status,
        headers: { "Content-Type": "application/json" },
      });
    // PostgREST returns an object only when the SDK requests a single row.
    const rows = (values: Record<string, unknown>[]) => {
      if (request.headers.get("accept")?.includes("vnd.pgrst.object")) {
        return values.length === 1
          ? json(values[0])
          : json({ code: "PGRST116", message: "No row returned" }, 406);
      }
      return json(values);
    };
    if (
      url.origin === "https://texttospeech.googleapis.com" &&
      ["/v1/text:synthesize", "/v1beta1/text:synthesize"].includes(path)
    ) {
      return json({ audioContent: "SUQz" });
    }
    if (url.origin !== baseURL) {
      this.unexpected.push(request.url);
      throw new Error("Unexpected synthetic request");
    }
    if (path === "/auth/v1/user") {
      return this.authRejected
        ? json({ message: "Invalid synthetic token" }, 401)
        : json({ id: userId });
    }
    if (path === "/rest/v1/rpc/check_rate_limit") {
      return json([{
        allowed: this.rateAllowed,
        remaining: 9,
        reset_at: "2100-01-01T00:00:00Z",
      }]);
    }
    if (path === "/rest/v1/profiles") {
      return rows([{ subscription_tier: this.premium ? "premium" : "free" }]);
    }
    if (path === "/rest/v1/rpc/check_tts_monthly_budget") {
      return this.budgetError ? json(dbError, 500) : json([{
        allowed: this.budgetAllowed,
        chars_used: 0,
        chars_limit: 1250000,
        chars_remaining: 1250000,
      }]);
    }
    if (path === "/rest/v1/rpc/reserve_monthly_ai_budget") {
      const params = call.body!;
      assertEquals(call.headers.get("apikey"), "synthetic-service-role-key");
      assertEquals(
        params.p_user_id,
        this.libraryMode ? BACKEND_WORKLOAD_BUDGET_PRINCIPAL : userId,
      );
      assertEquals(
        params.p_feature,
        this.libraryMode ? "meditation.tts" : "voice.tts",
      );
      if (this.denyAfterFirstSegment && this.providerCalls().length > 0) {
        this.monthlyAllowed = false;
      }
      if (this.monthlyError) return json(dbError, 503);
      const reserved = this.monthlyAllowed
        ? params.p_reserve_microdollars as number
        : 10_000_000;
      return json({
        allowed: this.monthlyAllowed,
        reason: this.monthlyAllowed ? "reserved" : "exhausted",
        request_id: params.p_request_id,
        user_id: params.p_user_id,
        feature: params.p_feature,
        month_start: "2026-10-01",
        reserve_microdollars: params.p_reserve_microdollars,
        reserved_microdollars: reserved,
        limit_microdollars: 10_000_000,
        remaining_microdollars: 10_000_000 - reserved,
      });
    }
    if (path === "/rest/v1/rpc/check_and_increment_synthesis_quota") {
      return this.quotaError ? json(dbError, 500) : json([{
        allowed: this.quotaAllowed,
        quota_used: 1,
        quota_limit: 10,
      }]);
    }
    if (this.libraryMode && path === "/rest/v1/exercises") {
      if (request.method === "GET") {
        return rows([{
          id: contentId,
          title: "Synthetic meditation",
          type: "meditation",
          duration_seconds: 60,
          duration_minutes: 1,
          instructions: {
            type: "meditation",
            data: {
              segments: [
                {
                  timestamp_seconds: 0,
                  text: "Synthetic first speech segment",
                },
                {
                  timestamp_seconds: 30,
                  text: "Synthetic second speech segment",
                },
              ],
            },
          },
        }]);
      }
      if (request.method === "PATCH") {
        return new Response(null, { status: 204 });
      }
    }
    if (
      this.libraryMode &&
      path ===
        `/storage/v1/object/audio/exercises/audio/meditation-${contentId}.mp3`
    ) {
      return json({ Key: "synthetic-meditation.mp3" });
    }
    if (path === "/rest/v1/generated_content") {
      if (request.method === "GET") {
        const requestedOwner = url.searchParams.get("user_id");
        return rows(
          requestedOwner && requestedOwner !== `eq.${this.content.user_id}`
            ? []
            : [this.content],
        );
      }
      if (request.method === "PATCH") {
        const body = call.body!;
        // Enforce the two relevant contracts from the schema-only recovery dump.
        if ("duration" in body) {
          return json(
            { code: "PGRST204", message: "Unknown column duration" },
            400,
          );
        }
        if (
          "status" in body &&
          !["pending", "generating", "completed", "failed"].includes(
            String(body.status),
          )
        ) {
          return json(
            { code: "23514", message: "Invalid content status" },
            400,
          );
        }
        if (this.updateError) return json(dbError, 500);
        if (this.updateMissing) return rows([]);
        assertEquals(url.searchParams.get("id"), `eq.${contentId}`);
        Object.assign(this.content, body);
        return request.headers.get("prefer")?.includes("return=representation")
          ? rows([{ id: contentId }])
          : new Response(null, { status: 204 });
      }
    }
    if (path === "/rest/v1/gen_content_flags") {
      if (request.method === "GET") {
        return this.duplicateReadError ? json(dbError, 500) : rows(this.flags);
      }
      if (request.method === "POST") {
        if (this.insertError) return json(dbError, 500);
        if (this.insertMissing) return json(null);
        const flag: Record<string, unknown> = { id: flagId, ...call.body };
        assertEquals(flag.generated_content_id, contentId);
        assertEquals(flag.status, "pending");
        this.flags.push(flag);
        return rows([flag]);
      }
    }
    const fileName = `${userId}/${contentId}.mp3`;
    if (path === `/storage/v1/object/generated-audio/${fileName}`) {
      return this.uploadError ? json(dbError, 500) : json({ Key: fileName });
    }
    if (path === `/storage/v1/object/sign/generated-audio/${fileName}`) {
      return json({
        signedURL: `/object/sign/generated-audio/${fileName}?token=synthetic`,
      });
    }
    if (
      ["/rest/v1/critical_alerts", "/rest/v1/analytics_events"].includes(path)
    ) {
      this.unexpected.push(`${request.method} ${path}`);
      return json({ code: "PGRST205", message: "Table does not exist" }, 404);
    }
    this.unexpected.push(`${request.method} ${path}`);
    throw new Error("Unexpected synthetic request");
  }

  async run(
    handler: Handler,
    body: Record<string, unknown>,
    anonymous = false,
    token = "synthetic-token",
  ) {
    const response = await handler(
      new Request("http://localhost:8000", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(anonymous ? {} : { Authorization: `Bearer ${token}` }),
        },
        body: JSON.stringify(body),
      }),
    );
    return { status: response.status, body: await response.json() };
  }

  providerCalls() {
    return this.calls.filter((call) =>
      ["/v1/text:synthesize", "/v1beta1/text:synthesize"].includes(call.path)
    );
  }
}

async function withFixture(work: (fixture: Fixture) => Promise<void>) {
  const fixture = new Fixture();
  const originalFetch = globalThis.fetch;
  const originalEnvGet = Deno.env.get;
  const env: Record<string, string> = {
    SUPABASE_URL: baseURL,
    SUPABASE_ANON_KEY: "synthetic-anon-key",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role-key",
    GOOGLE_CLOUD_TTS_KEY: "synthetic-tts-key",
  };
  try {
    globalThis.fetch = fixture.fetch.bind(fixture);
    // Never read ambient credentials, including keys unrelated to these handlers.
    Deno.env.get = (key: string) => env[key];
    await work(fixture);
    assertEquals(fixture.unexpected, []);
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalEnvGet;
  }
}

for (
  const token of [
    "synthetic-anon-key",
    "synthetic-token",
    `${btoa('{"alg":"none"}')}.${btoa('{"role":"service_role"}')}.forged`,
  ]
) {
  Deno.test("meditation: only the exact service credential admits shared-library work", () =>
    withFixture(async (fixture) => {
      fixture.libraryMode = true;
      const result = await fixture.run(generateMeditation, {}, false, token);
      assertEquals(result.status, 401);
      assertEquals(fixture.calls, []);
    }));
}

Deno.test("meditation: missing authorization stops before library or provider HTTP", () =>
  withFixture(async (fixture) => {
    const result = await fixture.run(generateMeditation, {}, true);
    assertEquals(result.status, 401);
    assertEquals(fixture.calls, []);
  }));

Deno.test("meditation: each segment reserves at Chirp rate before its paid submission", () =>
  withFixture(async (fixture) => {
    fixture.libraryMode = true;
    const result = await fixture.run(
      generateMeditation,
      {},
      false,
      "synthetic-service-role-key",
    );
    assertEquals(result.body.summary.success, 1);
    const reservations = fixture.calls.filter((call) =>
      call.path.endsWith("reserve_monthly_ai_budget")
    );
    assertEquals(reservations.length, 2);
    assertEquals(fixture.providerCalls().length, 2);
    assertEquals(
      new Set(reservations.map((r) => r.body?.p_request_id)).size,
      2,
    );
    fixture.providerCalls().forEach((call, index) => {
      assertEquals(
        fixture.calls.indexOf(reservations[index]) <
          fixture.calls.indexOf(call),
        true,
      );
      const text = (call.body?.input as { text: string }).text;
      assertEquals(
        reservations[index].body?.p_reserve_microdollars,
        new TextEncoder().encode(text).length * 30,
      );
    });
    assertEquals(
      fixture.calls.some((call) =>
        call.path === "/rest/v1/exercises" && call.method === "PATCH"
      ),
      true,
    );
  }));

for (const afterFirst of [false, true]) {
  Deno.test(`meditation: denied segment admission stops provider and persistence (afterFirst=${afterFirst})`, () =>
    withFixture(async (fixture) => {
      fixture.libraryMode = true;
      fixture.monthlyAllowed = afterFirst;
      fixture.denyAfterFirstSegment = afterFirst;
      const result = await fixture.run(
        generateMeditation,
        {},
        false,
        "synthetic-service-role-key",
      );
      assertEquals(result.body.summary.errors, 1);
      assertEquals(fixture.providerCalls().length, afterFirst ? 1 : 0);
      assertEquals(
        fixture.calls.some((call) =>
          call.path.startsWith("/storage/") || call.method === "PATCH"
        ),
        false,
      );
      assertEquals(JSON.stringify(result.body).includes("microdollars"), false);
    }));
}

Deno.test("meditation: dry run performs no admission or paid submission", () =>
  withFixture(async (fixture) => {
    fixture.libraryMode = true;
    const result = await fixture.run(
      generateMeditation,
      { dryRun: true },
      false,
      "synthetic-service-role-key",
    );
    assertEquals(result.body.summary.dryRun, 1);
    assertEquals(
      fixture.calls.some((call) =>
        call.path.endsWith("reserve_monthly_ai_budget")
      ),
      false,
    );
    assertEquals(fixture.providerCalls().length, 0);
  }));

Deno.test("synthesize-voice: persists duration_seconds and the compatible public locator", () =>
  withFixture(async (fixture) => {
    const result = await fixture.run(synthesizeVoice, { contentId });
    assertEquals(result.status, 200);
    assertEquals(result.body.success, true);
    assertEquals(fixture.content.duration_seconds, result.body.durationSeconds);
    assertEquals("duration" in fixture.content, false);
    assertEquals(
      fixture.content.audio_url,
      `${baseURL}/storage/v1/object/public/generated-audio/${userId}/${contentId}.mp3`,
    );
    assertEquals(
      result.body.audioUrl,
      `${baseURL}/storage/v1/object/sign/generated-audio/${userId}/${contentId}.mp3?token=synthetic`,
    );
    assertEquals(
      fixture.content.voice_settings_used,
      result.body.voiceSettingsUsed,
    );
    assertEquals(fixture.providerCalls().length, 1);
    const update = fixture.calls.find((call) => call.method === "PATCH");
    assertExists(update);
    assertEquals(update.body?.duration_seconds, result.body.durationSeconds);
    assertEquals("duration" in update.body!, false);
    const upload = fixture.calls.find((call) =>
      call.path.startsWith("/storage/v1/object/generated-audio/")
    );
    assertEquals(upload?.headers.get("x-upsert"), "true");
    const providerIndex = fixture.calls.indexOf(fixture.providerCalls()[0]);
    const monthly = fixture.calls.findIndex((call) =>
      call.path.endsWith("reserve_monthly_ai_budget")
    );
    assertEquals(monthly >= 0 && monthly < providerIndex, true);
    const daily = fixture.calls.findIndex((call) =>
      call.path.endsWith("check_and_increment_synthesis_quota")
    );
    assertEquals(monthly < daily && daily < providerIndex, true);
    assertEquals(
      fixture.calls[monthly].body?.p_reserve_microdollars,
      new TextEncoder().encode(String(fixture.content.text_content)).length * 4,
    );
    for (
      const rpc of [
        "check_tts_monthly_budget",
        "check_and_increment_synthesis_quota",
      ]
    ) {
      const index = fixture.calls.findIndex((call) => call.path.endsWith(rpc));
      assertEquals(index >= 0 && index < providerIndex, true);
      assertEquals(fixture.calls[index].body?.p_user_id, userId);
      assertEquals(
        fixture.calls[index].body?.p_character_count,
        String(fixture.content.text_content).length,
      );
    }
  }));

for (const failure of ["monthlyAllowed", "monthlyError"] as const) {
  Deno.test(`synthesize-voice: ${failure} denies paid work without exposing counters`, () =>
    withFixture(async (fixture) => {
      fixture[failure] = failure === "monthlyError";
      const result = await fixture.run(synthesizeVoice, { contentId });
      assertEquals(result.status, failure === "monthlyAllowed" ? 429 : 503);
      assertEquals(result.body.success, false);
      assertEquals(fixture.providerCalls().length, 0);
      assertEquals(
        fixture.calls.some((call) =>
          call.path.endsWith("check_and_increment_synthesis_quota")
        ),
        false,
      );
      assertEquals(
        fixture.calls.some((call) => call.path.startsWith("/storage/")),
        false,
      );
      assertEquals(JSON.stringify(result.body).includes("microdollars"), false);
    }));
}

for (const failure of ["updateError", "updateMissing"] as const) {
  Deno.test(`synthesize-voice: ${failure} cannot return synthesis success`, () =>
    withFixture(async (fixture) => {
      fixture[failure] = true;
      const result = await fixture.run(synthesizeVoice, { contentId });
      assertEquals(result.status, 503);
      assertEquals(result.body.success, false);
      assertEquals(result.body.code, "DATABASE_ERROR");
      assertEquals(result.body.audioUrl, undefined);
      assertEquals(fixture.providerCalls().length, 1);
    }));
}

for (
  const [field, code, status] of [
    ["rateAllowed", "RATE_LIMIT_EXCEEDED", 429],
    ["premium", "PREMIUM_REQUIRED", 403],
    ["budgetAllowed", "MONTHLY_BUDGET_EXCEEDED", 429],
    ["quotaAllowed", "SYNTHESIS_QUOTA_EXCEEDED", 429],
    ["budgetError", "BUDGET_CHECK_ERROR", 500],
    ["quotaError", "QUOTA_CHECK_ERROR", 500],
  ] as const
) {
  Deno.test(`synthesize-voice: ${code} stops before provider or upload`, () =>
    withFixture(async (fixture) => {
      fixture[field] = field.endsWith("Error");
      const result = await fixture.run(synthesizeVoice, { contentId });
      assertEquals(result.status, status);
      assertEquals(result.body.success, false);
      assertEquals(result.body.code, code);
      assertEquals(fixture.providerCalls().length, 0);
      assertEquals(
        fixture.calls.some((call) => call.path.startsWith("/storage/")),
        false,
      );
    }));
}

Deno.test("synthesize-voice: ownership denial precedes paid work", () =>
  withFixture(async (fixture) => {
    fixture.content.user_id = "00000000-0000-4000-8000-000000000004";
    const result = await fixture.run(synthesizeVoice, { contentId });
    assertEquals(result.status, 403);
    assertEquals(result.body.code, "FORBIDDEN");
    assertEquals(fixture.providerCalls().length, 0);
    assertEquals(
      fixture.calls.some((call) => call.path.includes("synthesis_quota")),
      false,
    );
  }));

Deno.test("synthesize-voice: missing auth stops before database or provider", () =>
  withFixture(async (fixture) => {
    const result = await fixture.run(synthesizeVoice, { contentId }, true);
    assertEquals(result.status, 401);
    assertEquals(fixture.calls, []);
  }));

Deno.test("synthesize-voice: upload failure cannot report persisted audio", () =>
  withFixture(async (fixture) => {
    fixture.uploadError = true;
    const result = await fixture.run(synthesizeVoice, { contentId });
    assertEquals(result.status, 500);
    assertEquals(result.body.code, "STORAGE_ERROR");
    assertEquals(fixture.content.audio_url, undefined);
  }));

Deno.test("flag-content: safety reports persist in the clinical queue and safety_flags", () =>
  withFixture(async (fixture) => {
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
      details: "Synthetic safety report",
    });
    assertEquals(result.status, 200);
    assertEquals(result.body.success, true);
    assertEquals(result.body.flagId, flagId);
    assertEquals(fixture.flags.length, 1);
    assertEquals(fixture.flags[0], {
      id: flagId,
      generated_content_id: contentId,
      user_id: userId,
      reason: "safety_concern",
      description: "Synthetic safety report",
      status: "pending",
    });
    assertEquals(fixture.content.status, "completed");
    assertEquals(fixture.content.safety_flags, [
      "existing_safety_marker",
      marker,
    ]);
  }));

for (const failure of ["updateError", "updateMissing"] as const) {
  Deno.test(`flag-content: ${failure} returns failure and retains the review report`, () =>
    withFixture(async (fixture) => {
      fixture[failure] = true;
      const result = await fixture.run(flagContent, {
        contentId,
        reason: "safety_concern",
      });
      assertEquals(result.status, 503);
      assertEquals(result.body.success, false);
      assertEquals(result.body.error, "ESCALATION_FAILED");
      assertEquals(fixture.flags.length, 1);
      assertEquals(fixture.flags[0].status, "pending");
    }));
}

Deno.test("flag-content: a safety retry completes partial persistence without duplicate reports or markers", () =>
  withFixture(async (fixture) => {
    fixture.updateError = true;
    const first = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
    });
    assertEquals(first.status, 503);
    fixture.updateError = false;
    const retry = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
    });
    assertEquals(retry.status, 200);
    assertEquals(retry.body.flagId, flagId);
    assertEquals(fixture.flags.length, 1);
    const repeated = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
    });
    assertEquals(repeated.status, 200);
    assertEquals(fixture.content.safety_flags, [
      "existing_safety_marker",
      marker,
    ]);
    assertEquals(fixture.flags.length, 1);
  }));

for (
  const failure of [
    "insertError",
    "insertMissing",
    "duplicateReadError",
  ] as const
) {
  Deno.test(`flag-content: ${failure} cannot claim report success`, () =>
    withFixture(async (fixture) => {
      fixture[failure] = true;
      const result = await fixture.run(flagContent, {
        contentId,
        reason: "safety_concern",
      });
      assertEquals(result.status, 500);
      assertEquals(result.body.error, "FLAG_FAILED");
      assertEquals(result.body.success === true, false);
      assertEquals(fixture.content.safety_flags, ["existing_safety_marker"]);
    }));
}

Deno.test("flag-content: ordinary reports use the existing review queue", () =>
  withFixture(async (fixture) => {
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "inaccurate",
    });
    assertEquals(result.status, 200);
    assertEquals(fixture.flags[0].reason, "inaccurate");
    assertEquals(fixture.content.safety_flags, ["existing_safety_marker"]);
    assertEquals(fixture.calls.some((call) => call.method === "PATCH"), false);
  }));

Deno.test("flag-content: ordinary duplicate reports still return conflict", () =>
  withFixture(async (fixture) => {
    fixture.flags.push({ id: flagId, reason: "inaccurate", status: "pending" });
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "inaccurate",
    });
    assertEquals(result.status, 409);
    assertEquals(result.body.error, "ALREADY_FLAGGED");
    assertEquals(fixture.flags.length, 1);
  }));

Deno.test("flag-content: a resolved safety report is not reopened by a retry", () =>
  withFixture(async (fixture) => {
    fixture.flags.push({
      id: flagId,
      reason: "safety_concern",
      status: "resolved",
    });
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
    });
    assertEquals(result.status, 409);
    assertEquals(fixture.calls.some((call) => call.method === "PATCH"), false);
    assertEquals(fixture.flags[0].status, "resolved");
  }));

Deno.test("flag-content: anonymous callers cannot access private reports", () =>
  withFixture(async (fixture) => {
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
    }, true);
    assertEquals(result.status, 401);
    assertEquals(fixture.flags, []);
    assertEquals(fixture.calls, []);
  }));

Deno.test("flag-content: rejected JWT cannot become an anonymous report", () =>
  withFixture(async (fixture) => {
    fixture.authRejected = true;
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "harmful",
    });
    assertEquals(result.status, 401);
    assertEquals(fixture.flags, []);
    assertEquals(
      fixture.calls.some((call) => call.path.startsWith("/rest/")),
      false,
    );
  }));

Deno.test("flag-content: another owner's content is unavailable and unchanged", () =>
  withFixture(async (fixture) => {
    fixture.content.user_id = "00000000-0000-4000-8000-000000000099";
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "harmful",
    });
    assertEquals(result.status, 404);
    assertEquals(fixture.flags, []);
    assertEquals(fixture.calls.some((call) => call.method === "PATCH"), false);
  }));

for (
  const [clientReason, storedReason] of [
    ["harmful", "safety_concern"],
    ["triggering", "safety_concern"],
    ["misleading", "inaccurate"],
  ]
) {
  Deno.test(`flag-content: released client reason ${clientReason} persists as ${storedReason}`, () =>
    withFixture(async (fixture) => {
      const result = await fixture.run(flagContent, {
        contentId,
        reason: clientReason,
      });
      assertEquals(result.status, 200);
      assertEquals(fixture.flags[0].reason, storedReason);
      assertEquals(
        (fixture.content.safety_flags as string[]).includes(marker),
        storedReason === "safety_concern",
      );
    }));
}

Deno.test("flag-content: rate denial precedes all report writes", () =>
  withFixture(async (fixture) => {
    fixture.rateAllowed = false;
    const result = await fixture.run(flagContent, {
      contentId,
      reason: "safety_concern",
    });
    assertEquals(result.status, 429);
    assertEquals(fixture.flags, []);
    assertEquals(fixture.calls.some((call) => call.method === "PATCH"), false);
    assertExists(
      fixture.calls.find((call) => call.path.endsWith("check_rate_limit")),
    );
  }));
