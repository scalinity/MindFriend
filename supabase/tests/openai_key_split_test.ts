// Pins which key each OpenAI call path reads (docs/decisions.md, AI provider migration):
// image generation reads OPENAI_API_KEY; every other OpenAI call reads
// VOICE_AND_NONIMAGE_OPENAI_API_KEY through _shared/openai-keys.ts.
import { callStandardText, type TextRoute } from "../functions/_shared/ai-provider.ts";

const functionsDir = new URL("../functions/", import.meta.url);
const IMAGE_KEY_READERS = new Set([
  "generate-art/index.ts",
  "generate-profile-picture/index.ts",
  "_shared/openai-keys.ts",
]);
const NONIMAGE_OPENAI_CALLERS = [
  "_shared/ai-provider.ts", // text under AI_PROVIDER=standard
  "chat/index.ts", // chat replies, titles and memory extraction
  "voice-token/index.ts", // realtime voice relay (also served as test-auth-diagnostic)
  "analyze-voice-journal/index.ts", // speech-to-text
];

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

async function sources(dir: URL, prefix = ""): Promise<Array<[string, string]>> {
  const found: Array<[string, string]> = [];
  for await (const entry of Deno.readDir(dir)) {
    const path = prefix + entry.name;
    if (entry.isDirectory) {
      if (entry.name === "tests" || entry.name === "__tests__" || entry.name === "node_modules") continue;
      found.push(...await sources(new URL(entry.name + "/", dir), path + "/"));
    } else if (entry.name.endsWith(".ts") && !/(^|[._-])test[s]?\.ts$|test-[a-z]+\.ts$/.test(entry.name)) {
      found.push([path, await Deno.readTextFile(new URL(entry.name, dir))]);
    }
  }
  return found;
}

Deno.test("only image generation reads OPENAI_API_KEY", async () => {
  const readers = (await sources(functionsDir))
    .filter(([, text]) => /["'`]OPENAI_API_KEY["'`]/.test(text))
    .map(([path]) => path);
  for (const path of readers) {
    assert(IMAGE_KEY_READERS.has(path), `${path} reads the image key OPENAI_API_KEY`);
  }
  for (const path of ["generate-art/index.ts", "generate-profile-picture/index.ts"]) {
    assert(readers.includes(path), `${path} no longer reads OPENAI_API_KEY`);
  }
});

Deno.test("every non-image OpenAI caller reads the non-image key", async () => {
  const all = new Map(await sources(functionsDir));
  for (const path of NONIMAGE_OPENAI_CALLERS) {
    const text = all.get(path);
    assert(text, `${path} is missing`);
    assert(/openAINonImageKey\(\)/.test(text), `${path} does not read the non-image key`);
  }
  // Any other file calling OpenAI outside image generation must be added above.
  for (const [path, text] of all) {
    if (!text.includes("api.openai.com") || IMAGE_KEY_READERS.has(path)) continue;
    assert(
      NONIMAGE_OPENAI_CALLERS.includes(path) || path.startsWith("_shared/openai-") ||
        path === "_shared/voice-relay.ts",
      `${path} calls OpenAI without a pinned key`,
    );
  }
});

Deno.test("standard text sends the non-image key to OpenAI, never the image key", async () => {
  const previous = {
    image: Deno.env.get("OPENAI_API_KEY"),
    nonImage: Deno.env.get("VOICE_AND_NONIMAGE_OPENAI_API_KEY"),
  };
  Deno.env.set("OPENAI_API_KEY", "synthetic-image-key");
  Deno.env.set("VOICE_AND_NONIMAGE_OPENAI_API_KEY", "synthetic-nonimage-key");
  try {
    let authorization = "";
    const route: TextRoute = { vendor: "openai", model: "gpt-6-luna", inputUsdPerM: 0.1, outputUsdPerM: 0.5 };
    const result = await callStandardText({
      route,
      feature: "synthetic.feature",
      messages: [{ role: "user", content: "Say hello" }],
      maxTokens: 16,
      json: false,
      signal: AbortSignal.timeout(5000),
      fetcher: (_input, init) => {
        authorization = new Headers(init?.headers).get("Authorization") ?? "";
        return Promise.resolve(Response.json({
          status: "completed",
          output: [{ content: [{ type: "output_text", text: "hello" }] }],
          usage: { input_tokens: 3, output_tokens: 1 },
        }));
      },
    });
    assert(authorization === "Bearer synthetic-nonimage-key", "Wrong OpenAI key sent");
    assert(result.content === "hello", "Unexpected content");
  } finally {
    for (const [name, value] of [["OPENAI_API_KEY", previous.image], ["VOICE_AND_NONIMAGE_OPENAI_API_KEY", previous.nonImage]] as const) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});
