// Pure Google TTS admission checks: synthetic transports, no net/env permission.
import {
  CHIRP3_HD_PRESETS,
  GOOGLE_VOICE_PRESETS,
  GoogleTTSClient,
  GoogleTTSError,
  type GoogleTTSOptions,
} from "../functions/_shared/google-tts.ts";
import {
  type MonthlyAIBudgetAdmin,
  MonthlyAIBudgetExhaustedError,
  MonthlyAIBudgetUnavailableError,
} from "../functions/_shared/monthly-ai-budget.ts";

type Params = Parameters<MonthlyAIBudgetAdmin["rpc"]>[1];
const userId = "10000000-0000-4000-8000-000000000001";
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function receipt(params: Params, mode = "allowed") {
  const limit = mode === "disabled" ? 0 : 10_000_000;
  const reserved = mode === "denied"
    ? limit
    : mode === "disabled"
    ? 0
    : params.p_reserve_microdollars;
  return {
    allowed: mode === "allowed",
    reason: mode === "denied"
      ? "exhausted"
      : mode === "disabled"
      ? "disabled"
      : "reserved",
    request_id: params.p_request_id,
    user_id: params.p_user_id,
    feature: params.p_feature,
    month_start: "2026-10-01",
    reserve_microdollars: params.p_reserve_microdollars,
    reserved_microdollars: reserved,
    limit_microdollars: limit,
    remaining_microdollars: limit - reserved,
  };
}
async function rejects(
  work: () => Promise<unknown>,
  kind: new (...args: never[]) => Error,
) {
  try {
    await work();
  } catch (error) {
    assert(
      error instanceof kind,
      `Unexpected error type: ${(error as Error).name}`,
    );
    return error;
  }
  throw new Error("Expected failure");
}
function fixture(mode = "allowed") {
  const reservations: Params[] = [];
  const order: string[] = [];
  const admin: MonthlyAIBudgetAdmin = {
    rpc(name, params) {
      assert(name === "reserve_monthly_ai_budget");
      order.push("reserve");
      reservations.push(params);
      const result = Promise.resolve({
        data: mode === "malformed" ? { allowed: true } : receipt(params, mode),
        error: mode === "error"
          ? { message: "Synthetic database error" }
          : null,
      });
      return Object.assign(result, {
        abortSignal: (_signal: AbortSignal) => result,
      });
    },
  };
  const options: GoogleTTSOptions = {
    budget: { admin, userId, feature: "voice.tts" },
  };
  return {
    reservations,
    order,
    options,
    client: new GoogleTTSClient({ apiKey: "synthetic-only" }),
  };
}
async function withFetch(fetcher: typeof fetch, work: () => Promise<void>) {
  const previous = globalThis.fetch;
  globalThis.fetch = fetcher;
  try {
    await work();
  } finally {
    globalThis.fetch = previous;
  }
}
const audio = () => Response.json({ audioContent: btoa("synthetic-audio") });

Deno.test("TTS prices actual final SSML UTF8 bytes at the resolved voice rate", async () => {
  const f = fixture();
  const ssml =
    '<speak>calm café 🧘<mark name="pause"/><break time="1s"/></speak>';
  let index = 0;
  await withFetch(async (input, init) => {
    const request = new Request(input, init);
    const body = await request.json();
    f.order.push("provider");
    assert(
      f.reservations.length === index + 1,
      "Submission preceded reservation",
    );
    assert(body.input.ssml === ssml && !("text" in body.input));
    assert(
      body.voice.name ===
        (index === 0 ? "en-US-Standard-C" : "en-US-Chirp3-HD-Leda"),
    );
    assert(
      body.audioConfig.audioEncoding === "MP3" &&
        body.audioConfig.sampleRateHertz === 24000,
    );
    assert(body.audioConfig.speakingRate === (index === 0 ? 0.85 : 1.0));
    assert(request.headers.get("X-Goog-Api-Key") === "synthetic-only");
    assert(!request.signal.aborted);
    index++;
    return audio();
  }, async () => {
    for (const useChirp3HD of [false, true]) {
      const result = await f.client.textToSpeech({
        text: "ignored",
        ssml,
        voiceId: "meditation",
        useChirp3HD,
      }, f.options);
      assert(new TextDecoder().decode(result.audioData) === "synthetic-audio");
    }
  });
  const bytes = new TextEncoder().encode(ssml).length;
  assert(f.reservations[0].p_reserve_microdollars === bytes * 4);
  assert(f.reservations[1].p_reserve_microdollars === bytes * 30);
  assert(
    f.reservations.every((r) =>
      r.p_user_id === userId && r.p_feature === "voice.tts"
    ),
  );
  assert(f.order.join(",") === "reserve,provider,reserve,provider");
});

for (const mode of ["denied", "disabled", "malformed", "error"]) {
  Deno.test(`TTS ${mode} admission submits no provider request`, async () => {
    const f = fixture(mode);
    let calls = 0;
    let quotaCalls = 0;
    f.options.beforeProvider = () => {
      quotaCalls++;
      return Promise.resolve();
    };
    await withFetch(() => {
      calls++;
      return Promise.resolve(audio());
    }, async () => {
      await rejects(
        () =>
          f.client.textToSpeech({
            text: "Synthetic speech",
            voiceId: "meditation",
          }, f.options),
        mode === "denied"
          ? MonthlyAIBudgetExhaustedError
          : MonthlyAIBudgetUnavailableError,
      );
    });
    assert(calls === 0 && quotaCalls === 0 && f.reservations.length === 1);
  });
}

Deno.test("TTS each chunk and explicit retry uses a fresh backend receipt", async () => {
  const f = fixture();
  let calls = 0;
  let dailyDebits = 0;
  f.options.beforeProvider = () => {
    if (dailyDebits === 0) dailyDebits++;
    return Promise.resolve();
  };
  await withFetch(() => {
    calls++;
    assert(
      f.reservations.length === calls,
      "Paid submission was not separately admitted",
    );
    assert(
      dailyDebits === 1,
      "Retry or chunk repeated the one-time daily debit",
    );
    return Promise.resolve(
      calls === 2
        ? new Response("private provider error", { status: 429 })
        : audio(),
    );
  }, async () => {
    await f.client.textToSpeech(
      { text: "First chunk", voiceId: "meditation" },
      f.options,
    );
    const error = await rejects(
      () =>
        f.client.textToSpeech(
          { text: "Second chunk", voiceId: "meditation" },
          f.options,
        ),
      GoogleTTSError,
    );
    assert(
      !JSON.stringify(error).includes("private provider error"),
      "Provider body leaked",
    );
    assert(calls === 2, "Helper silently retried");
    await f.client.textToSpeech(
      { text: "Second chunk", voiceId: "meditation" },
      f.options,
    );
    await f.client.textToSpeech(
      { text: "Third chunk", voiceId: "meditation" },
      f.options,
    );
  });
  assert(calls === 4 && f.reservations.length === 4);
  assert(dailyDebits === 1);
  assert(new Set(f.reservations.map((r) => r.p_request_id)).size === 4);
  assert(
    f.reservations.every((r) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
        .test(r.p_request_id)
    ),
  );
});

Deno.test("TTS quota denial keeps monthly receipt and submits no paid request", async () => {
  const f = fixture();
  let calls = 0;
  const denial = new Error("Synthetic quota denial");
  f.options.beforeProvider = () => Promise.reject(denial);
  await withFetch(() => {
    calls++;
    return Promise.resolve(audio());
  }, async () => {
    const error = await rejects(
      () =>
        f.client.textToSpeech({
          text: "Synthetic speech",
          voiceId: "meditation",
        }, f.options),
      Error,
    );
    assert(error === denial);
  });
  assert(calls === 0 && f.reservations.length === 1);
});

Deno.test("TTS cancellation after quota callback prevents the paid submission", async () => {
  const f = fixture();
  const controller = new AbortController();
  let calls = 0;
  f.options.signal = controller.signal;
  f.options.beforeProvider = () => {
    controller.abort();
    return Promise.resolve();
  };
  await withFetch(() => {
    calls++;
    return Promise.resolve(audio());
  }, async () => {
    await rejects(
      () =>
        f.client.textToSpeech({
          text: "Synthetic speech",
          voiceId: "meditation",
        }, f.options),
      DOMException,
    );
  });
  assert(calls === 0 && f.reservations.length === 1);
});

Deno.test("TTS invalid input and unsupported resolved voices fail before reservation", async () => {
  const f = fixture();
  let calls = 0;
  await withFetch(() => {
    calls++;
    return Promise.resolve(audio());
  }, async () => {
    for (const text of ["", " ", "é".repeat(2501)]) {
      await rejects(
        () => f.client.textToSpeech({ text, voiceId: "meditation" }, f.options),
        GoogleTTSError,
      );
    }
    for (
      const [presets, useChirp3HD] of [[GOOGLE_VOICE_PRESETS, false], [
        CHIRP3_HD_PRESETS,
        true,
      ]] as const
    ) {
      const previous = presets.meditation.voiceName;
      presets.meditation.voiceName = "en-US-Neural2-A";
      try {
        await rejects(
          () =>
            f.client.textToSpeech({
              text: "Synthetic speech",
              voiceId: "meditation",
              useChirp3HD,
            }, f.options),
          GoogleTTSError,
        );
      } finally {
        presets.meditation.voiceName = previous;
      }
    }
    await rejects(
      () =>
        f.client.textToSpeech({
          text: "Synthetic speech",
          voiceId: "meditation",
        }, undefined as unknown as GoogleTTSOptions),
      MonthlyAIBudgetUnavailableError,
    );
    await rejects(
      () =>
        f.client.textToSpeech({
          text: "Synthetic speech",
          voiceId: "meditation",
        }, {
          budget: {
            ...f.options.budget,
            feature: "client.override",
          } as unknown as GoogleTTSOptions["budget"],
        }),
      MonthlyAIBudgetUnavailableError,
    );
  });
  assert(calls === 0 && f.reservations.length === 0);
});

Deno.test("TTS exact 5000-byte input is bounded and unknown preset keeps supported default", async () => {
  const f = fixture();
  await withFetch((_input, init) => {
    const body = JSON.parse(String(init?.body));
    assert(body.voice.name === GOOGLE_VOICE_PRESETS.default.voiceName);
    return Promise.resolve(audio());
  }, async () => {
    await f.client.textToSpeech({
      text: "é".repeat(2500),
      voiceId: "unknown-preset",
    }, f.options);
  });
  assert(f.reservations[0].p_reserve_microdollars === 20_000);
});

Deno.test("TTS pre-aborted request does not reserve or submit", async () => {
  const f = fixture();
  const controller = new AbortController();
  controller.abort();
  let calls = 0;
  await withFetch(() => {
    calls++;
    return Promise.resolve(audio());
  }, async () => {
    await rejects(
      () =>
        f.client.textToSpeech({
          text: "Synthetic speech",
          voiceId: "meditation",
        }, { ...f.options, signal: controller.signal }),
      MonthlyAIBudgetUnavailableError,
    );
  });
  assert(calls === 0 && f.reservations.length === 0);
});

Deno.test("TTS 45-second bound remains active through response body consumption", async () => {
  const f = fixture();
  const previous = AbortSignal.timeout;
  let requestedTimeout = 0;
  AbortSignal.timeout = (ms) => {
    requestedTimeout = ms;
    return previous(5);
  };
  try {
    await withFetch((input, init) => {
      const request = new Request(input, init);
      return Promise.resolve(
        new Response(
          new ReadableStream({
            start(controller) {
              request.signal.addEventListener("abort", () =>
                controller.error(
                  new DOMException("Synthetic timeout", "AbortError"),
                ), { once: true });
            },
          }),
        ),
      );
    }, async () => {
      await rejects(
        () =>
          f.client.textToSpeech({
            text: "Synthetic speech",
            voiceId: "meditation",
          }, f.options),
        DOMException,
      );
    });
  } finally {
    AbortSignal.timeout = previous;
  }
  assert(requestedTimeout === 45_000 && f.reservations.length === 1);
});
