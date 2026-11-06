// Run with --allow-env and without --allow-net. All HTTP responses are synthetic;
// the real handlers and Supabase SDK run behind the Deno.serve/fetch intercepts.
type ImageEndpoint = "generate-profile-picture" | "generate-art";
type Handler = (request: Request) => Promise<Response>;
type Json = Record<string, unknown>;

const USER_ID = "10000000-0000-4000-8000-000000000001";
const GENERATION_ID = "20000000-0000-4000-8000-000000000002";
const WORK_ID = "30000000-0000-4000-8000-000000000003";
const FAKE_ENV = {
  SUPABASE_URL: "http://127.0.0.1:55321",
  SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role-key",
  SUPABASE_ANON_KEY: "synthetic-anon-key",
  OPENAI_API_KEY: "synthetic-openai-key",
};
// Synthetic JPEG marker bytes: no photograph, private prompt or real credential.
const IMAGE = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xd9));

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

async function bounded<T>(task: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      task,
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("Mocked handler timed out")),
          2000,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function waitFor(predicate: () => boolean): Promise<void> {
  const deadline = Date.now() + 2000;
  while (!predicate()) {
    assert(Date.now() < deadline, "Mocked stream cleanup timed out");
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

interface Scenario {
  authDenied?: boolean;
  quota?: "error" | "denied";
  reservation?: "error" | "denied";
  monthlyBudget?: "error" | "denied" | "disabled" | "malformed";
  providerFails?: boolean;
  premium?: boolean;
  uploadFails?: boolean;
  image?: string;
  stream?: "complete" | "no-final" | "hold";
}

class MockNetwork {
  calls: string[] = [];
  unexpected = false;
  providerBody?: Json;
  providerSignal?: AbortSignal;
  monthlyReservations: Json[] = [];
  upstream?: ReadableStream<Uint8Array>;
  upstreamAborted = false;
  upload?: { path: string; contentType: string | null; bytes: number };
  statuses: string[] = [];
  private quotaReads = 0;
  private stopUpstream?: () => void;

  constructor(
    readonly endpoint: ImageEndpoint,
    readonly scenario: Scenario = {},
  ) {}

  readonly fetch: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.href === "https://api.openai.com/v1/images/generations") {
      this.calls.push("provider");
      this.providerBody = await request.json();
      this.providerSignal = request.signal;
      if (this.scenario.providerFails) {
        return new Response(null, { status: 503 });
      }
      const image = this.scenario.image ?? IMAGE;
      if (!this.providerBody!.stream) {
        return Response.json({ data: [{ b64_json: image }] });
      }
      const encoder = new TextEncoder();
      const mode = this.scenario.stream ?? "complete";
      const partial = `data: ${
        JSON.stringify({
          type: "image_generation.partial_image",
          partial_image_index: 0,
          b64_json: IMAGE,
        })
      }\n\n`;
      const final = mode === "complete"
        ? `data: ${
          JSON.stringify({
            type: "image_generation.completed",
            b64_json: image,
          })
        }\n\n`
        : "";
      this.upstream = new ReadableStream<Uint8Array>({
        start: (controller) => {
          if (mode === "hold") {
            controller.enqueue(encoder.encode(partial));
            const abort = () => {
              this.upstreamAborted = true;
              controller.error(
                new DOMException("Synthetic cancellation", "AbortError"),
              );
            };
            request.signal.addEventListener("abort", abort, { once: true });
            this.stopUpstream = () => {
              request.signal.removeEventListener("abort", abort);
              try {
                controller.close();
              } catch { /* already closed or errored */ }
            };
          } else {
            // Split JSON and SSE delimiters across chunks to exercise real framing.
            const bytes = encoder.encode(
              partial + "data: invalid-json\n\n" + final + "data: [DONE]\n\n",
            );
            for (
              const [start, end] of [[0, 7], [7, 39], [39, bytes.length - 1], [
                bytes.length - 1,
                bytes.length,
              ]]
            ) {
              controller.enqueue(bytes.slice(start, end));
            }
            controller.close();
          }
        },
      });
      return new Response(this.upstream, {
        headers: { "Content-Type": "text/event-stream" },
      });
    }
    if (url.origin !== FAKE_ENV.SUPABASE_URL) return this.rejectRoute();
    const path = url.pathname;
    if (path === "/auth/v1/user" && request.method === "GET") {
      this.calls.push("auth");
      return this.scenario.authDenied
        ? Response.json(
          { message: "Synthetic invalid token", code: "bad_jwt" },
          { status: 401 },
        )
        : Response.json({
          id: USER_ID,
          aud: "authenticated",
          role: "authenticated",
        });
    }
    if (path === "/rest/v1/rpc/check_rate_limit" && request.method === "POST") {
      this.calls.push("rate-limit");
      return Response.json([{
        allowed: true,
        remaining: 4,
        reset_at: "2030-01-01T00:00:00Z",
      }]);
    }
    if (
      path === "/rest/v1/rpc/get_creative_quota" && request.method === "POST"
    ) {
      this.calls.push("quota");
      assert(
        request.headers.get("apikey") === FAKE_ENV.SUPABASE_ANON_KEY,
        "Quota must use the user-scoped client",
      );
      if (this.scenario.quota === "error") {
        return Response.json({
          message: "Synthetic quota error",
          code: "XX000",
        }, { status: 500 });
      }
      return Response.json([{
        ai_art_count: this.scenario.quota === "denied" ? 3 : this.quotaReads++,
        ai_art_limit: 3,
        is_premium: this.scenario.premium ?? false,
      }]);
    }
    if (path === "/rest/v1/rpc/reserve_monthly_ai_budget") {
      this.calls.push("monthly-budget");
      assert(
        request.headers.get("apikey") === FAKE_ENV.SUPABASE_SERVICE_ROLE_KEY,
        "Monthly budget must use the service client",
      );
      const params = await request.json();
      this.monthlyReservations.push(params);
      assert(
        params.p_user_id === USER_ID,
        "Budget owner must be verified user",
      );
      assert(
        params.p_feature ===
          (this.endpoint === "generate-art" ? "art.image" : "profile.image"),
        "Feature must be fixed by the endpoint",
      );
      assert(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
          .test(params.p_request_id),
        "Budget request must use a backend UUID",
      );
      if (this.scenario.monthlyBudget === "error") {
        return Response.json({ code: "XX000", message: "Synthetic error" }, {
          status: 503,
        });
      }
      if (this.scenario.monthlyBudget === "malformed") {
        return Response.json({ allowed: true });
      }
      const denied = this.scenario.monthlyBudget === "denied";
      const disabled = this.scenario.monthlyBudget === "disabled";
      const limit = disabled ? 0 : 10_000_000;
      const reserved = denied
        ? limit
        : disabled
        ? 0
        : params.p_reserve_microdollars;
      return Response.json({
        allowed: !denied && !disabled,
        reason: denied ? "exhausted" : disabled ? "disabled" : "reserved",
        request_id: params.p_request_id,
        user_id: params.p_user_id,
        feature: params.p_feature,
        month_start: "2026-10-01",
        reserve_microdollars: params.p_reserve_microdollars,
        reserved_microdollars: reserved,
        limit_microdollars: limit,
        remaining_microdollars: limit - reserved,
      });
    }
    if (
      path === "/rest/v1/rpc/reserve_ai_image_quota" &&
      request.method === "POST"
    ) {
      this.calls.push("reserve");
      assert(
        request.headers.get("apikey") === FAKE_ENV.SUPABASE_SERVICE_ROLE_KEY,
        "Reservation must use the admin client",
      );
      const body = await request.json();
      assert(
        body.p_user_id === USER_ID,
        "Reservation must belong to the authenticated user",
      );
      return this.scenario.reservation === "error"
        ? Response.json({
          message: "Synthetic reservation error",
          code: "XX000",
        }, { status: 503 })
        : Response.json(this.scenario.reservation !== "denied");
    }
    if (path === "/rest/v1/ai_art_generations" && request.method === "POST") {
      this.calls.push("generation");
      return Response.json({ id: GENERATION_ID }, { status: 201 });
    }
    if (path === "/rest/v1/ai_art_generations" && request.method === "PATCH") {
      const body = await request.json();
      this.statuses.push(body.generation_status);
      this.calls.push("status");
      return new Response(null, { status: 204 });
    }
    if (path === "/rest/v1/creative_works" && request.method === "POST") {
      this.calls.push("work");
      return Response.json({ id: WORK_ID }, { status: 201 });
    }
    if (
      path.startsWith("/storage/v1/object/sign/creative-works/") &&
      request.method === "POST"
    ) {
      this.calls.push("sign");
      return Response.json({
        signedURL: path.replace("/storage/v1", "") +
          "?token=synthetic-short-lived",
      });
    }
    const bucket = this.endpoint === "generate-profile-picture"
      ? "profile-pictures"
      : "creative-works";
    if (
      path.startsWith(`/storage/v1/object/${bucket}/${USER_ID}/`) &&
      request.method === "POST"
    ) {
      this.calls.push("upload");
      this.upload = {
        path,
        contentType: request.headers.get("Content-Type"),
        bytes: (await request.arrayBuffer()).byteLength,
      };
      return this.scenario.uploadFails
        ? Response.json({
          statusCode: "503",
          error: "Unavailable",
          message: "Synthetic upload failure",
        }, { status: 503 })
        : Response.json({ Key: path.slice("/storage/v1/object/".length) });
    }
    return this.rejectRoute();
  };

  private rejectRoute(): never {
    this.unexpected = true;
    throw new Error("Unexpected HTTP route in fully mocked image test");
  }

  cleanup() {
    this.stopUpstream?.();
  }
}

function imageRequest(
  endpoint: ImageEndpoint,
  stream = false,
  token: string | null = "synthetic-user-token",
  signal?: AbortSignal,
) {
  return new Request(`http://localhost/${endpoint}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ prompt: "A calm blue mountain", stream }),
    signal,
  });
}

async function sseEvents(response: Response): Promise<Json[]> {
  assert(response.status === 200, "SSE request failed before streaming");
  assert(
    response.headers.get("Content-Type") === "text/event-stream",
    "Expected SSE response",
  );
  const text = await bounded(response.text());
  return text.split("\n").filter((line) => line.startsWith("data: ")).map((
    line,
  ) => JSON.parse(line.slice(6)));
}

function assertReservedBeforeProvider(mock: MockNetwork) {
  const monthly = mock.calls.indexOf("monthly-budget");
  const reserve = mock.calls.indexOf("reserve"),
    provider = mock.calls.indexOf("provider");
  assert(
    reserve >= 0 && provider > reserve,
    "Provider was called before quota reservation",
  );
  assert(
    monthly >= 0 && monthly < reserve,
    "Monthly budget must precede daily allowance",
  );
  assert(
    mock.monthlyReservations.length === 1,
    "Each submission needs one monthly receipt",
  );
  const expected =
    (new TextEncoder().encode(JSON.stringify(mock.providerBody?.prompt))
        .length + 1024) * 2 +
    36_000 + (mock.providerBody?.stream ? 1600 : 0);
  assert(
    mock.monthlyReservations[0].p_reserve_microdollars === expected,
    "Wrong conservative image ceiling",
  );
  assert(
    mock.providerBody?.n === 1 && mock.providerBody?.size === "1024x1024",
    "Unpriced image configuration",
  );
  assert(
    mock.calls.filter((call) => call === "reserve").length === 1,
    "Usage must be reserved exactly once",
  );
  assert(
    mock.calls.filter((call) => call === "provider").length === 1,
    "Generation must contact the provider once",
  );
  assert(mock.providerSignal, "Provider fetch must have an abort signal");
}

for (const endpoint of ["generate-profile-picture", "generate-art"] as const) {
  Deno.test(`actual ${endpoint} handler with fully mocked HTTP`, async (t) => {
    const envBefore = new Map(
      Object.keys(FAKE_ENV).map((key) => [key, Deno.env.get(key)]),
    );
    const serveDescriptor = Object.getOwnPropertyDescriptor(Deno, "serve")!;
    const nativeFetch = globalThis.fetch;
    const nativeAddEventListener = globalThis.addEventListener;
    const listeners: [
      string,
      EventListenerOrEventListenerObject,
      boolean | AddEventListenerOptions | undefined,
    ][] = [];
    let handler: Handler | undefined;
    let activeMock: MockNetwork | undefined;
    try {
      for (const [key, value] of Object.entries(FAKE_ENV)) {
        Deno.env.set(key, value);
      }
      Object.defineProperty(Deno, "serve", {
        configurable: true,
        value: (value: Handler) => {
          handler = value;
        },
      });
      globalThis.fetch = ((...args) => {
        assert(activeMock, "Handler fetched outside its test scenario");
        return activeMock.fetch(args[0], args[1]);
      }) as typeof fetch;
      globalThis.addEventListener = ((
        type: string,
        listener: EventListenerOrEventListenerObject,
        options?: boolean | AddEventListenerOptions,
      ) => {
        listeners.push([type, listener, options]);
        nativeAddEventListener.call(globalThis, type, listener, options);
      }) as typeof addEventListener;
      if (endpoint === "generate-profile-picture") {
        await import(
          "../functions/generate-profile-picture/index.ts?image-handler-test"
        );
      } else {
        await import("../functions/generate-art/index.ts?image-handler-test");
      }
      globalThis.addEventListener = nativeAddEventListener;
      assert(handler, "Deno.serve did not register the actual handler");
      const invoke = (
        stream = false,
        token: string | null = "synthetic-user-token",
        signal?: AbortSignal,
      ) => bounded(handler!(imageRequest(endpoint, stream, token, signal)));
      const step = async (
        name: string,
        scenario: Scenario,
        run: (mock: MockNetwork) => Promise<void>,
      ) => {
        await t.step(name, async () => {
          const mock = activeMock = new MockNetwork(endpoint, scenario);
          try {
            await run(mock);
          } finally {
            mock.cleanup();
            if (mock.upstream) await waitFor(() => !mock.upstream!.locked);
            assert(
              !mock.unexpected,
              "Handler attempted an unmocked HTTP route",
            );
          }
        });
      };

      await step(
        "missing authorization is denied before any HTTP",
        {},
        async (mock) => {
          const response = await invoke(false, null);
          assert(response.status === 401, "Anonymous request was accepted");
          await response.text();
          assert(
            mock.calls.length === 0,
            "Anonymous request reached HTTP services",
          );
        },
      );
      await step("anonymous API key cannot reach quota or provider", {
        authDenied: true,
      }, async (mock) => {
        const response = await invoke(false, FAKE_ENV.SUPABASE_ANON_KEY);
        assert(
          response.status === 401,
          "Anonymous API key was accepted as a user token",
        );
        await response.text();
        assert(
          mock.calls.join(",") === "auth",
          "Rejected token reached quota or provider",
        );
      });
      for (const stream of [false, true]) {
        for (
          const monthlyBudget of [
            "error",
            "denied",
            "disabled",
            "malformed",
          ] as const
        ) {
          await step(
            `${
              stream ? "SSE" : "JSON"
            } monthly ${monthlyBudget} prevents allowance consumption`,
            { monthlyBudget, premium: true },
            async (mock) => {
              const response = await invoke(stream);
              assert(
                response.status === (monthlyBudget === "denied" ? 429 : 503),
                "Wrong monthly denial status",
              );
              const body = await response.json();
              assert(
                body.code ===
                  (monthlyBudget === "denied"
                    ? "monthly_ai_budget_exhausted"
                    : "monthly_ai_budget_unavailable"),
                "Missing safe budget error",
              );
              assert(
                !JSON.stringify(body).includes("microdollars"),
                "Response exposed service counters",
              );
              assert(
                mock.monthlyReservations.length === 1,
                "Admission route was not exercised",
              );
              assert(
                !mock.calls.some((call) =>
                  ["reserve", "provider", "generation", "upload"].includes(call)
                ),
                "Denied admission consumed allowance or submitted work",
              );
            },
          );
        }
        for (
          const [scenario, expected] of [
            [{ quota: "error" }, 500],
            [{ quota: "denied" }, 429],
            [{ reservation: "error" }, 503],
            [{ reservation: "denied" }, 429],
          ] as const
        ) {
          await step(
            `${stream ? "SSE" : "JSON"} fails closed for ${
              Object.keys(scenario)[0]
            } ${Object.values(scenario)[0]}`,
            scenario,
            async (mock) => {
              const response = await invoke(stream);
              assert(
                response.status === expected,
                "Quota failure or denial returned the wrong status",
              );
              const body = await response.json();
              assert(body.success !== true, "Quota failure returned success");
              assert(
                !mock.calls.includes("provider") &&
                  !mock.calls.includes("upload"),
                "Quota rejection reached provider or storage",
              );
              assert(
                !mock.calls.includes("generation"),
                "Quota rejection created a generation record",
              );
              if (scenario.quota) {
                assert(
                  !mock.calls.includes("reserve"),
                  "Rejected quota reached reservation",
                );
              } else {assert(
                  mock.calls.includes("reserve"),
                  "Reservation failure path was not exercised",
                );}
            },
          );
        }
      }
      await step(
        "enhanced Unicode prompt is priced while client overrides are ignored",
        {},
        async (mock) => {
          const response = await bounded(
            handler!(
              new Request(`http://localhost/${endpoint}`, {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                  Authorization: "Bearer synthetic-user-token",
                },
                body: JSON.stringify({
                  prompt: "Calm café 🧘",
                  style: "watercolor",
                  moodScore: 8,
                  userId: "90000000-0000-4000-8000-000000000009",
                  model: "client-model",
                  quality: "low",
                  size: "1536x1024",
                  n: 100,
                  reserveMicrodollars: 1,
                  partial_images: 0,
                }),
              }),
            ),
          );
          assert(response.status === 200, "Synthetic enhanced prompt failed");
          await response.text();
          assertReservedBeforeProvider(mock);
          assert(
            mock.providerBody?.model === "gpt-image-1-mini" &&
              mock.providerBody?.quality === undefined,
            "Client changed the priced configuration",
          );
          if (endpoint === "generate-art") {
            assert(
              String(mock.providerBody?.prompt).includes(
                "uplifting joyful mood",
              ),
              "Enhanced mood prompt was not priced",
            );
          }
        },
      );
      await step(
        "provider failure and caller retry each retain a distinct monthly reservation",
        {
          providerFails: true,
        },
        async (mock) => {
          for (const stream of [false, true]) {
            const response = await invoke(stream);
            assert(response.status >= 500, "Provider error returned success");
            await response.text();
          }
          assert(
            mock.monthlyReservations.length === 2,
            "Retry reused a monthly reservation",
          );
          assert(
            mock.monthlyReservations[0].p_request_id !==
              mock.monthlyReservations[1].p_request_id,
            "Retry needs fresh backend UUID",
          );
          assert(
            mock.calls.filter((call) => call === "provider").length === 2,
            "Expected one paid attempt per invocation",
          );
          assert(
            !mock.calls.includes("upload"),
            "Provider failure reached storage",
          );
        },
      );
      await step(
        "JSON reserves before provider and persists before success",
        {},
        async (mock) => {
          const response = await invoke();
          assert(response.status === 200, "JSON generation failed");
          const body = await response.json();
          assert(
            body.success === true && body.generationId && body.imageUrl,
            "Missing persisted generation metadata",
          );
          assertReservedBeforeProvider(mock);
          assert(
            mock.calls.includes("upload"),
            "Successful generation skipped storage",
          );
          assert(
            mock.providerBody?.model === "gpt-image-1-mini",
            "Unexpected image model",
          );
          if (endpoint === "generate-profile-picture") {
            assert(
              mock.providerBody?.output_format === "jpeg",
              "Avatar provider must return JPEG",
            );
            assert(
              mock.upload?.contentType === "image/jpeg" &&
                mock.upload.path.endsWith(".jpg"),
              "Avatar upload violates JPEG bucket type",
            );
            assert(
              mock.upload.bytes <= 512 * 1024,
              "Avatar exceeds bucket size",
            );
            assert(
              body.storagePath.startsWith(`${USER_ID}/generated/`) &&
                body.quotaRemaining === 2,
              "Avatar path or remaining quota is incorrect",
            );
          } else {
            assert(
              body.creativeWorkId === WORK_ID,
              "Creative work was not persisted",
            );
            assert(
              mock.statuses.includes("completed"),
              "Generation record was not completed",
            );
          }
        },
      );
      await step("JSON upload failure cannot report success", {
        uploadFails: true,
      }, async (mock) => {
        const response = await invoke();
        assert(
          response.status >= 500,
          "Upload failure returned a successful status",
        );
        const body = await response.json();
        assert(
          body.success !== true && body.error,
          "Upload failure reported successful generation",
        );
        assertReservedBeforeProvider(mock);
        assert(
          mock.calls.includes("upload"),
          "Storage failure was not exercised",
        );
        assert(
          !mock.calls.includes("work") && !mock.statuses.includes("completed"),
          "Failed upload was persisted as completed",
        );
      });
      await step("fragmented SSE emits partial then a persisted completion", {
        stream: "complete",
      }, async (mock) => {
        const events = await sseEvents(await invoke(true));
        assert(
          events.length === 2 && events[0].type === "partial" &&
            events[1].type === "complete",
          "SSE must emit partial then one completion",
        );
        assert(
          events[0].index === 0 && events[0].imageBase64 === IMAGE,
          "Partial image event was corrupted",
        );
        assert(
          events[1].success === true && events[1].imageBase64 === IMAGE &&
            events[1].imageUrl,
          "SSE completion is missing saved image metadata",
        );
        assertReservedBeforeProvider(mock);
        assert(
          mock.providerBody?.stream === true,
          "Provider streaming was not requested",
        );
        assert(mock.calls.includes("upload"), "SSE success skipped storage");
        if (endpoint === "generate-profile-picture") {
          assert(
            mock.providerBody.output_format === "jpeg",
            "Streaming avatar must request JPEG",
          );
          assert(
            mock.upload?.contentType === "image/jpeg" &&
              mock.upload.path.endsWith(".jpg"),
            "Streaming avatar upload violates JPEG bucket type",
          );
        } else {assert(
            mock.statuses.includes("completed"),
            "Streaming art was not marked completed",
          );}
      });
      await step(
        "SSE ending without a final image emits error and never uploads",
        { stream: "no-final" },
        async (mock) => {
          const events = await sseEvents(await invoke(true));
          assert(
            events.some((event) => event.type === "partial"),
            "No-final scenario omitted the partial image",
          );
          assert(
            events.some((event) =>
              event.type === "error" && event.error === "No image generated"
            ),
            "Missing final image did not emit terminal error",
          );
          assert(
            !events.some((event) =>
              event.type === "complete" || event.success === true
            ),
            "Partial image was treated as a final success",
          );
          assert(
            !mock.calls.includes("upload") && !mock.calls.includes("work"),
            "Missing final image was persisted",
          );
          if (endpoint === "generate-art") {
            assert(
              mock.statuses.includes("failed"),
              "No-final art was not marked failed",
            );
          }
        },
      );
      await step("SSE upload failure emits error without completion", {
        stream: "complete",
        uploadFails: true,
      }, async (mock) => {
        const events = await sseEvents(await invoke(true));
        assert(
          events.some((event) => event.type === "error"),
          "SSE storage failure omitted terminal error",
        );
        assert(
          !events.some((event) =>
            event.type === "complete" || event.success === true
          ),
          "SSE storage failure reported success",
        );
        assert(
          mock.calls.includes("upload") && !mock.statuses.includes("completed"),
          "SSE storage failure was not exercised correctly",
        );
      });
      for (const cancellation of ["reader", "request"] as const) {
        await step(
          `${cancellation} cancellation aborts the upstream provider stream`,
          { stream: "hold" },
          async (mock) => {
            const controller = new AbortController();
            const response = await invoke(
              true,
              "synthetic-user-token",
              controller.signal,
            );
            const reader = response.body!.getReader();
            try {
              const partial = await bounded(reader.read());
              assert(
                !partial.done,
                "Provider stream was not active before cancellation",
              );
              if (cancellation === "reader") await bounded(reader.cancel());
              else {
                controller.abort();
                // Consume the terminal error so the handler can release its writer.
                await bounded((async () => {
                  while (!(await reader.read()).done) { /* drain */ }
                })());
              }
              await waitFor(() => mock.upstreamAborted);
              assert(
                mock.providerSignal?.aborted,
                "Client cancellation did not propagate to provider signal",
              );
              assert(
                !mock.calls.includes("upload") && !mock.calls.includes("work"),
                "Cancelled generation persisted an image",
              );
              if (endpoint === "generate-art") {
                await waitFor(() => mock.statuses.includes("failed"));
              }
            } finally {
              await reader.cancel().catch(() => {});
              reader.releaseLock();
            }
          },
        );
      }
      if (endpoint === "generate-profile-picture") {
        for (const stream of [false, true]) {
          for (const bytes of [512 * 1024, 512 * 1024 + 1]) {
            await step(
              `${
                stream ? "SSE" : "JSON"
              } enforces avatar bucket boundary at ${bytes} bytes`,
              {
                stream: "complete",
                image: btoa("x".repeat(bytes)),
              },
              async (mock) => {
                const response = await invoke(stream);
                if (stream) {
                  const events = await sseEvents(response);
                  assert(
                    events.some((event) =>
                      event.type ===
                        (bytes === 512 * 1024 ? "complete" : "error")
                    ),
                    "SSE avatar size boundary was not enforced",
                  );
                  if (bytes > 512 * 1024) {
                    assert(
                      !events.some((event) => event.type === "complete"),
                      "Oversized SSE avatar reported success",
                    );
                  }
                } else {
                  assert(
                    response.status === (bytes === 512 * 1024 ? 200 : 422),
                    "JSON avatar size boundary returned wrong status",
                  );
                  await response.text();
                }
                assert(
                  (mock.upload?.bytes === bytes) === (bytes === 512 * 1024),
                  "Avatar size boundary uploaded the wrong bytes",
                );
                assert(
                  mock.calls.includes("upload") === (bytes === 512 * 1024),
                  "Oversized avatar reached storage",
                );
              },
            );
          }
        }
      }
    } finally {
      activeMock?.cleanup();
      globalThis.fetch = nativeFetch;
      Object.defineProperty(Deno, "serve", serveDescriptor);
      globalThis.addEventListener = nativeAddEventListener;
      for (const [type, listener, options] of listeners) {
        globalThis.removeEventListener(type, listener, options);
      }
      for (const [key, value] of envBefore) {
        if (value === undefined) Deno.env.delete(key);
        else Deno.env.set(key, value);
      }
    }
  });
}
