// Provider transport only. Authentication, ownership and quotas stay in the caller.
export const CHAT_MODEL = "gpt-6-luna";
export const MAX_PROMPT_BYTES = 128_000;

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

// Keep the system prompt and current message intact, dropping oldest history first.
export function trimChatContext(messages: ChatMessage[]): ChatMessage[] {
  const bounded = messages.slice();
  const encoder = new TextEncoder();
  while (encoder.encode(JSON.stringify(bounded)).length > MAX_PROMPT_BYTES) {
    if (bounded.length <= 2) throw new Error("CHAT_CONTEXT_TOO_LARGE");
    bounded.splice(1, 1);
  }
  return bounded;
}

export async function generateChatText(
  messages: ChatMessage[],
  options: {
    apiKey: string;
    reserveBudget: (microdollars: number) => Promise<boolean>;
    beforeProvider?: () => Promise<void>;
    maxOutputTokens?: number;
    onDelta?: (text: string) => void;
    signal?: AbortSignal;
    fetcher?: typeof fetch;
  },
): Promise<string> {
  options.signal?.throwIfAborted();
  const inputBytes = new TextEncoder().encode(JSON.stringify(messages)).length;
  if (inputBytes > MAX_PROMPT_BYTES) {
    throw new Error("CHAT_CONTEXT_TOO_LARGE");
  }
  const maxOutputTokens = options.maxOutputTokens ?? 500;
  if (!Number.isInteger(maxOutputTokens) || maxOutputTokens < 1 || maxOutputTokens > 500) {
    throw new Error("INVALID_OUTPUT_LIMIT");
  }
  // Standard GPT-6 Luna: reserve the worst 30-minute cache-write input rate
  // ($0.125/M) and $0.50/M output; ordinary/cached input costs less.
  // At most one token per input byte, plus framing allowance; no paid tools/Fast tier.
  const maxCostMicrodollars = Math.ceil((inputBytes + 1024) * 0.125 + maxOutputTokens * 0.5);
  if (!await options.reserveBudget(maxCostMicrodollars)) throw new Error("AI_DAILY_BUDGET_REACHED");
  options.signal?.throwIfAborted();
  // The caller debits user quota only after validated input and approved spending.
  await options.beforeProvider?.();
  options.signal?.throwIfAborted();
  const signal = options.signal
    ? AbortSignal.any([options.signal, AbortSignal.timeout(45_000)])
    : AbortSignal.timeout(45_000);
  // No SDK retries or provider fallback: an uncertain request must not be replayed.
  const response = await (options.fetcher ?? fetch)("https://api.openai.com/v1/responses", {
    method: "POST",
    signal,
    headers: {
      Authorization: `Bearer ${options.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: CHAT_MODEL,
      service_tier: "default",
      prompt_cache_options: { ttl: "30m" },
      input: messages,
      reasoning: { effort: "none" },
      max_output_tokens: maxOutputTokens,
      store: false,
      stream: !!options.onDelta,
    }),
  });
  if (!response.ok) throw new Error(`AI_HTTP_${response.status}`);
  if (!options.onDelta) {
    const data = await response.json();
    if (data.status === "failed" || data.status === "incomplete") throw new Error("AI_TERMINAL_FAILED");
    if (data.status !== "completed") throw new Error("AI_INCOMPLETE_RESPONSE");
    const text = (data.output ?? []).flatMap((item: { content?: { type: string; text?: string }[] }) =>
      item.content ?? []
    ).filter((item: { type: string }) => item.type === "output_text")
      .map((item: { text: string }) => item.text).join("");
    if (!text.trim()) throw new Error("AI_EMPTY_RESPONSE");
    return text;
  }
  if (!response.body) throw new Error("AI_EMPTY_STREAM");
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let pending = "";
  let text = "";
  let completed = false;
  try {
    while (true) {
      const { value, done } = await reader.read();
      pending += decoder.decode(value, { stream: !done });
      const lines = pending.split("\n");
      pending = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.startsWith("data:")) continue;
        const raw = line.slice(5).trim();
        if (!raw || raw === "[DONE]") continue;
        const event = JSON.parse(raw);
        if (event.type === "response.output_text.delta") {
          text += event.delta;
          options.onDelta(event.delta);
        } else if (event.type === "response.completed") {
          completed = true;
        } else if (["error", "response.failed", "response.incomplete"].includes(event.type)) {
          throw new Error("AI_STREAM_FAILED");
        }
      }
      if (done) break;
    }
    if (!completed) throw new Error("AI_INCOMPLETE_STREAM");
    if (!text.trim()) throw new Error("AI_EMPTY_RESPONSE");
    return text;
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
