// Requires the owned local stack. Provider responses are mocked; external net is denied.
const statusPath = Deno.env.get("MINDFRIEND_LOCAL_STATUS");
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test({ name: "real chat handler: monthly admission, Auth, streaming, persistence, deduplication and owner isolation", ignore: !statusPath, fn: async () => {
  const cfg = JSON.parse(await Deno.readTextFile(statusPath!));
  const base = cfg.API_URL;
  assert(base === "http://127.0.0.1:55321", "Only the isolated local stack is allowed");
  const nativeFetch = globalThis.fetch;
  const nativeServe = Deno.serve;
  const env = { SUPABASE_URL: base, SUPABASE_ANON_KEY: cfg.ANON_KEY, SUPABASE_SERVICE_ROLE_KEY: cfg.SERVICE_ROLE_KEY, OPENAI_API_KEY: "synthetic-only" };
  const previous = Object.keys(env).map((name) => Deno.env.get(name));
  const background: Promise<unknown>[] = [];
  const runtime = globalThis as typeof globalThis & { EdgeRuntime?: { waitUntil(task: Promise<unknown>): void } };
  const previousRuntime = runtime.EdgeRuntime;
  let handler: (request: Request) => Promise<Response> = () => { throw new Error("Handler was not registered"); };
  let providerCalls = 0;
  let lastProviderInput: { role: string; content: string }[] = [];
  let holdStream = false;
  let providerAborted = false;
  let failSettingsRead = false;
  let budgetMode: "allowed" | "exhausted" | "unavailable" = "allowed";
  let reservedMicrodollars = 0;
  const budgetCalls: { p_request_id: string; p_user_id: string; p_feature: string; p_reserve_microdollars: number }[] = [];
  let holdBudget = false;
  let budgetAborted = false;
  let budgetStarted: (() => void) | undefined;
  const encoder = new TextEncoder();
  async function api(path: string, body?: unknown, token = cfg.SERVICE_ROLE_KEY, method?: string) {
    const response = await nativeFetch(base + path, { method: method ?? (body ? "POST" : "GET"), headers: { apikey: cfg.ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json", Prefer: "return=representation" }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await response.text();
    assert(response.ok, `${path.split("?")[0]} failed: ${response.status}`);
    return text ? JSON.parse(text) : null;
  }
  try {
    for (const [name, value] of Object.entries(env)) Deno.env.set(name, value);
    runtime.EdgeRuntime = { waitUntil(task) { background.push(task); } };
    Object.defineProperty(Deno, "serve", { configurable: true, value: (value: typeof handler) => { handler = value; } });
    globalThis.fetch = (async (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      if (url.href === "https://api.openai.com/v1/responses") {
        providerCalls++;
        const body = JSON.parse(init!.body as string);
        assert(body.model === "gpt-6-luna" && body.store === false, "Wrong provider contract");
        lastProviderInput = body.input;
        assert(encoder.encode(JSON.stringify(body.input)).length <= 128_000, "Provider input exceeded UTF-8 byte bound");
        if (body.stream) return new Response(new ReadableStream({ start(controller) {
          controller.enqueue(encoder.encode('data: {"type":"response.output_text.delta","delta":"Synthetic response"}\n\n'));
          if (holdStream) {
            init!.signal!.addEventListener("abort", () => { providerAborted = true; controller.error(new DOMException("Aborted", "AbortError")); }, { once: true });
          } else {
            controller.enqueue(encoder.encode('data: {"type":"response.completed"}\n\n'));
            controller.close();
          }
        } }), { headers: { "Content-Type": "text/event-stream" } });
        const system = body.input[0].content as string;
        const text = system.includes("conversation title") ? "Synthetic title" : system.includes("structured personal facts") ? "[]" : "Synthetic response";
        return Response.json({ status: "completed", output: [{ content: [{ type: "output_text", text }] }] });
      }
      assert(url.origin === base, "External request denied");
      if (url.pathname === "/rest/v1/rpc/reserve_monthly_ai_budget") {
        const params = JSON.parse(init!.body as string);
        budgetCalls.push(params);
        assert(Object.keys(params).sort().join() === "p_feature,p_request_id,p_reserve_microdollars,p_user_id", "Unexpected monthly budget inputs");
        assert(Number.isSafeInteger(params.p_reserve_microdollars) && params.p_reserve_microdollars > 0, "Unbounded monthly reservation");
        if (holdBudget) {
          budgetStarted?.();
          return await new Promise<Response>((_resolve, reject) => {
            const signal = init!.signal!;
            assert(signal, "Monthly admission did not receive cancellation");
            const abort = () => { budgetAborted = true; reject(new DOMException("Aborted", "AbortError")); };
            if (signal.aborted) abort();
            else signal.addEventListener("abort", abort, { once: true });
          });
        }
        if (budgetMode === "unavailable") return Response.json({ message: "Synthetic monthly ledger outage" }, { status: 500 });
        const allowed = budgetMode === "allowed";
        if (allowed) reservedMicrodollars += params.p_reserve_microdollars;
        const total = allowed ? reservedMicrodollars : 10_000_000;
        return Response.json({
          allowed, reason: allowed ? "reserved" : "exhausted",
          request_id: params.p_request_id, user_id: params.p_user_id, feature: params.p_feature,
          reserve_microdollars: params.p_reserve_microdollars,
          month_start: new Date().toLocaleDateString("en-CA", { timeZone: "America/New_York" }).slice(0, 7) + "-01",
          reserved_microdollars: total, limit_microdollars: 10_000_000, remaining_microdollars: 10_000_000 - total,
        });
      }
      if (failSettingsRead && url.pathname === "/rest/v1/user_settings") {
        return Response.json({ message: "Synthetic settings outage" }, { status: 500 });
      }
      return nativeFetch(input, init);
    }) as typeof fetch;
    // Monthly admission is synthetic; this test never changes the real ledger.
    await import("../functions/chat/index.ts");
    const password = crypto.randomUUID();
    const users: { access_token: string; user: { id: string } }[] = [];
    for (let i = 0; i < 2; i++) {
      const email = `restoration-chat-${crypto.randomUUID()}@example.invalid`;
      await api("/auth/v1/admin/users", { email, password, email_confirm: true });
      users.push(await api("/auth/v1/token?grant_type=password", { email, password }, cfg.ANON_KEY));
    }
    const [a, b] = users;
    await api(`/rest/v1/user_settings?user_id=eq.${a.user.id}`, { privacy_mode: "enhanced" }, a.access_token, "PATCH");
    const [conversation] = await api("/rest/v1/conversations", { id: `abcdefab-${crypto.randomUUID().slice(9)}`, user_id: a.user.id, title: "Synthetic integration" }, a.access_token);
    const requestId = `ABCDEFAB-${crypto.randomUUID().slice(9)}`.toUpperCase();
    const content = "A calm synthetic testing day";
    function chat(token: string | null, id = requestId, stream = true, message = content, conversationId = conversation.id.toUpperCase(), signal?: AbortSignal) {
      return handler(new Request("http://localhost/chat", { method: "POST", headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), Accept: stream ? "text/event-stream" : "application/json", "Content-Type": "application/json" }, body: JSON.stringify({ conversationId, content: message, requestId: id }), signal }));
    }
    let response = await chat(null);
    assert(response.status === 401, "Anonymous chat allowed"); await response.text();
    response = await chat(b.access_token);
    assert([403, 404].includes(response.status), "Cross-user conversation allowed"); await response.text();
    assert(providerCalls === 0, "Denied caller reached provider");
    const [privateSettingsConversation] = await api("/rest/v1/conversations", { user_id: b.user.id, title: "Synthetic privacy guard" }, b.access_token);
    failSettingsRead = true;
    response = await chat(b.access_token, crypto.randomUUID(), false, content, privateSettingsConversation.id);
    assert(response.status === 503 && providerCalls === 0, "Unavailable privacy settings reached a provider"); await response.text();
    failSettingsRead = false;
    response = await chat(a.access_token);
    assert(response.ok && response.headers.get("Content-Type") === "text/event-stream", "Streaming not negotiated");
    const text = await response.text();
    const events = text.split("\n").filter((line) => line.startsWith("data:")).map((line) => JSON.parse(line.slice(5)));
    const result = events.find((event) => event.type === "result")?.data;
    assert(events.some((event) => event.type === "delta") && result?.message?.content === "Synthetic response", "Missing delta or final result");
    assert(result.userMessage?.id && result.message.id && typeof result.message.createdAt === "number", "Missing authoritative saved IDs/date contract");
    await Promise.all(background);
    const callsAfterFirst = Number(providerCalls);
    const budgetCallsAfterFirst = budgetCalls.length;
    assert(budgetCallsAfterFirst === callsAfterFirst && budgetCallsAfterFirst === 2, "Main and title did not each reserve once");
    assert(budgetCalls.map((call) => call.p_feature).sort().join() === "chat.response,chat.title", "Enhanced privacy unexpectedly extracted memory");
    assert(budgetCalls.every((call) => call.p_user_id === a.user.id && call.p_request_id !== requestId.toLowerCase()), "Reservations lost verified owner or reused client receipt UUID");
    response = await chat(a.access_token);
    const duplicate = await response.json();
    assert(response.ok && duplicate.message.id === result.message.id && duplicate.userMessage.id === result.userMessage.id && duplicate.assistantMessage.id === result.assistantMessage.id, "Exact uppercase retry did not replay authoritative IDs");
    assert(providerCalls === callsAfterFirst, "Duplicate request generated another charge");
    assert(budgetCalls.length === budgetCallsAfterFirst, "Saved retry reserved monthly budget again");
    response = await chat(a.access_token, requestId.toLowerCase(), false, content, conversation.id);
    const canonicalRetry = await response.json();
    assert(response.ok && canonicalRetry.message.id === result.message.id && canonicalRetry.userMessage.id === result.userMessage.id, "UUID case variants did not share a receipt");
    assert(providerCalls === callsAfterFirst, "Canonical UUID retry reached provider");
    assert(budgetCalls.length === budgetCallsAfterFirst, "Canonical UUID retry reserved monthly budget again");
    response = await chat(a.access_token, requestId, false, "Changed content");
    assert(response.status === 409, "Reused identifier with changed content allowed"); await response.text();
    const history = await api(`/rest/v1/messages?conversation_id=eq.${conversation.id}&select=id,role`, undefined, a.access_token);
    assert(history.length === 2, "Retry duplicated persisted messages");
    assert((await api(`/rest/v1/messages?conversation_id=eq.${conversation.id}&select=id`, undefined, b.access_token)).length === 0, "Cross-user history leaked");
    response = await chat(a.access_token, crypto.randomUUID(), false);
    assert(response.ok && (await response.json()).message.content === "Synthetic response", "Installed-client JSON contract broken");
    await Promise.all(background);
    const [multilingualConversation] = await api("/rest/v1/conversations", { user_id: a.user.id, title: "Synthetic multilingual history" }, a.access_token);
    await api("/rest/v1/messages", Array.from({ length: 20 }, (_, i) => ({
      conversation_id: multilingualConversation.id,
      role: i % 2 ? "assistant" : "user",
      content: `${i}:` + "漢".repeat(3997),
      created_at: new Date(Date.now() - 60_000 + i * 1000).toISOString(),
    })));
    const multilingualMessage = "今".repeat(4000);
    const callsBeforeMultilingual = providerCalls;
    response = await chat(a.access_token, crypto.randomUUID(), false, multilingualMessage, multilingualConversation.id.toUpperCase());
    assert(response.ok && (await response.json()).message.content === "Synthetic response", "Accepted multilingual history failed");
    assert(providerCalls === callsBeforeMultilingual + 1, "Multilingual response retried or did not reach provider");
    assert(lastProviderInput[0]?.role === "system" && lastProviderInput.at(-1)?.content === multilingualMessage, "System or current multilingual input was lost");
    assert(lastProviderInput.length > 2 && lastProviderInput.length < 22 && lastProviderInput.at(-2)?.content.startsWith("19:"), "Newest multilingual history was not retained");
    await Promise.all(background);
    const callsBeforeStandard = providerCalls;
    const budgetCallsBeforeStandard = budgetCalls.length;
    response = await chat(b.access_token, crypto.randomUUID(), false, content, privateSettingsConversation.id);
    assert(response.ok && (await response.json()).message.content === "Synthetic response", "Standard privacy chat failed");
    await Promise.all(background);
    const standardReservations = budgetCalls.slice(budgetCallsBeforeStandard);
    assert(providerCalls === callsBeforeStandard + 3 && standardReservations.length === 3, "Main, title and memory did not each admit a distinct provider submission");
    assert(standardReservations.map((call) => call.p_feature).sort().join() === "chat.memory,chat.response,chat.title", "Background submission has the wrong fixed feature");
    assert(standardReservations.every((call) => call.p_user_id === b.user.id), "Background admission lost its verified user");
    for (const mode of ["exhausted", "unavailable"] as const) {
      budgetMode = mode;
      const beforeDenied: number = Number(providerCalls);
      const [quotaBeforeDenied] = await api(`/rest/v1/profiles?id=eq.${b.user.id}&select=daily_ai_used`);
      response = await chat(b.access_token, crypto.randomUUID(), false, content, privateSettingsConversation.id);
      const error = await response.json();
      assert(response.status === 503 && error.error === (mode === "exhausted" ? "AI_MONTHLY_BUDGET_REACHED" : "AI_MONTHLY_BUDGET_UNAVAILABLE"), "Monthly spending denial did not fail safely");
      assert(!JSON.stringify(error).includes("Synthetic monthly ledger outage") && !JSON.stringify(error).includes("reserved_microdollars"), "Monthly admission exposed private ledger details");
      assert(providerCalls === beforeDenied, "Denied global monthly budget reached provider");
      const [quotaAfterDenied] = await api(`/rest/v1/profiles?id=eq.${b.user.id}&select=daily_ai_used`);
      assert(quotaAfterDenied.daily_ai_used === quotaBeforeDenied.daily_ai_used, "Denied global monthly budget consumed daily AI quota");
    }
    budgetMode = "allowed";
    holdBudget = true;
    const cancellation = new AbortController();
    const admissionStarted = new Promise<void>((resolve) => { budgetStarted = resolve; });
    const callsBeforeAdmissionCancel = providerCalls;
    const [quotaBeforeAdmissionCancel] = await api(`/rest/v1/profiles?id=eq.${b.user.id}&select=daily_ai_used`);
    const cancelledAdmission = chat(b.access_token, crypto.randomUUID(), false, content, privateSettingsConversation.id, cancellation.signal);
    await admissionStarted;
    cancellation.abort();
    response = await cancelledAdmission;
    assert(response.status === 503 && (await response.json()).error === "AI_MONTHLY_BUDGET_UNAVAILABLE", "Cancelled admission did not fail safely");
    assert(budgetAborted && providerCalls === callsBeforeAdmissionCancel, "Monthly admission cancellation reached provider");
    const [quotaAfterAdmissionCancel] = await api(`/rest/v1/profiles?id=eq.${b.user.id}&select=daily_ai_used`);
    assert(quotaAfterAdmissionCancel.daily_ai_used === quotaBeforeAdmissionCancel.daily_ai_used, "Cancelled monthly admission consumed daily quota");
    holdBudget = false;
    budgetStarted = undefined;
    // An existing sponsored seat remains useful after a personal plan expires,
    // even while the stored profile retains its free tier and exhausted quota.
    await api(`/rest/v1/profiles?id=eq.${a.user.id}`, { daily_ai_quota: 0, daily_ai_used: 0 }, cfg.SERVICE_ROLE_KEY, "PATCH");
    const beforeFreeLimit = providerCalls;
    response = await chat(a.access_token, crypto.randomUUID(), false);
    assert(response.status === 429, "Exhausted free quota was not enforced"); await response.text();
    assert(providerCalls === beforeFreeLimit, "Exhausted free quota reached provider");
    const [organization] = await api("/rest/v1/organizations", { name: "Synthetic chat sponsor", billing_email: `synthetic-${crypto.randomUUID()}@example.invalid`, seat_count: 1, seats_used: 1, status: "active", subscription_status: "active" });
    await api("/rest/v1/organization_members", { organization_id: organization.id, user_id: a.user.id, is_active: true });
    response = await chat(a.access_token, crypto.randomUUID(), false);
    assert(response.ok && (await response.json()).message.content === "Synthetic response", "Active sponsorship did not bypass the free chat quota");
    await Promise.all(background);
    const [unchangedTier] = await api(`/rest/v1/profiles?id=eq.${a.user.id}&select=subscription_tier`);
    assert(unchangedTier.subscription_tier === "free", "Sponsorship test unexpectedly rewrote profile tier");
    holdStream = true;
    response = await chat(a.access_token, crypto.randomUUID());
    const reader = response.body!.getReader();
    await reader.read();
    await reader.cancel();
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert(providerAborted, "Client cancellation did not abort provider");
    await Promise.all(background);
    assert(new Set(budgetCalls.map((call) => call.p_request_id)).size === budgetCalls.length, "Distinct provider submissions reused a monthly reservation UUID");
  } finally {
    globalThis.fetch = nativeFetch;
    Object.defineProperty(Deno, "serve", { configurable: true, value: nativeServe });
    runtime.EdgeRuntime = previousRuntime;
    Object.keys(env).forEach((name, i) => previous[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[i]!));
  }
} });
