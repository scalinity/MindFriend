// One server-side switch selects the AI vendor. AI_PROVIDER=standard sends text,
// realtime voice and transcription to OpenAI; any other value, including unset,
// keeps the xAI behavior. There is no per-request cross-vendor fallback: a failed
// call fails like it did on xAI. docs/decisions.md records the model evaluation.
import { CRISIS_RESPONSE } from "./crisis.ts";
import { openAINonImageKey } from "./openai-keys.ts";

export type AIProvider = "xai" | "standard";

// Speech-to-text under AI_PROVIDER=standard: voice-journal REST transcription
// and the realtime session's input transcription.
export const OPENAI_TRANSCRIPTION_MODEL = "gpt-transcribe";

export function selectedAIProvider(): AIProvider {
  return Deno.env.get("AI_PROVIDER")?.trim().toLowerCase() === "standard"
    ? "standard"
    : "xai";
}

export interface TextRoute {
  vendor: "xai" | "openai";
  model: string;
  // USD per million tokens, used for the monthly budget reservation.
  inputUsdPerM: number;
  outputUsdPerM: number;
  // Output cap replacing the caller's, where the routed model's JSON needs more room.
  maxTokens?: number;
}

export const XAI_TEXT_ROUTE: TextRoute = {
  vendor: "xai",
  model: "grok-4.3",
  inputUsdPerM: 1.25,
  outputUsdPerM: 2.5,
};

// gpt-6-luna: $0.10/M input, $0.50/M output (OpenAI pricing page, 2026-11-06).
// Reasoning is off ("none"), so no reasoning tokens bill as output.
const LUNA: TextRoute = {
  vendor: "openai",
  model: "gpt-6-luna",
  inputUsdPerM: 0.1,
  outputUsdPerM: 0.5,
};

// Feature -> route under AI_PROVIDER=standard. Unlisted features use LUNA.
const STANDARD_TEXT_ROUTES: Record<string, TextRoute> = {
  // Luna's decision JSON runs ~400 tokens; the caller's 300 cut it off.
  "decision.analysis": { ...LUNA, maxTokens: 800 },
};

export function textRoute(feature: string): TextRoute {
  if (selectedAIProvider() !== "standard") return XAI_TEXT_ROUTE;
  return STANDARD_TEXT_ROUTES[feature] ?? LUNA;
}

// Appended to the system prompt of features that reflect on a person's own
// words, and to realtime voice instructions, under AI_PROVIDER=standard. The
// safety evaluation (supabase/tests/ai_eval) showed the new models otherwise
// answered abuse and hopelessness warmly without pointing to support.
export const SAFETY_NOTE =
  "Safety: if the person's words suggest self-harm, not wanting to live, hopelessness, or abuse or violence against them, respond with warmth; where abuse is described, say clearly that it is not their fault. Encourage reaching out for support: in the US, call or text 988 (Suicide & Crisis Lifeline); for abuse, the National Domestic Violence Hotline at 1-800-799-7233; in immediate danger, 911 or local emergency services. Never give method, means or dosing details. For medication questions, encourage talking with their prescriber or pharmacist before changing anything. If your reply must be JSON, put this support in the most person-facing text field and keep the JSON valid.";
const SAFETY_NOTE_FEATURES = new Set([
  "journal.analysis",
  "thought.analysis",
  "voice_journal.analysis",
  "decision.analysis",
  "rehearsal.opening",
  "rehearsal.reply",
]);

export function withSafetyNote(
  feature: string,
  messages: ProviderTextRequest["messages"],
): ProviderTextRequest["messages"] {
  if (!SAFETY_NOTE_FEATURES.has(feature)) return messages;
  const index = messages.findIndex((m) => m.role === "system");
  if (index < 0) return [{ role: "system", content: SAFETY_NOTE }, ...messages];
  return messages.map((m, i) =>
    i === index ? { ...m, content: `${m.content}\n\n${SAFETY_NOTE}` } : m
  );
}

// Conversational features show the reply to the person; a safety refusal
// there becomes the crisis-resource response instead of a blank reply.
// Analysis features return no content on refusal and keep their own fallback.
const CONVERSATIONAL_FEATURES = new Set(["rehearsal.opening", "rehearsal.reply"]);

export interface ProviderTextRequest {
  route: TextRoute;
  feature: string;
  messages: Array<{ role: "system" | "user" | "assistant"; content: string }>;
  maxTokens: number;
  json: boolean;
  signal: AbortSignal;
  fetcher?: typeof fetch;
}

export interface ProviderTextResult {
  status: number;
  content?: string;
  finishReason?: string;
  inputTokens?: number;
  outputTokens?: number;
}

// Same ceiling as the xAI path in budgeted-xai-text.ts.
const MAX_RESPONSE_BYTES = 1_048_576;

// Reads a provider body within the ceiling. An abort or oversized body cancels
// the stream and releases its lock; the caller keeps the budget reservation.
async function readBounded(
  response: Response,
  signal: AbortSignal,
): Promise<string> {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("AI_TEXT_EMPTY_RESPONSE");
  const cancel = () => void reader.cancel().catch(() => {});
  signal.addEventListener("abort", cancel, { once: true });
  const chunks: Uint8Array[] = [];
  let size = 0;
  let completed = false;
  try {
    while (true) {
      signal.throwIfAborted();
      const { value, done } = await reader.read();
      if (done) {
        completed = true;
        break;
      }
      size += value.length;
      if (size > MAX_RESPONSE_BYTES) throw new Error("AI_TEXT_RESPONSE_TOO_LARGE");
      chunks.push(value);
    }
  } finally {
    signal.removeEventListener("abort", cancel);
    if (!completed) cancel();
    reader.releaseLock();
  }
  signal.throwIfAborted();
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(bytes);
}

export function vendorKey(route: TextRoute): string | undefined {
  return route.vendor === "openai" ? openAINonImageKey() : undefined;
}

export async function callStandardText(
  input: ProviderTextRequest,
): Promise<ProviderTextResult> {
  const apiKey = vendorKey(input.route);
  if (!apiKey) throw new Error("AI_PROVIDER_CONFIG_ERROR");
  const messages = withSafetyNote(input.feature, input.messages);
  const response = await (input.fetcher ?? fetch)(
    "https://api.openai.com/v1/responses",
    {
      method: "POST",
      redirect: "error",
      signal: input.signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: input.route.model,
        input: messages,
        reasoning: { effort: "none" },
        max_output_tokens: input.maxTokens,
        store: false,
        ...(input.json ? { text: { format: { type: "json_object" } } } : {}),
      }),
    },
  );
  if (!response.ok) {
    // Provider diagnostics can contain private data; keep only the status.
    void response.body?.cancel().catch(() => {});
    return { status: response.status };
  }
  const data = JSON.parse(await readBounded(response, input.signal));
  const usage = {
    inputTokens: data.usage?.input_tokens,
    outputTokens: data.usage?.output_tokens,
  };
  const parts = (data.output ?? []).flatMap((
    item: { content?: Array<{ type: string; text?: string }> },
  ) => item.content ?? []);
  if (parts.some((part: { type: string }) => part.type === "refusal")) {
    return {
      status: 200,
      content: CONVERSATIONAL_FEATURES.has(input.feature) ? CRISIS_RESPONSE : "",
      finishReason: "refusal",
      ...usage,
    };
  }
  const text = parts.filter((part: { type: string }) =>
    part.type === "output_text"
  ).map((part: { text?: string }) => part.text ?? "").join("");
  return {
    status: 200,
    content: text,
    finishReason: data.status === "incomplete" ? "length" : "stop",
    ...usage,
  };
}

// Callers parse the xAI chat-completions shape; standard replies keep it.
export function chatCompletionBody(
  route: TextRoute,
  result: ProviderTextResult,
): string {
  const inputTokens = result.inputTokens ?? 0;
  const outputTokens = result.outputTokens ?? 0;
  return JSON.stringify({
    id: crypto.randomUUID(),
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model: route.model,
    choices: [{
      index: 0,
      message: { role: "assistant", content: result.content ?? "" },
      finish_reason: result.finishReason ?? "stop",
    }],
    usage: {
      prompt_tokens: inputTokens,
      completion_tokens: outputTokens,
      total_tokens: inputTokens + outputTokens,
    },
  });
}
