import {
  bridgeRelay,
  clientEvent,
  type Clock,
  handleVoiceRelay,
  MONTHLY_VOICE_RESERVE_MICRODOLLARS,
  type RelayDependencies,
} from "../_shared/voice-relay.ts";
function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw Error(message);
}
function rejects(fn: () => unknown) {
  let rejected = false;
  try {
    fn();
  } catch {
    rejected = true;
  }
  assert(rejected);
}
class FakeClock implements Clock {
  time = 0;
  sequence = 0;
  timers = new Map<number, { at: number; fn: () => void }>();
  now() {
    return this.time;
  }
  set(fn: () => void, ms: number) {
    const id = ++this.sequence;
    this.timers.set(id, { at: this.time + ms, fn });
    return id;
  }
  clear(id: number) {
    this.timers.delete(id);
  }
  advance(ms: number) {
    const end = this.time + ms;
    while (true) {
      const next = [...this.timers].filter(([, t]) =>
        t.at <= end
      ).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) {
        break;
      }
      this.time = next[1].at;
      this.timers.delete(next[0]);
      next[1].fn();
    }
    this.time = end;
  }
}
class Socket extends EventTarget {
  readyState = 1;
  bufferedAmount = 0;
  sent: string[] = [];
  closes = 0;
  reason = "";
  listeners = 0;
  override addEventListener(
    type: string,
    fn: EventListenerOrEventListenerObject | null,
    options?: boolean | AddEventListenerOptions,
  ) {
    this.listeners++;
    super.addEventListener(type, fn, options);
  }
  override removeEventListener(
    type: string,
    fn: EventListenerOrEventListenerObject | null,
    options?: boolean | EventListenerOptions,
  ) {
    this.listeners--;
    super.removeEventListener(type, fn, options);
  }
  send(data: string) {
    this.sent.push(data);
  }
  close(_code?: number, reason?: string) {
    this.closes++;
    this.reason = reason ?? "";
    this.readyState = 2;
  }
  closed(clean = true) {
    this.readyState = 3;
    this.dispatchEvent(
      new CloseEvent("close", { code: clean ? 1000 : 1006, wasClean: clean }),
    );
  }
  message(data: unknown) {
    this.dispatchEvent(new MessageEvent("message", { data }));
  }
  socket() {
    return this as unknown as WebSocket;
  }
}
const id = "10000000-0000-4000-8000-000000000001";
function harness() {
  const clock = new FakeClock(), client = new Socket(), upstream = new Socket();
  const calls: string[] = [];
  let used = false;
  const deps: RelayDependencies = {
    clock,
    anonKey: "anon",
    authenticate: (jwt) => Promise.resolve(jwt === "owner" ? "owner" : null),
    rpc: (name, args) => {
      calls.push(name);
      if (name === "prepare_voice_relay") {
        return Promise.resolve({
          session_id: id,
          expires_at: "2026-10-23T00:00:00Z",
          minutes_remaining: 3,
          voice: "ara",
          is_premium: false,
          available_voices: ["ara"],
        });
      }
      if (name === "claim_voice_relay") {
        if (used || args.p_session_id !== id) throw Error("INVALID");
        used = true;
        return Promise.resolve({
          reserved_seconds: 120,
          is_premium: false,
          monthly_reserve_microdollars: MONTHLY_VOICE_RESERVE_MICRODOLLARS,
          monthly_budget_month: "2026-10-01",
        });
      }
      return Promise.resolve({});
    },
    issueSecret: () => {
      calls.push("issue");
      return Promise.resolve("ephemeral-secret");
    },
    connect: () => {
      calls.push("connect");
      return upstream.socket();
    },
    upgrade: () => ({
      socket: client.socket(),
      response: new Response(null, { status: 200 }),
    }),
  };
  function request(method = "GET", body?: object, jwt = "owner", sid = id) {
    return new Request(`http://localhost/voice-token?session_id=${sid}`, {
      method,
      headers: {
        Authorization: `Bearer ${jwt}`,
        apikey: "anon",
        upgrade: "websocket",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  }
  return { deps, calls, clock, client, upstream, request };
}
Deno.test("anonymous, wrong JWT, malformed UUID and missing apikey denied before provider", async () => {
  for (
    const request of [
      new Request("http://localhost/voice-token"),
      new Request("http://localhost/voice-token", {
        headers: { Authorization: "Bearer owner" },
      }),
    ]
  ) {
    const h = harness();
    assert((await handleVoiceRelay(request, h.deps)).status === 401);
    assert(!h.calls.length);
  }
  const h = harness();
  assert(
    (await handleVoiceRelay(h.request("GET", undefined, "other"), h.deps))
      .status === 401,
  );
  assert(
    (await handleVoiceRelay(
      h.request("GET", undefined, "owner", "bad"),
      h.deps,
    )).status === 400,
  );
  assert(!h.calls.length);
});
Deno.test("POST prepares without provider credentials and requires explicit relay transport", async () => {
  const h = harness();
  assert(
    (await handleVoiceRelay(h.request("POST", {}), h.deps)).status === 426,
  );
  const result = await handleVoiceRelay(
    h.request("POST", { transport: "relay" }),
    h.deps,
  );
  const body = await result.json();
  assert(
    body.token === "" && body.transport === "relay" &&
      body.max_duration_seconds === 120,
  );
  assert(h.calls.join() === "prepare_voice_relay");
  assert(!JSON.stringify(body).includes("secret"));
  assert(!h.clock.timers.size);
});
Deno.test("quota/ownership/replay failure precedes provider issuance", async () => {
  const h = harness();
  h.deps.rpc = () => {
    throw Error("QUOTA_EXCEEDED");
  };
  assert((await handleVoiceRelay(h.request(), h.deps)).status === 403);
  assert(!h.calls.includes("issue"));
  const r = harness();
  await handleVoiceRelay(r.request(), r.deps);
  assert(r.calls.slice(0, 3).join() === "claim_voice_relay,issue,connect");
  assert((await handleVoiceRelay(r.request(), r.deps)).status === 409);
  assert(r.calls.filter((c) => c === "issue").length === 1);
  r.client.closed();
  r.upstream.closed();
  assert(!r.clock.timers.size);
});
Deno.test("cap closes both sockets; finalizes only after upstream close; cleanup is once", async () => {
  const h = harness();
  await handleVoiceRelay(h.request(), h.deps);
  h.clock.advance(119999);
  assert(h.upstream.closes === 0);
  h.clock.advance(1);
  assert(
    h.upstream.reason === "SESSION_LIMIT_REACHED" && h.client.closes === 1,
  );
  assert(!h.calls.includes("finalize_voice_relay"));
  h.upstream.closed();
  h.upstream.closed();
  assert(h.calls.filter((c) => c === "finalize_voice_relay").length === 1);
  assert(
    !h.clock.timers.size && h.client.listeners === 0 &&
      h.upstream.listeners === 0,
  );
});
Deno.test("unknown close retains reservation and wall timer removes every listener", async () => {
  const h = harness();
  await handleVoiceRelay(h.request(), h.deps);
  h.clock.advance(135000);
  assert(!h.calls.includes("finalize_voice_relay"));
  assert(!h.clock.timers.size);
  assert(h.client.listeners === 0 && h.upstream.listeners === 0);
});
Deno.test("client close, provider failure and malformed/binary/oversized frames clean both sockets", async () => {
  for (
    const action of [
      (h: ReturnType<typeof harness>) => h.client.closed(),
      (h: ReturnType<typeof harness>) =>
        h.upstream.dispatchEvent(new Event("error")),
      (h: ReturnType<typeof harness>) => h.client.message(new Uint8Array(2)),
      (h: ReturnType<typeof harness>) => h.client.message("x".repeat(100000)),
    ]
  ) {
    const h = harness();
    await handleVoiceRelay(h.request(), h.deps);
    action(h);
    assert(h.upstream.closes === 1);
    h.upstream.closed();
    assert(!h.clock.timers.size);
  }
});
Deno.test("backpressure and frame flood stop the relay", async () => {
  for (const flood of [false, true]) {
    const h = harness();
    await handleVoiceRelay(h.request(), h.deps);
    h.client.message('{"type":"session.update","session":{}}');
    if (flood) {
      for (let i = 0; i < 81; i++) {
        h.client.message('{"type":"input_audio_buffer.clear"}');
      }
    } else {
      h.client.bufferedAmount = 300000;
      h.clock.advance(250);
    }
    assert(h.upstream.closes === 1);
    h.upstream.closed();
    assert(!h.clock.timers.size);
  }
});
Deno.test("no key escapes provider messages, errors or session metadata", async () => {
  for (
    const event of [
      { type: "session.created", session: { client_secret: "anything" } },
      { type: "error", error: { message: "ephemeral-secret" } },
      { type: "response.text.delta", delta: "ephemeral-secret" },
    ]
  ) {
    const h = harness();
    await handleVoiceRelay(h.request(), h.deps);
    h.upstream.message(JSON.stringify(event));
    assert(!h.client.sent.join().includes("secret"));
    h.client.closed();
    h.upstream.closed();
  }
});
Deno.test("allow PCM/VAD/mute/cancel; strip custom audio URLs and refuse tools, resume and oversized context", () => {
  const update = JSON.parse(clientEvent(
    JSON.stringify({
      type: "session.update",
      session: {
        voice: "ara",
        instructions: "help",
        audio: { url: "https://bad" },
        turn_detection: {
          type: "server_vad",
          threshold: 0.15,
          create_response: true,
        },
      },
    }),
    false,
  )!);
  assert(
    update.session.audio.input.format.rate === 24000 &&
      update.session.tools.length === 0,
  );
  assert(!JSON.stringify(update).includes("https"));
  for (
    const type of [
      "response.cancel",
      "input_audio_buffer.clear",
      "input_audio_buffer.commit",
    ]
  ) {
    assert(
      JSON.parse(clientEvent(JSON.stringify({ type }), false)!).type === type,
    );
  }
  for (
    const e of [
      { type: "session.update", session: { tools: [{ type: "web_search" }] } },
      { type: "session.resume" },
      { type: "response.create", response: { tools: [] } },
      { type: "session.update", session: { instructions: "x".repeat(12001) } },
      { type: "session.update", session: { voice: "rex" } },
    ]
  ) rejects(() => clientEvent(JSON.stringify(e), false));
});
Deno.test("separately billed text items never reach the provider", async () => {
  const event = {
    type: "conversation.item.create",
    item: {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: "Synthetic" }],
    },
  };
  for (const premium of [false, true]) {
    rejects(() => clientEvent(JSON.stringify(event), premium));
  }
  const h = harness();
  await handleVoiceRelay(h.request(), h.deps);
  h.client.message(
    JSON.stringify({ type: "session.update", session: { voice: "ara" } }),
  );
  const sent = h.upstream.sent.length;
  h.client.message(JSON.stringify(event));
  assert(
    h.upstream.sent.length === sent && h.upstream.closes === 1 &&
      h.client.closes === 1,
  );
  h.upstream.closed();
  h.client.closed();
  assert(!h.clock.timers.size);
});
Deno.test("setup timeout cancels Auth without provider or dangling timers", async () => {
  const h = harness();
  h.deps.authenticate = () => new Promise(() => {});
  const result = handleVoiceRelay(h.request(), h.deps);
  h.clock.advance(12000);
  assert((await result).status === 409);
  assert(!h.calls.length && !h.clock.timers.size);
});
Deno.test("short remaining allowance determines cap and finalized duration", () => {
  const clock = new FakeClock(), client = new Socket(), provider = new Socket();
  let duration = -1;
  bridgeRelay(client.socket(), provider.socket(), {
    clock,
    seconds: 5,
    premium: false,
    secret: "private",
    deadline: 135000,
    finalize: (s) => {
      duration = s;
      return Promise.resolve();
    },
  });
  clock.advance(5000);
  assert(provider.reason === "SESSION_LIMIT_REACHED");
  provider.closed();
  assert(duration === 5 && !clock.timers.size);
});

Deno.test("unknown provider setup failure keeps the full reservation", async () => {
  const h = harness();
  h.deps.issueSecret = () => Promise.reject(Error("private-provider-details"));
  const result = await handleVoiceRelay(h.request(), h.deps);
  assert(result.status === 409 && !(await result.text()).includes("private"));
  assert(h.calls.join() === "claim_voice_relay");
  assert(!h.clock.timers.size);
});

Deno.test("unknown provider setup timeout holds full reservation and never connects late", async () => {
  const h = harness();
  let complete: (secret: string) => void = () => {};
  h.deps.issueSecret = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  const result = handleVoiceRelay(h.request(), h.deps);
  // Flush authentication and claim continuations before advancing the mock clock.
  for (let i = 0; i < 5; i++) await Promise.resolve();
  h.clock.advance(12000);
  assert((await result).status === 409);
  complete("late-secret");
  for (let i = 0; i < 5; i++) await Promise.resolve();
  assert(
    !h.calls.includes("connect") && !h.calls.includes("finalize_voice_relay"),
  );
  assert(!h.clock.timers.size);
});

Deno.test("context budget and provider oversized frames close without forwarding", async () => {
  const h = harness();
  await handleVoiceRelay(h.request(), h.deps);
  const config = JSON.stringify({
    type: "session.update",
    session: { instructions: "x".repeat(12000) },
  });
  h.client.message(config);
  h.client.message(config);
  h.client.message(config);
  assert(h.upstream.closes === 1);
  h.upstream.closed();
  assert(!h.clock.timers.size);
  const p = harness();
  await handleVoiceRelay(p.request(), p.deps);
  p.upstream.message("x".repeat(100000));
  assert(
    p.upstream.closes === 1 &&
      !p.client.sent.some((frame) => frame.length > 1000),
  );
  p.upstream.closed();
  assert(!p.clock.timers.size);
});

Deno.test("setup consumes wall budget, handshake starts the conservative provider cap", async () => {
  const h = harness();
  h.deps.issueSecret = () => {
    h.clock.advance(11000);
    return Promise.resolve("private");
  };
  await handleVoiceRelay(h.request(), h.deps);
  h.clock.advance(119999);
  assert(h.upstream.closes === 0);
  h.clock.advance(1);
  assert(h.clock.now() === 131000 && Number(h.upstream.closes) === 1);
  h.upstream.closed();
  assert(!h.clock.timers.size);
});

Deno.test("oversized POST body is rejected before creating a reservation", async () => {
  const h = harness();
  const response = await handleVoiceRelay(
    h.request("POST", { transport: "relay", context: "x".repeat(1024) }),
    h.deps,
  );
  assert(
    response.status === 413 && h.calls.length === 0 && !h.clock.timers.size,
  );
});

Deno.test("POST transport gate uses authenticated JWT; WebSocket additionally needs anon apikey", async () => {
  const h = harness();
  const request = (body: object) =>
    new Request("http://localhost/voice-token", {
      method: "POST",
      headers: { Authorization: "Bearer owner" },
      body: JSON.stringify(body),
    });
  assert((await handleVoiceRelay(request({}), h.deps)).status === 426);
  assert(
    (await handleVoiceRelay(request({ transport: "relay" }), h.deps)).status ===
      200,
  );
  assert(!h.calls.includes("issue"));
});

Deno.test("heartbeat and conversation-created events preserve existing iOS protocol", async () => {
  const h = harness();
  await handleVoiceRelay(h.request(), h.deps);
  h.upstream.message('{"type":"ping"}');
  h.client.message('{"type":"pong"}');
  assert(h.upstream.sent.includes('{"type":"pong"}'));
  h.upstream.message(
    '{"type":"conversation.created","conversation":{"id":"server-private"}}',
  );
  assert(
    h.client.sent.some((raw) =>
      JSON.parse(raw).type === "conversation.created"
    ),
  );
  assert(!h.client.sent.join().includes("server-private"));
  h.client.closed();
  h.upstream.closed();
  assert(!h.clock.timers.size);
});

Deno.test("client configuration waits for provider open and preserves order", async () => {
  const h = harness();
  h.upstream.readyState = 0;
  await handleVoiceRelay(h.request(), h.deps);
  h.client.message(
    JSON.stringify({ type: "session.update", session: { voice: "ara" } }),
  );
  h.client.message(
    JSON.stringify({ type: "input_audio_buffer.append", audio: "AAAA" }),
  );
  assert(h.upstream.sent.length === 0 && h.upstream.closes === 0);
  h.upstream.readyState = 1;
  h.upstream.dispatchEvent(new Event("open"));
  assert(Number(h.upstream.sent.length) === 2);
  assert(JSON.parse(h.upstream.sent[0]).type === "session.update");
  assert(JSON.parse(h.upstream.sent[1]).type === "input_audio_buffer.append");
  h.client.closed();
  h.upstream.closed();
  assert(!h.clock.timers.size);
});
Deno.test("provider setup events wait for client open", async () => {
  const h = harness();
  h.client.readyState = 0;
  await handleVoiceRelay(h.request(), h.deps);
  h.upstream.message(
    JSON.stringify({ type: "session.created", session: { id: "private" } }),
  );
  assert(h.client.sent.length === 0 && h.upstream.closes === 0);
  h.client.readyState = 1;
  h.client.dispatchEvent(new Event("open"));
  assert(
    Number(h.client.sent.length) === 1 && !h.client.sent[0].includes("private"),
  );
  h.client.closed();
  h.upstream.closed();
});
Deno.test("stalled handshake closes at twelve seconds and never flushes after cancellation", async () => {
  const h = harness();
  h.upstream.readyState = 0;
  await handleVoiceRelay(h.request(), h.deps);
  h.client.message(JSON.stringify({ type: "session.update", session: {} }));
  h.clock.advance(12000);
  assert(h.upstream.closes === 1 && h.upstream.reason === "SETUP_TIMEOUT");
  h.upstream.readyState = 1;
  h.upstream.dispatchEvent(new Event("open"));
  assert(h.upstream.sent.length === 0);
  h.client.closed();
  h.upstream.closed();
  assert(!h.clock.timers.size);
});

Deno.test("global budget denial prevents any provider setup", async () => {
  const h = harness();
  h.deps.rpc = (name) => {
    h.calls.push(name);
    return Promise.reject(Error("VOICE_BUDGET_EXCEEDED"));
  };
  const response = await handleVoiceRelay(h.request(), h.deps);
  assert(response.status === 503);
  assert((await response.json()).code === "VOICE_BUDGET_EXCEEDED");
  assert(h.calls.join() === "claim_voice_relay");
  assert(!h.clock.timers.size);
});
Deno.test("invalid admission response retains all holds and cannot contact provider", async () => {
  const h = harness();
  h.deps.rpc = (name) => {
    h.calls.push(name);
    return Promise.resolve({ reserved_seconds: 121 });
  };
  assert((await handleVoiceRelay(h.request(), h.deps)).status === 409);
  assert(h.calls.join() === "claim_voice_relay");
});
Deno.test("unknown atomic claim outcome cannot refund or contact provider", async () => {
  const h = harness();
  h.deps.rpc = (name) => {
    h.calls.push(name);
    return Promise.reject(Error("unknown database outcome"));
  };
  assert((await handleVoiceRelay(h.request(), h.deps)).status === 409);
  assert(h.calls.join() === "claim_voice_relay");
});

Deno.test("missing local provider key never claims; a distinct session starts after configuration is restored", async () => {
  type Handler = (req: Request) => Response | Promise<Response>;
  let handler!: Handler;
  const serve = Deno.serve, envGet = Deno.env.get;
  const fetchOriginal = globalThis.fetch, socketOriginal = globalThis.WebSocket;
  const upgrade = Deno.upgradeWebSocket;
  const client = new Socket(), provider = new Socket();
  const secondId = "20000000-0000-4000-8000-000000000002";
  const prepared: string[] = [], claimed: string[] = [];
  let active: string | null = null, providerKey: string | undefined;
  let providerRequests = 0, providerConnections = 0, finalizations = 0;
  let finalized!: () => void;
  const settled = new Promise<void>((resolve) => finalized = resolve);
  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  const request = (method: string, sessionId = id, jwt = "owner") =>
    new Request(`http://localhost/voice-token?session_id=${sessionId}`, {
      method,
      headers: {
        Authorization: `Bearer ${jwt}`,
        apikey: "rotated-public-key",
        upgrade: "websocket",
      },
      body: method === "POST"
        ? JSON.stringify({ transport: "relay" })
        : undefined,
    });
  try {
    Deno.serve = ((fn: Handler) => {
      handler = fn;
      return {};
    }) as typeof Deno.serve;
    Deno.env.get = (key) => ({
      SUPABASE_URL: "https://mock.supabase.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "fake-service-role",
      SUPABASE_ANON_KEY: "anon",
      XAI_API_KEY: providerKey,
    }[key]);
    globalThis.fetch = (input, init) => {
      const url = new URL(
        typeof input === "string"
          ? input
          : input instanceof URL
          ? input.href
          : input.url,
      );
      if (url.host === "api.x.ai") {
        providerRequests++;
        assert(url.pathname === "/v1/realtime/client_secrets");
        assert(
          new Headers(init?.headers).get("Authorization") ===
            "Bearer fake-provider-key",
        );
        return Promise.resolve(json({ value: "ephemeral-secret" }));
      }
      assert(
        url.host === "mock.supabase.invalid",
        "all HTTP boundaries must be mocked",
      );
      if (url.pathname === "/auth/v1/user") {
        const auth = new Headers(init?.headers).get("Authorization");
        if (auth === "Bearer invalid") {
          return Promise.resolve(json({ message: "Invalid JWT" }, 401));
        }
        return Promise.resolve(
          json({ id, is_anonymous: auth === "Bearer anonymous" }),
        );
      }
      const args = init?.body ? JSON.parse(init.body as string) : {};
      if (url.pathname === "/rest/v1/rpc/prepare_voice_relay") {
        const sessionId = prepared.length ? secondId : id;
        prepared.push(sessionId);
        return Promise.resolve(json({ session_id: sessionId }));
      }
      if (url.pathname === "/rest/v1/rpc/claim_voice_relay") {
        if (active) {
          return Promise.resolve(
            json({ message: "RELAY_ALREADY_ACTIVE" }, 400),
          );
        }
        active = args.p_session_id;
        claimed.push(args.p_session_id);
        return Promise.resolve(
          json({
            reserved_seconds: 120,
            is_premium: false,
            monthly_reserve_microdollars: MONTHLY_VOICE_RESERVE_MICRODOLLARS,
            monthly_budget_month: "2026-10-01",
          }),
        );
      }
      if (url.pathname === "/rest/v1/rpc/finalize_voice_relay") {
        assert(args.p_session_id === secondId);
        active = null;
        finalizations++;
        finalized();
        return Promise.resolve(json({ status: "finalized" }));
      }
      throw Error("Unexpected mock route");
    };
    globalThis.WebSocket = function (url: string | URL) {
      assert(String(url).startsWith("wss://api.x.ai/"));
      providerConnections++;
      return provider.socket();
    } as unknown as typeof WebSocket;
    Deno.upgradeWebSocket = () => ({
      socket: client.socket(),
      response: new Response(null),
    });
    await import("../voice-token/index.ts");
    Deno.serve = serve;

    const first = await handler(request("POST"));
    assert(first.status === 200 && (await first.json()).session_id === id);
    for (const missing of [undefined, "", "   "]) {
      providerKey = missing;
      const denied = await handler(request("GET"));
      assert(
        denied.status === 503 && (await denied.json()).code === "CONFIG_ERROR",
      );
      assert(claimed.length === 0 && active === null && finalizations === 0);
      assert(providerRequests === 0 && providerConnections === 0);
    }

    providerKey = "fake-provider-key";
    for (const jwt of ["invalid", "anonymous"]) {
      assert((await handler(request("GET", id, jwt))).status === 401);
      assert(
        claimed.length === 0 && providerRequests === 0 &&
          providerConnections === 0,
      );
    }
    const next = await handler(request("POST"));
    assert(next.status === 200 && (await next.json()).session_id === secondId);
    assert(prepared.length === 2 && prepared[0] !== prepared[1]);
    assert((await handler(request("GET", secondId))).status === 200);
    assert(
      claimed.length === 1 && claimed[0] === secondId && active === secondId,
    );
    assert(providerRequests === 1 && providerConnections === 1);
    client.closed();
    provider.closed();
    await settled;
    assert(active === null && finalizations === 1);
  } finally {
    client.closed();
    provider.closed();
    Deno.serve = serve;
    Deno.env.get = envGet;
    globalThis.fetch = fetchOriginal;
    globalThis.WebSocket = socketOriginal;
    Deno.upgradeWebSocket = upgrade;
  }
});

Deno.test("monthly denial and missing fixed reservation stop before provider issuance", async () => {
  const h = harness();
  h.deps.rpc = (name) => {
    h.calls.push(name);
    return Promise.reject(Error("MONTHLY_AI_BUDGET_EXCEEDED"));
  };
  const result = await handleVoiceRelay(h.request(), h.deps);
  assert(
    result.status === 503 &&
      (await result.json()).code === "MONTHLY_AI_BUDGET_EXCEEDED",
  );
  assert(h.calls.join() === "claim_voice_relay");
  for (const hold of [undefined, 9600000, "240000"]) {
    const missing = harness();
    missing.deps.rpc = (name) => {
      missing.calls.push(name);
      return Promise.resolve({
        reserved_seconds: 120,
        monthly_reserve_microdollars: hold,
        monthly_budget_month: "2026-10-01",
      });
    };
    assert(
      (await handleVoiceRelay(missing.request(), missing.deps)).status === 409,
    );
    assert(missing.calls.join() === "claim_voice_relay");
  }
});

Deno.test("connect setup counts toward the two-minute cap and finalizer has no refund fields", async () => {
  const h = harness();
  const rpc = h.deps.rpc;
  let recorded: Record<string, unknown> | undefined;
  h.deps.rpc = (name, args, signal) => {
    if (name === "finalize_voice_relay") recorded = args;
    return rpc(name, args, signal);
  };
  h.deps.connect = () => {
    h.clock.advance(1000);
    return h.upstream.socket();
  };
  await handleVoiceRelay(h.request(), h.deps);
  h.clock.advance(118999);
  assert(h.upstream.closes === 0);
  h.clock.advance(1);
  assert(h.clock.now() === 120000 && Number(h.upstream.closes) === 1);
  assert(!h.calls.includes("finalize_voice_relay"));
  h.clock.advance(5000);
  h.upstream.closed();
  assert(recorded?.p_duration_seconds === 120);
  assert(
    recorded && Object.keys(recorded).sort().join() ===
        "p_duration_seconds,p_session_id,p_was_quota_limited",
  );
});

Deno.test("close requires the provider close signal and exact CLOSED state", () => {
  const clock = new FakeClock(), client = new Socket(), provider = new Socket();
  let finalized = 0;
  bridgeRelay(client.socket(), provider.socket(), {
    clock,
    seconds: 120,
    premium: false,
    secret: "private",
    deadline: 135000,
    finalize: () => {
      finalized++;
      return Promise.resolve();
    },
  });
  provider.dispatchEvent(new Event("close")); // OPEN is not closure evidence.
  assert(finalized === 0);
  provider.readyState = 3;
  client.closed(); // Local observation without provider close event is insufficient.
  assert(finalized === 0);
  provider.closed();
  assert(Number(finalized) === 1 && !clock.timers.size);
});

Deno.test("never-opened and socket-error outcomes retain active database reservation", async () => {
  for (const setupFailure of [true, false]) {
    const h = harness(), rpc = h.deps.rpc;
    let recorded: Record<string, unknown> | undefined;
    h.deps.rpc = (name, args, signal) => {
      if (name === "finalize_voice_relay") recorded = args;
      return rpc(name, args, signal);
    };
    if (setupFailure) h.upstream.readyState = 0;
    await handleVoiceRelay(h.request(), h.deps);
    if (setupFailure) h.clock.advance(12000);
    else h.upstream.dispatchEvent(new Event("error"));
    h.upstream.closed();
    assert(recorded === undefined && !h.calls.includes("finalize_voice_relay"));
    assert(!h.clock.timers.size);
  }
});

Deno.test("confirmed immediate closure reports only trusted user duration", async () => {
  const h = harness(), rpc = h.deps.rpc;
  let recorded: Record<string, unknown> | undefined;
  h.deps.rpc = (name, args, signal) => {
    if (name === "finalize_voice_relay") recorded = args;
    return rpc(name, args, signal);
  };
  await handleVoiceRelay(h.request(), h.deps);
  h.upstream.closed();
  assert(recorded?.p_duration_seconds === 0);
  assert(
    recorded &&
      !Object.keys(recorded).some((key) => key.startsWith("p_provider")),
  );
});

Deno.test("abnormal close without an error event cannot clear active reservation", async () => {
  const h = harness(), rpc = h.deps.rpc;
  let recorded: Record<string, unknown> | undefined;
  h.deps.rpc = (name, args, signal) => {
    if (name === "finalize_voice_relay") recorded = args;
    return rpc(name, args, signal);
  };
  await handleVoiceRelay(h.request(), h.deps);
  h.clock.advance(1000);
  h.upstream.closed(false);
  assert(recorded === undefined && !h.calls.includes("finalize_voice_relay"));
  assert(!h.clock.timers.size);
});

Deno.test("nonempty rotated public keys still require an authenticated user JWT", async () => {
  for (const jwt of [undefined, "invalid", "anonymous"]) {
    const h = harness();
    const headers = new Headers({
      apikey: "different-public-key",
      upgrade: "websocket",
    });
    if (jwt) headers.set("Authorization", `Bearer ${jwt}`);
    const req = new Request(`http://localhost/voice-token?session_id=${id}`, {
      headers,
    });
    assert((await handleVoiceRelay(req, h.deps)).status === 401);
    assert(h.calls.length === 0);
  }
  for (const key of ["", "   "]) {
    const h = harness();
    const req = new Request(`http://localhost/voice-token?session_id=${id}`, {
      headers: {
        Authorization: "Bearer owner",
        apikey: key,
        upgrade: "websocket",
      },
    });
    assert(
      (await handleVoiceRelay(req, h.deps)).status === 401 &&
        h.calls.length === 0,
    );
  }
  const h = harness();
  const headers = new Headers(h.request().headers);
  headers.set("apikey", "different-public-key");
  assert(
    (await handleVoiceRelay(new Request(h.request(), { headers }), h.deps))
      .status === 200,
  );
  assert(h.calls.slice(0, 3).join() === "claim_voice_relay,issue,connect");
  h.client.closed();
  h.upstream.closed();
});

Deno.test("upgrade retains one pending worker lifetime until provider closure or existing deadline", async () => {
  for (const outcome of ["clean", "unclean", "deadline"]) {
    const h = harness(), work: Promise<unknown>[] = [];
    let lifetimeDone = false;
    h.deps.waitUntil = (promise) => {
      work.push(promise);
    };
    await handleVoiceRelay(h.request(), h.deps);
    assert(work.length === 1 && h.clock.timers.size === 4);
    void work[0].then(() => {
      lifetimeDone = true;
    });
    await Promise.resolve();
    assert(!lifetimeDone);
    h.client.closed();
    await Promise.resolve();
    assert(!lifetimeDone); // Keep running while provider is only CLOSING.
    if (outcome === "deadline") h.clock.advance(135000);
    else h.upstream.closed(outcome === "clean");
    await Promise.resolve();
    assert(lifetimeDone && !h.clock.timers.size);
    assert(work.length === (outcome === "clean" ? 2 : 1));
    assert(h.calls.includes("finalize_voice_relay") === (outcome === "clean"));
  }
});

Deno.test("current xAI VAD conversation.item.added sequence maps to existing iOS created event", async () => {
  const h = harness();
  await handleVoiceRelay(h.request(), h.deps);
  h.upstream.message(
    JSON.stringify({ type: "session.created", session: { id: "upstream" } }),
  );
  h.upstream.message(
    JSON.stringify({
      type: "conversation.created",
      conversation: { id: "upstream" },
    }),
  );
  h.upstream.message('{"type":"ping"}');
  h.client.message('{"type":"pong"}');
  h.client.message(
    JSON.stringify({
      type: "session.update",
      session: {
        turn_detection: { type: "server_vad", create_response: true },
      },
    }),
  );
  const item = {
    id: "user-item",
    type: "message",
    role: "user",
    content: [{ type: "input_audio", transcript: null }],
  };
  for (
    const event of [
      { type: "session.updated", session: { id: "upstream" } },
      { type: "input_audio_buffer.speech_started", item_id: item.id },
      { type: "input_audio_buffer.speech_stopped", item_id: item.id },
      { type: "input_audio_buffer.committed", item_id: item.id },
      {
        type: "conversation.item.added",
        event_id: "added-event",
        previous_item_id: null,
        item,
      },
      {
        type: "conversation.item.input_audio_transcription.completed",
        item_id: item.id,
        transcript: "Synthetic greeting",
      },
      { type: "response.created", response: { id: "response" } },
      {
        type: "response.output_item.added",
        item: { id: "assistant-item", role: "assistant" },
      },
      { type: "response.content_part.added", content_index: 0 },
      { type: "response.output_audio.delta", delta: "AAAA" },
      { type: "response.output_audio_transcript.delta", delta: "Hello" },
      { type: "response.output_audio.done" },
      { type: "response.output_audio_transcript.done" },
      { type: "response.content_part.done" },
      { type: "response.output_item.done" },
      { type: "response.done", response: { id: "response" } },
    ]
  ) h.upstream.message(JSON.stringify(event));
  const events = h.client.sent.map((raw) => JSON.parse(raw));
  const mapped = events.find((event) =>
    event.type === "conversation.item.created"
  );
  assert(mapped && JSON.stringify(mapped.item) === JSON.stringify(item));
  assert(mapped.event_id === "added-event" && mapped.previous_item_id === null);
  assert(events.some((event) => event.type === "response.output_audio.delta"));
  assert(events.some((event) => event.type === "response.done"));
  assert(
    !events.some((event) =>
      event.type === "error" || event.type === "conversation.item.added"
    ),
  );
  assert(h.client.closes === 0 && h.upstream.closes === 0);
  h.clock.advance(120000);
  assert(h.upstream.reason === "SESSION_LIMIT_REACHED");
  h.upstream.closed();
  assert(!h.clock.timers.size);
});
