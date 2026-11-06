import {
  type MonthlyAIBudgetAdmin,
  reserveMonthlyAIBudget,
} from "./monthly-ai-budget.ts";

export const XAI_TEXT_MODEL = "grok-4.3";
const MAX_PROMPT_BYTES = 128_000;
const MAX_RESPONSE_BYTES = 1_048_576;

export interface XAITextBudgetContext {
  admin: MonthlyAIBudgetAdmin;
  userId: string;
  feature: string;
}

export interface XAITextMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

interface XAITextOptions extends XAITextBudgetContext {
  apiKey: string;
  messages: XAITextMessage[];
  maxTokens: number;
  temperature?: number;
  responseFormat?: { type: "json_object" };
  signal?: AbortSignal;
  beforeProvider?: (signal: AbortSignal) => Promise<void>;
  fetcher?: typeof fetch;
}

async function abortable<T>(
  operation: () => Promise<T>,
  signal: AbortSignal,
): Promise<T> {
  signal.throwIfAborted();
  return await new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, { once: true });
    Promise.resolve().then(() => {
      signal.throwIfAborted();
      return operation();
    })
      .then(resolve, reject).finally(() =>
        signal.removeEventListener("abort", abort)
      );
  });
}

/** One HTTP attempt only; callers retain any existing bounded retry policy. */
export async function budgetedXAIText(
  options: XAITextOptions,
): Promise<Response> {
  if (
    !options.apiKey || !Array.isArray(options.messages) ||
    options.messages.length < 1 || options.messages.length > 64 ||
    options.messages.some((message) =>
      !message || !["system", "user", "assistant"].includes(message.role) ||
      typeof message.content !== "string" ||
      Object.keys(message).some((key) => key !== "role" && key !== "content")
    ) ||
    !Number.isInteger(options.maxTokens) || options.maxTokens < 1 ||
    options.maxTokens > 8000 ||
    (options.temperature !== undefined &&
      (!Number.isFinite(options.temperature) || options.temperature < 0 ||
        options.temperature > 2)) ||
    (options.responseFormat !== undefined &&
      (options.responseFormat.type !== "json_object" ||
        Object.keys(options.responseFormat).length !== 1))
  ) throw new Error("XAI_TEXT_INVALID_REQUEST");

  const messages = options.messages.map(({ role, content }) => ({
    role,
    content,
  }));
  const promptBytes = new TextEncoder().encode(JSON.stringify(messages)).length;
  if (promptBytes > MAX_PROMPT_BYTES) {
    throw new Error("XAI_TEXT_CONTEXT_TOO_LARGE");
  }
  const body = JSON.stringify({
    model: XAI_TEXT_MODEL,
    reasoning_effort: "none",
    messages,
    max_tokens: options.maxTokens,
    ...(options.temperature === undefined
      ? {}
      : { temperature: options.temperature }),
    ...(options.responseFormat === undefined
      ? {}
      : { response_format: options.responseFormat }),
  });
  const signal = options.signal
    ? AbortSignal.any([options.signal, AbortSignal.timeout(45_000)])
    : AbortSignal.timeout(45_000);
  signal.throwIfAborted();
  // Short-context grok-4.3: $1.25/M input, $2.50/M output. The byte-per-token
  // allowance plus 1,024 framing tokens is a conservative assumption, not a
  // tokenizer-documented mathematical bound. Cache discounts are not assumed.
  await abortable(() =>
    reserveMonthlyAIBudget(options.admin, {
      requestId: crypto.randomUUID(),
      userId: options.userId,
      feature: options.feature,
      reserveMicrodollars: Math.ceil(
        (promptBytes + 1024) * 1.25 + options.maxTokens * 2.5,
      ),
    }, signal), signal);
  signal.throwIfAborted();
  if (options.beforeProvider) {
    await abortable(() => options.beforeProvider!(signal), signal);
    signal.throwIfAborted();
  }
  const response = await abortable(
    () =>
      (options.fetcher ?? fetch)("https://api.x.ai/v1/chat/completions", {
        method: "POST",
        redirect: "error",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${options.apiKey}`,
        },
        body,
        signal,
      }).then((response) => {
        if (signal.aborted) {
          void response.body?.cancel().catch(() => {});
          signal.throwIfAborted();
        }
        return response;
      }),
    signal,
  );
  if (!response.ok) {
    // Provider diagnostics can contain private data. Preserve status handling,
    // without returning or logging their body. An uncertain cost is never refunded.
    void response.body?.cancel().catch(() => {});
    return new Response(null, { status: response.status });
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error("XAI_TEXT_EMPTY_RESPONSE");
  const chunks: Uint8Array[] = [];
  let size = 0;
  let completed = false;
  try {
    while (true) {
      const { value, done } = await abortable(() => reader.read(), signal);
      if (done) {
        completed = true;
        break;
      }
      size += value.length;
      if (size > MAX_RESPONSE_BYTES) {
        throw new Error("XAI_TEXT_RESPONSE_TOO_LARGE");
      }
      chunks.push(value);
    }
  } finally {
    if (!completed) void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
  signal.throwIfAborted();
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new Response(bytes, {
    status: response.status,
    headers: { "Content-Type": "application/json" },
  });
}
