// Offline handler tests: synthetic audio, fake keys and every HTTP boundary mocked.
import { deepStrictEqual, ok, strictEqual } from "node:assert";

const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OTHER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const WORK = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const TRANSCRIPT = "Today I felt hopeful after taking a quiet walk.";
const ANALYSIS = {
  overall_sentiment: 0.5,
  emotions: {
    joy: 0.5,
    sadness: 0.1,
    anger: 0,
    fear: 0,
    surprise: 0,
    trust: 0.5,
    anticipation: 0.2,
    disgust: 0,
  },
  tone_analysis: {
    energy: "medium",
    pace: "moderate",
    confidence: "neutral",
    emotional_intensity: "moderate",
  },
  key_themes: ["hope"],
  key_quotes: ["felt hopeful"],
  ai_summary: "A hopeful reflection.",
  reflection_prompts: ["What helped today?"],
};
// Synthetic silent PCM; no recording, user content or provider is used.
function pcmAudio(seconds = 42): Uint8Array<ArrayBuffer> {
  const audio = new Uint8Array(44 + Math.round(seconds * 32000));
  const wav = new DataView(audio.buffer);
  for (
    const [offset, text] of [[0, "RIFF"], [8, "WAVEfmt "], [
      36,
      "data",
    ]] as const
  ) {
    [...text].forEach((c, i) => audio[offset + i] = c.charCodeAt(0));
  }
  wav.setUint32(4, audio.length - 8, true);
  wav.setUint32(16, 16, true);
  wav.setUint16(20, 1, true);
  wav.setUint16(22, 1, true);
  wav.setUint32(24, 16000, true);
  wav.setUint32(28, 32000, true);
  wav.setUint16(32, 2, true);
  wav.setUint16(34, 16, true);
  wav.setUint32(40, audio.length - 44, true);
  return audio;
}
const AUDIO = pcmAudio();

type Handler = (req: Request) => Promise<Response>;
let handler: Handler;
const originalServe = Deno.serve;
const originalFetch = globalThis.fetch;
const originalEnvGet = Deno.env.get;
Deno.serve = ((fn: Handler) => {
  handler = fn;
  return {};
}) as typeof Deno.serve;
Deno.env.get = (key: string) => ({
  SUPABASE_URL: "https://mock.supabase.invalid",
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-role",
  XAI_API_KEY: "fake-xai-key",
}[key]);
try {
  await import("../functions/analyze-voice-journal/index.ts");
} finally {
  Deno.serve = originalServe;
  Deno.env.get = originalEnvGet;
}

type State = ReturnType<typeof fresh>;
function fresh() {
  return {
    work: {
      id: WORK,
      user_id: USER,
      work_type: "voice_journal",
      storage_path:
        `${USER.toUpperCase()}/voice-journals/${WORK.toUpperCase()}.wav`,
      transcription: null as string | null,
      transcription_status: "pending",
      duration_seconds: 42,
    },
    saved: null as any,
    calls: [] as string[],
    reservations: 0,
    monthly: [] as Array<
      {
        p_request_id: string;
        p_user_id: string;
        p_feature: string;
        p_reserve_microdollars: number;
      }
    >,
    monthlyDecision: "allow",
    monthlyAnalysisDecision: "allow",
    onMonthly: null as null | (() => Promise<void> | void),
    paid: 0,
    analysisCalls: 0,
    quota: "allow",
    key: true,
    auth: true,
    mime: "audio/wav",
    audio: AUDIO,
    expectedAudio: AUDIO,
    expectedMinutes: 1,
    storageFail: false,
    declaredSize: null as number | null,
    streamOversize: false,
    stt: { text: TRANSCRIPT, duration: 42 } as any,
    sttStatus: 200,
    sttInvalidJson: false,
    analysis: ANALYSIS as any,
    analysisStatus: 200,
    noChoices: false,
    failSave: "",
    emptySave: "",
    claimLost: false,
    onStt: null as null | (() => Promise<void> | void),
    onAnalysis: null as null | (() => Promise<void> | void),
    seenSignal: null as AbortSignal | null,
  };
}
function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
function install(s: State) {
  Deno.env.get = (
    key: string,
  ) => ({
    SUPABASE_URL: "https://mock.supabase.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "fake-service-role",
    XAI_API_KEY: s.key ? "fake-xai-key" : undefined,
  }[key]);
  globalThis.fetch = async (input, init) => {
    const url = new URL(
      typeof input === "string"
        ? input
        : input instanceof URL
        ? input.href
        : input.url,
    );
    const method = init?.method ?? "GET";
    s.calls.push(`${method} ${url.pathname}`);
    if (url.host === "api.x.ai") {
      strictEqual(init?.redirect, "error");
      ok(init?.signal);
      ok(!init.signal.aborted);
      s.seenSignal = init.signal;
      s.paid++;
      strictEqual(s.reservations, 1, "quota reserved before every paid call");
      strictEqual(s.monthly.length, url.pathname === "/v1/stt" ? 1 : 2);
      strictEqual(s.work.transcription_status, "processing");
      if (url.pathname === "/v1/stt") {
        strictEqual(method, "POST");
        strictEqual(
          new Headers(init.headers).get("Authorization"),
          "Bearer fake-xai-key",
        );
        ok(init.body instanceof FormData);
        deepStrictEqual([...init.body.keys()], ["model", "file"]);
        strictEqual(init.body.get("model"), "grok-voice-transcribe-2.0");
        const file = init.body.get("file") as File;
        deepStrictEqual(
          new Uint8Array(await file.arrayBuffer()),
          s.expectedAudio,
        );
        strictEqual(file.name, `${WORK}.wav`);
        strictEqual(file.type, "audio/wav");
        strictEqual(
          new Headers(init.headers).has("Content-Type"),
          false,
          "fetch supplies multipart boundary",
        );
        if (s.onStt) await s.onStt();
        if (s.sttInvalidJson) return new Response("bad-json");
        return json(s.stt, s.sttStatus);
      }
      strictEqual(url.pathname, "/v1/chat/completions");
      s.analysisCalls++;
      const body = JSON.parse(init.body as string);
      strictEqual(body.model, "grok-4.3");
      strictEqual(body.reasoning_effort, "none");
      ok(
        body.messages[1].content.includes(TRANSCRIPT),
        "analysis must use STT transcript",
      );
      ok(!body.messages[1].content.includes("transcription pending"));
      if (s.onAnalysis) await s.onAnalysis();
      return json(
        s.noChoices ? {} : {
          choices: [{
            message: {
              content: typeof s.analysis === "string"
                ? s.analysis
                : JSON.stringify(s.analysis),
            },
          }],
        },
        s.analysisStatus,
      );
    }
    strictEqual(
      url.host,
      "mock.supabase.invalid",
      "no external URL or SSRF fallback",
    );
    if (url.pathname === "/auth/v1/user") {
      return s.auth ? json({ id: USER }) : json({ message: "bad token" }, 401);
    }
    if (url.pathname === "/rest/v1/rpc/check_rate_limit") {
      return json([{
        allowed: true,
        remaining: 2,
        reset_at: "2099-01-01T00:00:00Z",
      }]);
    }
    if (url.pathname === "/rest/v1/rpc/reserve_voice_journal_quota") {
      const body = JSON.parse(init?.body as string);
      deepStrictEqual(body, { p_user_id: USER, p_minutes: s.expectedMinutes });
      s.reservations++;
      if (s.quota === "error") {
        return json({ message: "private db detail", code: "XX000" }, 500);
      }
      if (s.quota === "empty") return json([]);
      if (s.quota === "malformed") return json([{ allowed: "yes" }]);
      return json([{
        allowed: s.quota === "allow",
        voice_minutes_used: 1,
        voice_minutes_limit: 5,
        is_premium: false,
      }]);
    }
    if (url.pathname === "/rest/v1/rpc/reserve_monthly_ai_budget") {
      const body = JSON.parse(init?.body as string);
      strictEqual(body.p_user_id, USER);
      ok(/^[0-9a-f-]{36}$/.test(body.p_request_id));
      strictEqual(
        body.p_feature,
        s.monthly.length === 0
          ? "voice_journal.transcription"
          : "voice_journal.analysis",
      );
      if (s.monthly.length === 0) {
        strictEqual(body.p_reserve_microdollars, 100_000);
        strictEqual(s.reservations, 0, "global admission precedes daily quota");
        strictEqual(s.paid, 0);
      } else {
        strictEqual(s.paid, 1);
        ok(body.p_reserve_microdollars > 2500);
        ok(body.p_reserve_microdollars < 200_000);
        ok(body.p_request_id !== s.monthly[0].p_request_id);
      }
      s.monthly.push(body);
      if (s.onMonthly) await s.onMonthly();
      const decision = s.monthly.length === 1
        ? s.monthlyDecision
        : s.monthlyAnalysisDecision;
      if (decision === "error") {
        return json({ message: "private budget detail", code: "XX000" }, 500);
      }
      if (decision === "malformed") return json({ allowed: true });
      return json({
        allowed: decision === "allow",
        reason: decision === "allow"
          ? "reserved"
          : decision === "disabled"
          ? "disabled"
          : "exhausted",
        request_id: body.p_request_id,
        user_id: body.p_user_id,
        feature: body.p_feature,
        reserve_microdollars: body.p_reserve_microdollars,
        month_start: "2026-10-01",
        reserved_microdollars: decision === "allow"
          ? body.p_reserve_microdollars
          : 10_000_000,
        limit_microdollars: decision === "disabled" ? 0 : 10_000_000,
        remaining_microdollars: decision === "allow"
          ? 10_000_000 - body.p_reserve_microdollars
          : 0,
      });
    }
    if (url.pathname.startsWith("/storage/v1/object/creative-works/")) {
      strictEqual(
        decodeURIComponent(url.pathname.split("/creative-works/")[1]),
        s.work.storage_path,
      );
      if (s.storageFail) {
        return json({ message: "private storage detail" }, 500);
      }
      const headers: Record<string, string> = { "Content-Type": s.mime };
      if (s.declaredSize !== null) {
        headers["Content-Length"] = String(s.declaredSize);
      }
      if (s.streamOversize) {
        return new Response(
          new ReadableStream({
            start(controller) {
              for (let i = 0; i < 26; i++) {
                controller.enqueue(new Uint8Array(1024 * 1024));
              }
              controller.close();
            },
          }),
          { headers },
        );
      }
      return new Response(s.audio, { headers });
    }
    const single = new Headers(init?.headers).get("Accept")?.includes(
      "vnd.pgrst.object",
    );
    if (url.pathname === "/rest/v1/creative_works") {
      if (method === "GET") return json(single ? s.work : [s.work]);
      strictEqual(method, "PATCH");
      const patch = JSON.parse(init?.body as string);
      const stage = patch.transcription_status === "completed"
        ? "complete"
        : patch.transcription
        ? "transcript"
        : "claim";
      if (s.failSave === stage) {
        return json({ message: "private db detail", code: "XX000" }, 500);
      }
      if (
        s.emptySave === stage ||
        (url.searchParams.has("or") &&
          (s.claimLost || s.work.transcription_status === "processing"))
      ) return json([]);
      Object.assign(s.work, patch);
      return json(single ? { id: WORK } : [{ id: WORK }]);
    }
    if (url.pathname === "/rest/v1/voice_journal_analysis") {
      if (method === "GET") return json(s.saved ? [s.saved] : []);
      strictEqual(method, "POST");
      if (s.failSave === "analysis") {
        return json({ message: "private db detail", code: "XX000" }, 500);
      }
      if (s.emptySave === "analysis") return json(null);
      s.saved = JSON.parse(init?.body as string);
      return json({ id: "mock-analysis" });
    }
    throw new Error(`Unexpected mock route: ${method} ${url.pathname}`);
  };
}
async function request(
  s: State,
  body: unknown = { creativeWorkId: WORK, durationSeconds: 42 },
  options: RequestInit = {},
) {
  install(s);
  return await handler(
    new Request("http://localhost/analyze-voice-journal", {
      method: "POST",
      headers: {
        Authorization: "Bearer fake-user-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      ...options,
    }),
  );
}
function test(name: string, fn: (s: State) => Promise<void>) {
  Deno.test(name, async () => {
    try {
      await fn(fresh());
    } finally {
      globalThis.fetch = originalFetch;
      Deno.env.get = originalEnvGet;
    }
  });
}

test("synthetic audio is transcribed, analyzed, persisted; completed retry does not pay again", async (s) => {
  const result = await request(s);
  strictEqual(result.status, 200);
  strictEqual((await result.json()).analysis.summary, ANALYSIS.ai_summary);
  strictEqual(s.work.transcription, TRANSCRIPT);
  strictEqual(s.saved.full_transcription, TRANSCRIPT);
  strictEqual(s.work.transcription_status, "completed");
  strictEqual(s.work.duration_seconds, 42);
  strictEqual(s.paid, 2);
  strictEqual(s.reservations, 1);
  strictEqual((await request(s)).status, 200);
  strictEqual(s.paid, 2);
  strictEqual(s.reservations, 1);
});

test("sample duration rounds up at minute boundaries before billing", async (s) => {
  s.audio = s.expectedAudio = pcmAudio(60.25);
  s.expectedMinutes = 2;
  s.stt.duration = 60.25;
  const response = await request(s, {
    creativeWorkId: WORK,
    durationSeconds: 60,
  });
  strictEqual(response.status, 200);
  strictEqual(s.work.transcription_status, "completed");
  strictEqual(s.work.duration_seconds, 61);
  strictEqual(s.paid, 2);
});

test("anonymous and invalid authentication never pay", async (s) => {
  strictEqual((await request(s, {}, { headers: {} })).status, 401);
  s.auth = false;
  strictEqual((await request(s)).status, 401);
  strictEqual(s.paid, 0);
});
test("unsupported methods do not consume bodies or contact services", async (s) => {
  install(s);
  const req = {
    method: "GET",
    headers: new Headers(),
    json() {
      throw new Error("body read");
    },
  } as unknown as Request;
  strictEqual((await handler(req)).status, 405);
  strictEqual(s.calls.length, 0);
});
test("invalid JSON, IDs and duration types fail before paid services", async (s) => {
  strictEqual((await request(s, {}, { body: "invalid-json" })).status, 400);
  for (const durationSeconds of [0, -60, 601, null, "42", 1e100]) {
    strictEqual(
      (await request(s, { creativeWorkId: WORK, durationSeconds })).status,
      400,
    );
  }
  strictEqual(
    (await request(s, { creativeWorkId: "bad", durationSeconds: 42 })).status,
    400,
  );
  // Raw overflow JSON parses as Infinity.
  strictEqual(
    (await request(s, {}, {
      body: `{"creativeWorkId":"${WORK}","durationSeconds":1e999}`,
    })).status,
    400,
  );
  strictEqual(s.reservations, 0);
  strictEqual(s.paid, 0);
});
test("cross-user works, non-voice works and unsafe storage paths never pay", async (s) => {
  s.work.user_id = OTHER;
  strictEqual((await request(s)).status, 403);
  s.work.user_id = USER;
  s.work.work_type = "drawing";
  strictEqual((await request(s)).status, 400);
  s.work.work_type = "voice_journal";
  for (
    const path of [
      `${OTHER}/voice-journals/${WORK}.wav`,
      "https://internal.invalid/audio",
      `${USER}/../audio.wav`,
      "",
      `${USER}/voice-journals/%2e%2e.wav`,
    ]
  ) {
    s.work.storage_path = path;
    strictEqual(
      (await request(s, {
        creativeWorkId: WORK,
        durationSeconds: 42,
        audioUrl: "http://169.254.169.254/",
      })).status,
      400,
    );
  }
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});
test("missing backend key returns 503 without quota or paid requests", async (s) => {
  s.key = false;
  strictEqual((await request(s)).status, 503);
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});
for (const decision of ["deny", "disabled", "error", "malformed"]) {
  test(`monthly transcription ${decision} stops before quota and provider`, async (s) => {
    s.monthlyDecision = decision;
    const response = await request(s);
    strictEqual(response.status, 503);
    const result = await response.text();
    ok(result.includes("monthly_ai_budget_"));
    ok(!result.includes("private budget detail"));
    strictEqual(s.reservations, 0);
    strictEqual(s.paid, 0);
    strictEqual(s.monthly.length, 1);
    strictEqual(
      s.work.transcription_status,
      ["deny", "disabled"].includes(decision) ? "pending" : "processing",
    );
  });
}
test("cancelled monthly admission retains uncertain claim without quota or paid work", async (s) => {
  const controller = new AbortController();
  s.onMonthly = () => controller.abort();
  strictEqual(
    (await request(s, undefined, { signal: controller.signal })).status,
    499,
  );
  strictEqual(s.reservations, 0);
  strictEqual(s.paid, 0);
  strictEqual(s.work.transcription_status, "processing");
});
test("analysis monthly denial keeps paid transcription reservation without a second provider call", async (s) => {
  s.monthlyAnalysisDecision = "deny";
  const response = await request(s);
  strictEqual(response.status, 503);
  strictEqual(s.paid, 1);
  strictEqual(s.analysisCalls, 0);
  strictEqual(s.monthly.length, 2);
  strictEqual(s.work.transcription_status, "processing");
  strictEqual((await request(s)).status, 409);
  strictEqual(s.paid, 1);
  strictEqual(s.monthly.length, 2);
});
for (const quota of ["deny", "error", "empty", "malformed"]) {
  test(`quota ${quota} fails closed before xAI`, async (s) => {
    s.quota = quota;
    strictEqual((await request(s)).status, quota === "deny" ? 429 : 503);
    strictEqual(s.paid, 0);
    strictEqual(
      s.work.transcription_status,
      quota === "deny" ? "pending" : "processing",
    );
  });
}
test("processing and lost atomic claim reject retries before reservation", async (s) => {
  s.work.transcription_status = "processing";
  strictEqual((await request(s)).status, 409);
  s.work.transcription_status = "pending";
  s.claimLost = true;
  strictEqual((await request(s)).status, 409);
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});
test("storage failure, unsupported MIME and both oversized forms prevent payment", async (s) => {
  s.storageFail = true;
  strictEqual((await request(s)).status, 502);
  s.storageFail = false;
  s.mime = "text/html";
  strictEqual((await request(s)).status, 415);
  s.mime = "audio/wav";
  s.declaredSize = 25 * 1024 * 1024 + 1;
  ok((await request(s)).status >= 400);
  s.declaredSize = null;
  s.streamOversize = true;
  ok((await request(s)).status >= 400);
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});
for (
  const stt of [
    { text: "", duration: 42 },
    { text: "hi", duration: 0 },
    { text: "hi", duration: -1 },
    { text: "hi", duration: 601 },
    { text: "hi", duration: 61 },
    { duration: 42 },
    { text: "hi", duration: "42" },
  ]
) {
  test(`invalid STT ${JSON.stringify(stt)} never fabricates or analyzes`, async (s) => {
    s.stt = stt;
    strictEqual((await request(s)).status, 502);
    strictEqual(s.analysisCalls, 0);
    strictEqual(s.work.transcription, null);
    strictEqual(s.work.transcription_status, "processing");
    strictEqual((await request(s)).status, 409);
    strictEqual(s.reservations, 1);
  });
}
test("provider HTTP failures and malformed JSON stay honest and retain reservations", async (s) => {
  s.sttStatus = 500;
  strictEqual((await request(s)).status, 502);
  strictEqual(s.analysisCalls, 0);
});
test("malformed STT JSON never reaches analysis", async (s) => {
  s.sttInvalidJson = true;
  strictEqual((await request(s)).status, 502);
  strictEqual(s.analysisCalls, 0);
});
for (
  const invalid of ["not JSON", {}, { ...ANALYSIS, overall_sentiment: 2 }, {
    ...ANALYSIS,
    emotions: {},
  }]
) {
  test(`invalid analysis ${JSON.stringify(invalid)} does not save fabricated output`, async (s) => {
    s.analysis = invalid;
    strictEqual((await request(s)).status, 502);
    strictEqual(s.saved, null);
    strictEqual(s.work.transcription_status, "processing");
  });
}
for (const stage of ["transcript", "analysis", "complete"]) {
  test(`failed ${stage} persistence never reports success or retries paid work`, async (s) => {
    s.failSave = stage;
    const response = await request(s);
    strictEqual(response.status, 503);
    ok(!(await response.text()).includes("private db detail"));
    strictEqual(s.work.transcription_status, "processing");
    strictEqual((await request(s)).status, 409);
    strictEqual(s.reservations, 1);
    strictEqual(s.paid, 2);
  });
  test(`empty ${stage} persistence never reports success`, async (s) => {
    s.emptySave = stage;
    strictEqual((await request(s)).status, 503);
  });
}
test("completed work missing stored analysis fails without another charge", async (s) => {
  s.work.transcription_status = "completed";
  strictEqual((await request(s)).status, 503);
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});
test("concurrent retry loses claim while first STT is in flight", async (s) => {
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  const gate = new Promise<void>((resolve) => release = resolve);
  s.onStt = async () => {
    entered();
    await gate;
  };
  const first = request(s);
  await started;
  strictEqual((await request(s)).status, 409);
  release();
  strictEqual((await first).status, 200);
  strictEqual(s.reservations, 1);
  strictEqual(s.paid, 2);
});
test("client cancellation aborts provider, retains claim and cannot start analysis", async (s) => {
  const controller = new AbortController();
  s.onStt = () => {
    controller.abort();
  };
  strictEqual(
    (await request(s, undefined, { signal: controller.signal })).status,
    499,
  );
  ok(s.seenSignal?.aborted);
  strictEqual(s.analysisCalls, 0);
  strictEqual(s.work.transcription_status, "processing");
});
test("total deadline aborts provider using the 120 second request budget", async (s) => {
  const original = globalThis.setTimeout;
  let deadline!: () => void;
  globalThis.setTimeout = ((callback: () => void, delay: number) => {
    strictEqual(delay, 120_000);
    deadline = callback;
    return original(() => {}, 60_000);
  }) as typeof setTimeout;
  s.onStt = () => {
    deadline();
  };
  try {
    strictEqual((await request(s)).status, 504);
    ok(s.seenSignal?.aborted);
    strictEqual(s.analysisCalls, 0);
    strictEqual(s.reservations, 1);
  } finally {
    globalThis.setTimeout = original;
  }
});

test("legacy compressed audio requests conversion before any download or billing", async (s) => {
  s.work.storage_path =
    `${USER.toUpperCase()}/voice-journals/${WORK.toUpperCase()}.m4a`;
  s.mime = "audio/m4a";
  s.audio = new TextEncoder().encode("synthetic compressed placeholder");
  const response = await request(s, {
    creativeWorkId: WORK,
    durationSeconds: 42,
    audioUrl: "http://169.254.169.254/metadata",
  });
  strictEqual(response.status, 428);
  ok((await response.text()).includes("updated app"));
  ok(!s.calls.some((call) => call.includes("/storage/")));
  strictEqual(s.work.transcription_status, "pending");
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});

test("saved legacy analyses return without downloading or converting old audio", async (s) => {
  strictEqual((await request(s)).status, 200);
  const paid = s.paid, calls = s.calls.length;
  s.work.storage_path = `${USER}/voice-journals/${WORK}.m4a`;
  s.mime = "audio/m4a";
  strictEqual((await request(s)).status, 200);
  strictEqual(s.paid, paid);
  ok(!s.calls.slice(calls).some((call) => call.includes("/storage/")));
});

test("provider network failures expose no raw error and cannot be retried automatically", async (s) => {
  s.onStt = () => {
    throw new Error("private-provider-detail fake-xai-key");
  };
  const response = await request(s);
  strictEqual(response.status, 502);
  const text = await response.text();
  ok(!text.includes("private-provider-detail"));
  ok(!text.includes("fake-xai-key"));
  strictEqual(s.analysisCalls, 0);
  strictEqual((await request(s)).status, 409);
  strictEqual(s.reservations, 1);
});

test("analysis HTTP failure keeps the reservation and reports failure", async (s) => {
  s.analysisStatus = 500;
  strictEqual((await request(s)).status, 502);
  strictEqual(s.saved, null);
  strictEqual(s.work.transcription_status, "processing");
});

test("analysis with no final content cannot be marked completed", async (s) => {
  s.noChoices = true;
  strictEqual((await request(s)).status, 502);
  strictEqual(s.saved, null);
  strictEqual(s.work.transcription_status, "processing");
});

test("client cancellation during analysis prevents persistence", async (s) => {
  const controller = new AbortController();
  s.onAnalysis = () => {
    controller.abort();
  };
  strictEqual(
    (await request(s, undefined, { signal: controller.signal })).status,
    499,
  );
  ok(s.seenSignal?.aborted);
  strictEqual(s.saved, null);
  strictEqual(s.work.transcription_status, "processing");
});

test("already cancelled request cannot make any outbound request", async (s) => {
  const controller = new AbortController();
  controller.abort();
  strictEqual(
    (await request(s, undefined, { signal: controller.signal })).status,
    499,
  );
  strictEqual(s.calls.length, 0);
});

test("total deadline also bounds a stalled request JSON body", async (s) => {
  install(s);
  const original = globalThis.setTimeout;
  let deadline!: () => void;
  globalThis.setTimeout = ((callback: () => void, delay: number) => {
    strictEqual(delay, 120_000);
    deadline = callback;
    return original(() => {}, 60_000);
  }) as typeof setTimeout;
  const req = {
    method: "POST",
    headers: new Headers({ Authorization: "Bearer fake-user-token" }),
    signal: new AbortController().signal,
    json() {
      deadline();
      return new Promise(() => {});
    },
  } as unknown as Request;
  try {
    strictEqual((await handler(req)).status, 504);
    strictEqual(s.reservations, 0);
    strictEqual(s.paid, 0);
  } finally {
    globalThis.setTimeout = original;
  }
});

for (const declared of [1, 600]) {
  test(`declared duration ${declared} cannot change the actual PCM reservation`, async (s) => {
    s.audio = s.expectedAudio = pcmAudio(120);
    s.expectedMinutes = 2;
    s.stt.duration = 120;
    strictEqual(
      (await request(s, { creativeWorkId: WORK, durationSeconds: declared }))
        .status,
      200,
    );
    strictEqual(s.work.duration_seconds, 120);
    strictEqual(s.reservations, 1);
  });
}

test("a 10 minute PCM recording is admitted using exactly ten minutes", async (s) => {
  s.audio = s.expectedAudio = pcmAudio(600);
  s.expectedMinutes = 10;
  s.stt.duration = 600;
  strictEqual(
    (await request(s, { creativeWorkId: WORK, durationSeconds: 1 })).status,
    200,
  );
  strictEqual(s.work.duration_seconds, 600);
});

test("even one sample beyond ten minutes fails before claim, quota and billing", async (s) => {
  s.audio = pcmAudio(600 + 1 / 16000);
  strictEqual((await request(s)).status, 413);
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
  strictEqual(s.work.transcription_status, "pending");
});

for (
  const [name, mutate] of [
    ["compressed bytes labeled WAV", (a: Uint8Array) => {
      a[0] = 0;
    }],
    [
      "truncated RIFF",
      (a: Uint8Array) => new DataView(a.buffer).setUint32(4, 36, true),
    ],
    [
      "compressed format tag",
      (a: Uint8Array) => new DataView(a.buffer).setUint16(20, 2, true),
    ],
    [
      "stereo",
      (a: Uint8Array) => new DataView(a.buffer).setUint16(22, 2, true),
    ],
    [
      "forged slow sample rate",
      (a: Uint8Array) => new DataView(a.buffer).setUint32(24, 1, true),
    ],
    [
      "forged byte rate",
      (a: Uint8Array) => new DataView(a.buffer).setUint32(28, 1, true),
    ],
    [
      "bad alignment",
      (a: Uint8Array) => new DataView(a.buffer).setUint16(32, 4, true),
    ],
    [
      "float depth",
      (a: Uint8Array) => new DataView(a.buffer).setUint16(34, 32, true),
    ],
    [
      "short data size hiding trailing samples",
      (a: Uint8Array) => new DataView(a.buffer).setUint32(40, 2, true),
    ],
    [
      "empty data",
      (a: Uint8Array) => new DataView(a.buffer).setUint32(40, 0, true),
    ],
    [
      "odd sample bytes",
      (a: Uint8Array) =>
        new DataView(a.buffer).setUint32(40, a.length - 45, true),
    ],
    [
      "oversized chunk",
      (a: Uint8Array) => new DataView(a.buffer).setUint32(40, 0xffffffff, true),
    ],
    ["missing format", (a: Uint8Array) => {
      a[12] = 0;
    }],
  ] as const
) {
  test(`untrusted WAV ${name} fails before billing`, async (s) => {
    s.audio = AUDIO.slice();
    mutate(s.audio);
    strictEqual((await request(s)).status, 415);
    strictEqual(s.paid, 0);
    strictEqual(s.reservations, 0);
    strictEqual(s.work.transcription_status, "pending");
  });
}

function withChunk(audio: Uint8Array, kind: string, payload: Uint8Array) {
  const result = new Uint8Array(
    audio.length + 8 + payload.length + payload.length % 2,
  );
  result.set(audio);
  const at = audio.length;
  [...kind].forEach((c, i) => result[at + i] = c.charCodeAt(0));
  const v = new DataView(result.buffer);
  v.setUint32(at + 4, payload.length, true);
  result.set(payload, at + 8);
  v.setUint32(4, result.length - 8, true);
  return result;
}

test("container metadata and odd chunk padding are stripped before transcription", async (s) => {
  s.audio = withChunk(
    AUDIO,
    "LIST",
    new TextEncoder().encode("untrusted duration=99999"),
  );
  strictEqual((await request(s)).status, 200);
  strictEqual(s.work.duration_seconds, 42);
});
for (const kind of ["data", "fmt "]) {
  test(`duplicate ${kind} chunk cannot alter decoded duration`, async (s) => {
    s.audio = withChunk(AUDIO, kind, AUDIO.slice(20, 36));
    strictEqual((await request(s)).status, 415);
    strictEqual(s.paid, 0);
    strictEqual(s.reservations, 0);
  });
}

test("Apple WAV chunk order and padding are accepted but not forwarded", async (s) => {
  const audio = pcmAudio(0.1);
  const padded = withChunk(
    withChunk(audio, "JUNK", new Uint8Array(28)),
    "FLLR",
    new Uint8Array(4008),
  );
  const data = padded.slice(36, audio.length);
  const metadata = padded.slice(audio.length);
  const apple = new Uint8Array(padded.length);
  apple.set(padded.subarray(0, 12));
  apple.set(metadata.subarray(0, 36), 12);
  apple.set(padded.subarray(12, 36), 48);
  apple.set(metadata.subarray(36), 72);
  apple.set(data, 4088);
  s.audio = apple;
  s.expectedAudio = audio;
  s.stt.duration = 0.1;
  strictEqual((await request(s)).status, 200);
  strictEqual(s.work.duration_seconds, 1);
});

async function requestPcm(s: State, options: RequestInit = {}, workId = WORK) {
  install(s);
  return await handler(
    new Request(
      `http://localhost/analyze-voice-journal?creativeWorkId=${workId}`,
      {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-user-token",
          "Content-Type": "audio/wav",
        },
        body: s.audio,
        ...options,
      },
    ),
  );
}

test("owned legacy M4A is analyzed with transient PCM without rewriting or downloading Storage", async (s) => {
  s.work.storage_path = `${USER}/voice-journals/${WORK}.m4a`;
  s.mime = "audio/m4a";
  const originalPath = s.work.storage_path;
  strictEqual((await requestPcm(s)).status, 200);
  strictEqual(s.work.storage_path, originalPath);
  strictEqual(s.work.transcription_status, "completed");
  strictEqual(s.work.duration_seconds, 42);
  strictEqual(s.paid, 2);
  strictEqual(s.reservations, 1);
  ok(!s.calls.some((call) => call.includes("/storage/")));
  strictEqual((await requestPcm(s)).status, 200);
  strictEqual(s.paid, 2);
});

test("transient PCM validates owner and work identity before any billing", async (s) => {
  s.work.user_id = OTHER;
  strictEqual((await requestPcm(s)).status, 403);
  s.work.user_id = USER;
  strictEqual((await requestPcm(s, {}, "invalid")).status, 400);
  strictEqual(
    (await requestPcm(s, { headers: { "Content-Type": "audio/wav" } })).status,
    401,
  );
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});

test("raw PCM body size and malformed samples are rejected before claim or quota", async (s) => {
  strictEqual(
    (await requestPcm(s, {
      headers: {
        Authorization: "Bearer fake-user-token",
        "Content-Type": "audio/wav",
        "Content-Length": "99999999",
      },
    })).status,
    413,
  );
  strictEqual((await requestPcm(s, { body: new Uint8Array() })).status, 413);
  strictEqual(
    (await requestPcm(s, { body: new TextEncoder().encode("compressed-m4a") }))
      .status,
    415,
  );
  const oversized = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(new Uint8Array(20 * 1024 * 1024));
      c.close();
    },
  });
  strictEqual((await requestPcm(s, { body: oversized })).status, 413);
  strictEqual(s.work.transcription_status, "pending");
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
});

test("raw body cancellation closes a stalled reader without claiming or paying", async (s) => {
  const controller = new AbortController();
  let entered!: () => void;
  const reading = new Promise<void>((resolve) => entered = resolve);
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull() {
      entered();
    },
    cancel() {
      cancelled = true;
    },
  }, { highWaterMark: 0 });
  const response = requestPcm(s, { body: stream, signal: controller.signal });
  await reading;
  controller.abort();
  strictEqual((await response).status, 499);
  ok(cancelled);
  strictEqual(s.paid, 0);
  strictEqual(s.reservations, 0);
  strictEqual(s.work.transcription_status, "pending");
});

test("raw PCM concurrent retry preserves one claim and one paid analysis", async (s) => {
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  const gate = new Promise<void>((resolve) => release = resolve);
  s.onStt = async () => {
    entered();
    await gate;
  };
  const first = requestPcm(s);
  await started;
  strictEqual((await requestPcm(s)).status, 409);
  release();
  strictEqual((await first).status, 200);
  strictEqual(s.reservations, 1);
  strictEqual(s.paid, 2);
});

test("raw legacy analysis reserves actual samples rather than stored duration", async (s) => {
  s.work.storage_path = `${USER}/voice-journals/${WORK}.m4a`;
  s.work.duration_seconds = 1;
  s.audio = s.expectedAudio = pcmAudio(120);
  s.stt.duration = 120;
  s.expectedMinutes = 2;
  strictEqual((await requestPcm(s)).status, 200);
  strictEqual(s.work.duration_seconds, 120);
  strictEqual(s.reservations, 1);
});

test("the raw upload deadline cancels a stalled body before claims or providers", async (s) => {
  const original = globalThis.setTimeout;
  let deadline!: () => void;
  globalThis.setTimeout = ((callback: () => void, delay: number) => {
    strictEqual(delay, 120_000);
    deadline = callback;
    return original(() => {}, 60_000);
  }) as typeof setTimeout;
  let reading!: () => void;
  const entered = new Promise<void>((resolve) => reading = resolve);
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull() {
      reading();
    },
    cancel() {
      cancelled = true;
    },
  }, { highWaterMark: 0 });
  try {
    const response = requestPcm(s, { body: stream });
    await entered;
    deadline();
    strictEqual((await response).status, 504);
    ok(cancelled);
    strictEqual(s.reservations, 0);
    strictEqual(s.paid, 0);
  } finally {
    globalThis.setTimeout = original;
  }
});
