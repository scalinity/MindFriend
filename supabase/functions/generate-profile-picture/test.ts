import { fixture, other, owner, reset } from "./test-supabase.ts";
import { decodeJPEG, MAX_IMAGE_BYTES } from "./image.ts";

const originalServe = Deno.serve;
Deno.serve = (() => ({})) as unknown as typeof Deno.serve;
const { handler } = await import("./index.ts");
Deno.serve = originalServe;

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
function equal(actual: unknown, expected: unknown) {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`,
  );
}

// Original 8x8 constant-gray baseline JPEG, authored from JPEG segment syntax.
// DC difference 0 and AC EOB each use a one-bit Huffman code; pad with ones.
// No third-party image, encoder, metadata, or user data is included.
const jpeg = new Uint8Array([
  0xff,
  0xd8,
  0xff,
  0xdb,
  0,
  67,
  0,
  ...new Array(64).fill(1),
  0xff,
  0xc0,
  0,
  11,
  8,
  0,
  8,
  0,
  8,
  1,
  1,
  0x11,
  0,
  0xff,
  0xc4,
  0,
  38,
  0,
  1,
  ...new Array(15).fill(0),
  0,
  0x10,
  1,
  ...new Array(15).fill(0),
  0,
  0xff,
  0xda,
  0,
  8,
  1,
  1,
  0,
  0,
  63,
  0,
  0x3f,
  0xff,
  0xd9,
]);
function base64(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
const imageBase64 = base64(jpeg);
function alteredJPEG(offset: number, value: number) {
  const copy = jpeg.slice();
  copy[offset] = value;
  return base64(copy);
}
const encoder = new TextEncoder();
function sse(event: unknown, ending = "\n\n") {
  return `data: ${JSON.stringify(event)}${ending}`;
}
function completed() {
  return { type: "image_generation.completed", b64_json: imageBase64 };
}
function streamBytes(bytes: Uint8Array, fragment = bytes.length) {
  return new Response(
    new ReadableStream<Uint8Array>({
      start(controller) {
        for (let offset = 0; offset < bytes.length; offset += fragment) {
          controller.enqueue(bytes.slice(offset, offset + fragment));
        }
        controller.close();
      },
    }),
    { headers: { "Content-Type": "text/event-stream" } },
  );
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

type Scenario = {
  provider?: (init: RequestInit) => Response | Promise<Response>;
  storage?: (init: RequestInit) => Response | Promise<Response>;
  providerCalls: RequestInit[];
  storageCalls: RequestInit[];
  logs: string[];
};
async function scenario(run: (state: Scenario) => Promise<void>) {
  reset();
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const originalTimeout = globalThis.setTimeout;
  const env = {
    SUPABASE_URL: "https://synthetic.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role",
    SUPABASE_ANON_KEY: "synthetic-anon-key",
    OPENAI_API_KEY: "synthetic-provider-key",
  };
  const previous = Object.fromEntries(
    Object.keys(env).map((key) => [key, Deno.env.get(key)]),
  );
  for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
  const state: Scenario = { providerCalls: [], storageCalls: [], logs: [] };
  console.error = (...args: unknown[]) => {
    state.logs.push(args.join(" "));
  };
  globalThis.fetch = ((input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = String(input);
    if (url === "https://api.openai.com/v1/images/generations") {
      state.providerCalls.push(init);
      fixture.calls.push({ name: "provider", admin: false });
      const body = JSON.parse(String(init.body));
      equal(body.model, "gpt-image-1-mini");
      equal(body.size, "1024x1024");
      equal(body.n, 1);
      equal(body.output_format, "jpeg");
      equal(body.output_compression, 80);
      assert(!("quality" in body));
      if (body.stream) equal(body.partial_images, 2);
      return Promise.resolve(
        state.provider?.(init) ??
          Response.json({ data: [{ b64_json: imageBase64 }] }),
      );
    }
    if (
      url.startsWith(
        `https://synthetic.invalid/storage/v1/object/profile-pictures/${owner}/generated/`,
      )
    ) {
      state.storageCalls.push(init);
      equal(
        new Headers(init.headers).get("authorization"),
        "Bearer synthetic-caller-token",
      );
      equal(new Headers(init.headers).get("content-type"), "image/jpeg");
      equal(new Headers(init.headers).get("x-upsert"), "false");
      assert(init.signal);
      return Promise.resolve(
        state.storage?.(init) ?? Response.json({ Key: "synthetic" }),
      );
    }
    throw new Error(
      "Unexpected fetch; external traffic is forbidden in these tests",
    );
  }) as typeof fetch;
  try {
    await run(state);
    assert(state.providerCalls.length <= 1, "Provider must never be retried");
    const logs = state.logs.join("\n");
    for (
      const sensitive of [
        imageBase64,
        "synthetic-provider-key",
        "synthetic-caller-token",
        "https://",
        "quiet moon avatar",
      ]
    ) {
      assert(!logs.includes(sensitive), "Sensitive content leaked to logs");
    }
  } finally {
    globalThis.fetch = originalFetch;
    console.error = originalError;
    globalThis.setTimeout = originalTimeout;
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}
function request(
  stream = false,
  body: unknown = { prompt: "quiet moon avatar", stream },
  signal?: AbortSignal,
  authorization: string | null = "Bearer synthetic-caller-token",
) {
  return new Request(
    "https://synthetic.invalid/functions/v1/generate-profile-picture",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(authorization ? { Authorization: authorization } : {}),
      },
      body: JSON.stringify(body),
      signal,
    },
  );
}
async function events(response: Response) {
  equal(response.headers.get("content-type"), "text/event-stream");
  return (await response.text()).trim().split("\n\n").map((line) =>
    JSON.parse(line.slice(6))
  );
}
async function result(stream: boolean, response: Response) {
  if (!stream) return await response.json();
  const messages = await events(response);
  assert(
    !messages.some((event) => event.type === "complete"),
    "Failure emitted a complete event",
  );
  const last = messages.at(-1);
  equal(last.type, "error");
  return last;
}
function validateSuccess(body: Record<string, unknown>) {
  equal(body.success, true);
  equal(body.imageBase64, imageBase64);
  equal(body.quotaRemaining, 4);
  assert(typeof body.generationId === "string");
  equal(body.storagePath, `${owner}/generated/${body.generationId}.jpg`);
  equal(
    body.imageUrl,
    `https://synthetic.invalid/storage/v1/object/public/profile-pictures/${body.storagePath}`,
  );
  equal(fixture.uploads.length, 1);
  const upload = fixture.uploads[0];
  equal(upload.admin, false);
  equal(upload.key, "synthetic-anon-key");
  equal(upload.bucket, "profile-pictures");
  equal(upload.options, { contentType: "image/jpeg", upsert: false });
  equal([...upload.bytes], [...jpeg]);
  const calls = fixture.calls.map((call) => call.name);
  assert(
    calls.indexOf("reserve_monthly_ai_budget") < calls.indexOf("provider"),
  );
  assert(calls.indexOf("reserve_ai_image_quota") < calls.indexOf("provider"));
  equal(
    fixture.calls.find((call) => call.name === "reserve_ai_image_quota")?.params
      ?.p_user_id,
    owner,
  );
}

Deno.test("JSON success preserves all released metadata and uploads a caller-owned JPEG", () =>
  scenario(async (state) => {
    const response = await handler(request());
    equal(response.status, 200);
    equal(response.headers.get("content-type"), "application/json");
    validateSuccess(await response.json());
    equal(state.providerCalls.length, 1);
    equal(state.storageCalls.length, 1);
  }));

Deno.test("SSE previews preserve their shape; completion waits for a successful upload", () =>
  scenario(async (state) => {
    const uploaded = deferred<Response>();
    const uploadStarted = deferred<void>();
    state.storage = () => {
      uploadStarted.resolve();
      return uploaded.promise;
    };
    state.provider = () =>
      streamBytes(encoder.encode(
        sse({
          type: "image_generation.partial_image",
          partial_image_index: 0,
          b64_json: imageBase64,
        }) +
          sse({
            type: "image_generation.partial_image",
            partial_image_index: 1,
            b64_json: imageBase64,
          }) +
          sse(completed()),
      ));
    const response = await handler(request(true));
    const reader = response.body!.getReader();
    const first = JSON.parse(
      new TextDecoder().decode((await reader.read()).value).slice(6),
    );
    equal(first.type, "partial");
    equal(first.index, 0);
    equal(first.imageBase64, imageBase64);
    await reader.read();
    await uploadStarted.promise;
    let delivered = false;
    const pending = reader.read().then((chunk) => {
      delivered = true;
      return chunk;
    });
    await Promise.resolve();
    equal(delivered, false);
    uploaded.resolve(Response.json({ Key: "synthetic" }));
    const final = JSON.parse(
      new TextDecoder().decode((await pending).value).slice(6),
    );
    equal(final.type, "complete");
    equal(final.generationId, first.generationId);
    validateSuccess(final);
    equal((await reader.read()).done, true);
    reader.releaseLock();
    equal(state.providerCalls.length, 1);
  }));

for (const newline of ["\n", "\r\n"]) {
  for (const ending of ["", newline, newline + newline]) {
    Deno.test(`fragmented UTF-8 ${JSON.stringify(newline)} final event ending ${JSON.stringify(ending)}`, () =>
      scenario(async (state) => {
        const data = { ...completed(), note: "original synthetic 🌙" };
        state.provider = () =>
          streamBytes(
            encoder.encode(
              `: keepalive${newline}${newline}event: image_generation.completed${newline}data:${
                JSON.stringify(data)
              }${ending}`,
            ),
            1,
          );
        const messages = await events(await handler(request(true)));
        equal(messages.length, 1);
        equal(messages[0].type, "complete");
        validateSuccess(messages[0]);
      }));
  }
}

Deno.test("SSE named/multiline data and legacy data-array final events remain supported", () =>
  scenario(async (state) => {
    state.provider = () =>
      streamBytes(
        encoder.encode(
          `event: image_generation.completed\r\ndata: {\r\ndata: "data":[{"b64_json":"${imageBase64}"}]}\r\n\r\ndata: [DONE]\r\n\r\n`,
        ),
        3,
      );
    const messages = await events(await handler(request(true)));
    equal(messages.length, 1);
    validateSuccess(messages[0]);
  }));

const invalidImages: [string, unknown, string][] = [
  [
    "PNG",
    base64(new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10])),
    "invalid_image_format",
  ],
  ["oversize", base64(new Uint8Array(MAX_IMAGE_BYTES + 1)), "image_too_large"],
  ["invalid base64", "!not base64!", "invalid_image_encoding"],
  [
    "noncanonical base64",
    "/x==",
    "invalid_image_encoding",
  ],
  ["truncated JPEG", base64(jpeg.slice(0, -1)), "invalid_image_format"],
  [
    "signature-only JPEG",
    base64(new Uint8Array([255, 216, 1, 255, 217])),
    "invalid_image_format",
  ],
  [
    "trailing bytes",
    base64(new Uint8Array([...jpeg, 0])),
    "invalid_image_format",
  ],
  ["wrong image type", 42, "invalid_image_encoding"],
  ["zero quantization value", alteredJPEG(7, 0), "invalid_image_format"],
  [
    "missing quantization table",
    alteredJPEG(jpeg.indexOf(0xc0) + 11, 1),
    "invalid_image_format",
  ],
  [
    "missing Huffman table",
    alteredJPEG(jpeg.indexOf(0xda) + 5, 0x11),
    "invalid_image_format",
  ],
];
for (const stream of [false, true]) {
  for (const [name, image, code] of invalidImages) {
    Deno.test(`${stream ? "SSE" : "JSON"} rejects ${name} before Storage`, () =>
      scenario(async (state) => {
        state.provider = () =>
          stream
            ? streamBytes(
              encoder.encode(
                sse({ type: "image_generation.completed", b64_json: image }),
              ),
            )
            : Response.json({ data: [{ b64_json: image }] });
        const body = await result(stream, await handler(request(stream)));
        equal(body.code, code);
        equal(fixture.uploads.length, 0);
        equal(state.providerCalls.length, 1);
      }));
  }
  Deno.test(`${stream ? "SSE" : "JSON"} missing final image never succeeds`, () =>
    scenario(async (state) => {
      state.provider = () =>
        stream
          ? streamBytes(
            encoder.encode(
              sse({
                type: "image_generation.partial_image",
                partial_image_index: 0,
                b64_json: imageBase64,
              }) + "data: [DONE]\n\n",
            ),
          )
          : Response.json({ data: [] });
      equal(
        (await result(stream, await handler(request(stream)))).code,
        "image_missing",
      );
      equal(fixture.uploads.length, 0);
      equal(state.providerCalls.length, 1);
    }));
  for (
    const [status, code] of [[403, "avatar_upload_denied"], [
      415,
      "avatar_upload_rejected",
    ], [500, "avatar_upload_failed"]] as const
  ) {
    Deno.test(`${stream ? "SSE" : "JSON"} Storage ${status} reports an upload error without success`, () =>
      scenario(async (state) => {
        state.provider = () =>
          stream
            ? streamBytes(encoder.encode(sse(completed())))
            : Response.json({ data: [{ b64_json: imageBase64 }] });
        state.storage = () => new Response("synthetic denied", { status });
        const body = await result(stream, await handler(request(stream)));
        equal(body.code, code);
        assert(
          body.error.includes(
            status === 403
              ? "permission"
              : status === 415
              ? "rejected"
              : "save",
          ),
        );
        equal(state.providerCalls.length, 1);
        equal(fixture.uploads.length, 1);
      }));
  }
  Deno.test(`${stream ? "SSE" : "JSON"} provider HTTP failure is redacted and never retried`, () =>
    scenario(async (state) => {
      state.provider = () =>
        new Response(
          "quiet moon avatar synthetic-provider-key private provider error",
          { status: 500 },
        );
      const response = await handler(request(stream));
      equal(response.status, 502);
      equal((await response.json()).code, "provider_failed");
      equal(fixture.uploads.length, 0);
      equal(state.providerCalls.length, 1);
    }));
}

Deno.test("SSE provider error after preview cannot complete", () =>
  scenario(async (state) => {
    state.provider = () =>
      streamBytes(
        encoder.encode(
          sse({
            type: "image_generation.partial_image",
            partial_image_index: 0,
            b64_json: imageBase64,
          }) +
            sse({
              type: "error",
              error: { message: "quiet moon avatar synthetic-provider-key" },
            }),
        ),
      );
    equal(
      (await result(true, await handler(request(true)))).code,
      "provider_failed",
    );
    equal(fixture.uploads.length, 0);
  }));

for (const stream of [false, true]) {
  Deno.test(`${stream ? "SSE" : "JSON"} truncated provider response cannot complete`, () =>
    scenario(async (state) => {
      state.provider = () =>
        new Response(
          stream
            ? `data: ${JSON.stringify(completed()).slice(0, -4)}`
            : '{"data":[{"b64_json":',
        );
      equal(
        (await result(stream, await handler(request(stream)))).code,
        "provider_response_invalid",
      );
      equal(fixture.uploads.length, 0);
    }));
}

for (
  const [name, body] of [
    ["short", { prompt: "ab" }],
    ["long", { prompt: "x".repeat(201) }],
    ["non-string", { prompt: 123 }],
    ["null", null],
    ["object", { prompt: {} }],
  ] as const
) {
  Deno.test(`invalid ${name} prompt is rejected before budget or provider`, () =>
    scenario(async (state) => {
      const response = await handler(request(false, body));
      equal(response.status, 400);
      equal((await response.json()).code, "invalid_prompt");
      equal(fixture.calls.map((call) => call.name), ["auth"]);
      equal(state.providerCalls.length, 0);
    }));
}
for (const field of ["userId", "user_id", "ownerId", "owner_id", "owner"]) {
  Deno.test(`${field} override is rejected before budget or provider`, () =>
    scenario(async (state) => {
      const response = await handler(
        request(false, { prompt: "moon avatar", [field]: other }),
      );
      equal(response.status, 403);
      equal((await response.json()).code, "owner_mismatch");
      equal(fixture.calls.map((call) => call.name), ["auth"]);
      equal(state.providerCalls.length, 0);
    }));
}

for (const mode of ["missing", "invalid", "anonymous"] as const) {
  Deno.test(`${mode} auth is rejected before quota, budget or provider`, () =>
    scenario(async (state) => {
      if (mode === "invalid") {
        fixture.authError = { message: "synthetic invalid token" };
      }
      if (mode === "anonymous") fixture.user!.is_anonymous = true;
      const response = await handler(
        request(
          false,
          undefined,
          undefined,
          mode === "missing" ? null : "Bearer synthetic-caller-token",
        ),
      );
      equal(response.status, mode === "anonymous" ? 403 : 401);
      await response.body?.cancel();
      assert(fixture.calls.every((call) => call.name === "auth"));
      equal(state.providerCalls.length, 0);
    }));
}

for (
  const mode of [
    "read-denial",
    "read-error",
    "atomic-denial",
    "atomic-error",
    "malformed-atomic",
    "budget-exhausted",
    "budget-error",
  ] as const
) {
  Deno.test(`${mode} prevents the provider attempt`, () =>
    scenario(async (state) => {
      if (mode === "read-denial") fixture.quotaCount = 5;
      if (mode === "read-error") {
        fixture.quotaError = { message: "synthetic quota error" };
      }
      if (mode === "atomic-denial") fixture.atomic = false;
      if (mode === "atomic-error") {
        fixture.atomicError = { message: "synthetic quota error" };
      }
      if (mode === "malformed-atomic") fixture.atomic = {};
      if (mode === "budget-exhausted") fixture.budget = "exhausted";
      if (mode === "budget-error") fixture.budget = "error";
      const response = await handler(request());
      assert(response.status === 429 || response.status === 503);
      await response.body?.cancel();
      equal(state.providerCalls.length, 0);
      equal(fixture.uploads.length, 0);
      if (mode.startsWith("budget")) {
        assert(
          !fixture.calls.some((call) => call.name === "reserve_ai_image_quota"),
        );
      }
    }));
}

function abortedFetch(init: RequestInit): Promise<Response> {
  return new Promise((_resolve, reject) => {
    init.signal!.addEventListener("abort", () => reject(init.signal!.reason), {
      once: true,
    });
  });
}
function hangingProvider(cancelled: { resolve: (value: void) => void }) {
  return new Response(
    new ReadableStream<Uint8Array>({
      cancel() {
        cancelled.resolve();
      },
    }),
  );
}

Deno.test("caller cancellation aborts the sole pending provider fetch", () =>
  scenario(async (state) => {
    const started = deferred<void>();
    state.provider = (init) => {
      started.resolve();
      return abortedFetch(init);
    };
    const controller = new AbortController();
    const pending = handler(request(false, undefined, controller.signal));
    await started.promise;
    controller.abort();
    const response = await pending;
    equal(response.status, 499);
    equal((await response.json()).code, "generation_cancelled");
    equal(state.providerCalls.length, 1);
    equal(fixture.uploads.length, 0);
  }));

Deno.test("SSE consumer cancellation cancels the provider reader without upload or writer leaks", () =>
  scenario(async (state) => {
    const cancelled = deferred<void>();
    state.provider = () => hangingProvider(cancelled);
    const response = await handler(request(true));
    await response.body!.cancel();
    await cancelled.promise;
    await Promise.resolve();
    equal(state.providerCalls[0].signal!.aborted, true);
    equal(fixture.uploads.length, 0);
  }));

for (const stream of [false, true]) {
  Deno.test(`${stream ? "SSE" : "JSON"} 120-second deadline cancels a stalled response body`, () =>
    scenario(async (state) => {
      const originalTimeout = globalThis.setTimeout;
      globalThis.setTimeout = ((callback: () => void, delay?: number) => {
        equal(delay, 120_000);
        return originalTimeout(callback, 1);
      }) as typeof setTimeout;
      const cancelled = deferred<void>();
      state.provider = () => hangingProvider(cancelled);
      const response = await handler(request(stream));
      equal((await result(stream, response)).code, "generation_timeout");
      await cancelled.promise;
      equal(state.providerCalls[0].signal!.aborted, true);
      equal(fixture.uploads.length, 0);
    }));
}

Deno.test("Storage cancellation uses the caller request signal and emits no completion", () =>
  scenario(async (state) => {
    const started = deferred<void>();
    state.provider = () => streamBytes(encoder.encode(sse(completed())));
    state.storage = (init) => {
      started.resolve();
      return abortedFetch(init);
    };
    const controller = new AbortController();
    const response = await handler(
      request(
        true,
        { prompt: "quiet moon avatar", stream: true },
        controller.signal,
      ),
    );
    await started.promise;
    controller.abort();
    equal((await result(true, response)).code, "generation_cancelled");
    equal(state.storageCalls[0].signal!.aborted, true);
  }));

for (const stream of [false, true]) {
  Deno.test(`${stream ? "SSE" : "JSON"} provider cumulative 8-MiB limit is enforced`, () =>
    scenario(async (state) => {
      const cancelled = deferred<void>();
      state.provider = () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              const chunk = encoder.encode(
                stream ? `: ${"x".repeat(1020)}\n\n` : " ".repeat(1024),
              );
              for (let i = 0; i < 8200; i++) controller.enqueue(chunk);
            },
            cancel() {
              cancelled.resolve();
            },
          }),
        );
      equal(
        (await result(stream, await handler(request(stream)))).code,
        "provider_response_too_large",
      );
      await cancelled.promise;
      equal(fixture.uploads.length, 0);
      equal(state.providerCalls.length, 1);
    }));
}

Deno.test("JPEG validation accepts exactly 512 KiB with well-formed comment segments", () => {
  const padded = new Uint8Array(MAX_IMAGE_BYTES);
  padded.set(jpeg.subarray(0, 2));
  let offset = 2;
  let remaining = MAX_IMAGE_BYTES - jpeg.length;
  while (remaining) {
    let size = Math.min(65537, remaining);
    if (remaining - size > 0 && remaining - size < 4) size -= 4;
    padded.set([255, 254, (size - 2) >> 8, (size - 2) & 255], offset);
    offset += size;
    remaining -= size;
  }
  padded.set(jpeg.subarray(2), offset);
  equal(decodeJPEG(base64(padded)).length, MAX_IMAGE_BYTES);
});

Deno.test("a preview above the upload cap cannot reject a valid final JPEG", () =>
  scenario(async (state) => {
    // Original JPEG with valid comment segments; previews are not uploaded.
    const preview = new Uint8Array(jpeg.length + 9 * 60004);
    preview.set(jpeg.subarray(0, -2));
    let offset = jpeg.length - 2;
    for (let i = 0; i < 9; i++) {
      preview.set([0xff, 0xfe, 0xea, 0x62], offset);
      offset += 60004;
    }
    preview.set([0xff, 0xd9], offset);
    state.provider = () =>
      streamBytes(encoder.encode(
        sse({
          type: "image_generation.partial_image",
          partial_image_index: 0,
          b64_json: base64(preview),
        }) + sse(completed()),
      ));
    const messages = await events(await handler(request(true)));
    equal(messages[0].type, "partial");
    equal(messages[1].type, "complete");
    validateSuccess(messages[1]);
    equal(state.providerCalls.length, 1);
  }));

Deno.test("a completed provider frame does not wait for its connection to close", () =>
  scenario(async (state) => {
    let cancelled = false;
    state.provider = () =>
      new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(encoder.encode(sse(completed())));
          },
          cancel() {
            cancelled = true;
          },
        }),
      );
    const abort = new AbortController();
    const deadline = setTimeout(() => abort.abort(), 500);
    try {
      const messages = await events(
        await handler(
          request(
            true,
            { prompt: "quiet moon avatar", stream: true },
            abort.signal,
          ),
        ),
      );
      equal(messages[0].type, "complete");
      equal(cancelled, true);
      equal(state.providerCalls.length, 1);
      validateSuccess(messages[0]);
    } finally {
      clearTimeout(deadline);
    }
  }));

Deno.test("the server accepts the same 200 emoji characters as the Swift prompt counter", () =>
  scenario(async (state) => {
    const response = await handler(
      request(false, { prompt: "🌙".repeat(200) }),
    );
    equal(response.status, 200);
    validateSuccess(await response.json());
    equal(state.providerCalls.length, 1);
  }));
Deno.test("201 grapheme characters are rejected before budget or provider", () =>
  scenario(async (state) => {
    const response = await handler(
      request(false, { prompt: "🌙".repeat(201) }),
    );
    equal(response.status, 400);
    equal(state.providerCalls.length, 0);
    equal(fixture.calls.length, 1);
  }));
