// Replays the eval cases on one provider route and writes one JSON line per case.
// Spends real provider credit, so it is run by hand, never by `deno test`:
//   deno run -A --env-file=supabase/functions/.env --config supabase/functions/deno.json \
//     supabase/tests/ai_eval/run.ts <target> <out.jsonl> [quality|safety|all] [case-id-prefix]
// <target>: "xai" or "standard" (budgetedXAIText with AI_PROVIDER unset or set,
// i.e. exactly the production routing, safety note, caps and reservations),
// "openai-realtime:<model>" or "xai-realtime:<model>" (voice.realtime cases
// only, as text turns; the OpenAI one mirrors the relay's safety note).
import { CASES, type EvalCase } from "./cases.ts";
import { budgetedXAIText } from "../../functions/_shared/budgeted-xai-text.ts";
import { openAINonImageKey } from "../../functions/_shared/openai-keys.ts";
import { SAFETY_NOTE } from "../../functions/_shared/ai-provider.ts";

const [target, outPath, kind = "all", prefix = ""] = Deno.args;
if (!target || !outPath) throw new Error("usage: run.ts <target> <out.jsonl> [kind] [prefix]");
const USER = "00000000-0000-4000-8000-000000000001";

// Accepts every reservation and records its amount; no database is touched.
const reservations: number[] = [];
const admin = {
  rpc(_name: string, args: Record<string, unknown>) {
    reservations.push(Number(args.p_reserve_microdollars));
    const result = {
      data: {
        allowed: true, reason: "reserved", request_id: args.p_request_id, user_id: args.p_user_id,
        feature: args.p_feature, reserve_microdollars: args.p_reserve_microdollars,
        month_start: "2026-11-01", reserved_microdollars: args.p_reserve_microdollars,
        limit_microdollars: 10_000_000,
        remaining_microdollars: 10_000_000 - Number(args.p_reserve_microdollars),
      },
      error: null,
    };
    const promise = Promise.resolve(result);
    return Object.assign(promise, { abortSignal: () => promise });
  },
};

async function realtimeText(vendor: "openai" | "xai", model: string, c: EvalCase) {
  const instructions = c.messages.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
  const user = c.messages.filter((m) => m.role === "user").map((m) => m.content).join("\n\n");
  let url: string, protocols: string[];
  if (vendor === "openai") {
    const res = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: { Authorization: `Bearer ${openAINonImageKey()}`, "Content-Type": "application/json" },
      body: JSON.stringify({ expires_after: { anchor: "created_at", seconds: 120 }, session: { type: "realtime", model } }),
    });
    const body = await res.json();
    if (!res.ok) return { status: res.status, content: "" };
    url = `wss://api.openai.com/v1/realtime?model=${model}`;
    protocols = ["realtime", "openai-insecure-api-key." + body.value];
  } else {
    const res = await fetch("https://api.x.ai/v1/realtime/client_secrets", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`, "Content-Type": "application/json" },
      body: JSON.stringify({ expires_after: { seconds: 120 } }),
    });
    const body = await res.json();
    if (!res.ok) return { status: res.status, content: "" };
    url = `wss://api.x.ai/v1/realtime?model=${model}`;
    protocols = ["xai-client-secret." + (body.value ?? body.client_secret?.value)];
  }
  const ws = new WebSocket(url, protocols);
  let text = "";
  const done = new Promise<number>((resolve) => {
    const timer = setTimeout(() => resolve(408), 45_000);
    ws.onmessage = (event) => {
      const e = JSON.parse(String(event.data));
      if (e.type === "session.updated") {
        ws.send(JSON.stringify({
          type: "conversation.item.create",
          item: { type: "message", role: "user", content: [{ type: "input_text", text: user }] },
        }));
        ws.send(JSON.stringify({ type: "response.create" }));
      }
      // xAI answers text turns as speech; its transcript is the reply text.
      if (/^response\.(output_)?(text|audio_transcript)\.delta$/.test(e.type)) text += e.delta;
      if (e.type === "response.done") { clearTimeout(timer); resolve(200); }
      if (e.type === "error") { clearTimeout(timer); resolve(500); }
    };
    ws.onerror = () => { clearTimeout(timer); resolve(502); };
  });
  ws.onopen = () => ws.send(JSON.stringify(vendor === "openai"
    // Mirrors the relay, which appends the safety note for OpenAI sessions.
    ? { type: "session.update", session: { type: "realtime", instructions: `${instructions}\n\n${SAFETY_NOTE}`, output_modalities: ["text"], max_output_tokens: c.maxTokens } }
    : { type: "session.update", session: { instructions, voice: "ara", modalities: ["text", "audio"] } }));
  const status = await done;
  ws.close();
  return { status, content: text };
}

async function runCase(c: EvalCase) {
  const [vendor, model] = target.includes(":") ? target.split(/:(.*)/s) : [target, "grok-4.3"];
  const started = performance.now();
  reservations.length = 0;
  let status = 0, content = "", finishReason = "", inputTokens = 0, outputTokens = 0;
  if (vendor === "openai-realtime" || vendor === "xai-realtime") {
    const r = await realtimeText(vendor === "openai-realtime" ? "openai" : "xai", model, c);
    status = r.status; content = r.content;
  } else {
    if (vendor === "standard") Deno.env.set("AI_PROVIDER", "standard");
    else Deno.env.delete("AI_PROVIDER");
    const response = await budgetedXAIText({
      admin, userId: USER, feature: c.feature, apiKey: Deno.env.get("XAI_API_KEY") ?? "",
      messages: c.messages, maxTokens: c.maxTokens, temperature: c.temperature,
      responseFormat: c.responseFormat, signal: AbortSignal.timeout(60_000),
    });
    status = response.status;
    if (response.ok) {
      const data = await response.json();
      content = data.choices?.[0]?.message?.content ?? "";
      finishReason = data.choices?.[0]?.finish_reason ?? "";
      inputTokens = data.usage?.prompt_tokens ?? 0;
      outputTokens = data.usage?.completion_tokens ?? 0;
    }
  }
  let jsonValid: boolean | null = null;
  if (c.expectJson) {
    try {
      JSON.parse(content.replace(/^```(?:json)?\s*|\s*```$/g, ""));
      jsonValid = true;
    } catch {
      jsonValid = false;
    }
  }
  return {
    id: c.id, feature: c.feature, kind: c.kind, target, status, finishReason,
    latencyMs: Math.round(performance.now() - started), inputTokens, outputTokens,
    reservedMicrodollars: reservations[0] ?? null, jsonValid, content,
  };
}

const selected = CASES.filter((c) =>
  (kind === "all" || c.kind === kind) && c.id.startsWith(prefix) &&
  (target.includes("realtime") ? c.feature === "voice.realtime" : c.feature !== "voice.realtime")
);
const lines: string[] = [];
// Small concurrency keeps the run short without tripping provider rate limits.
for (let i = 0; i < selected.length; i += 4) {
  const batch = await Promise.all(selected.slice(i, i + 4).map((c) =>
    runCase(c).catch((error) => ({ id: c.id, feature: c.feature, kind: c.kind, target, status: -1, error: String(error?.message ?? error).slice(0, 200) }))
  ));
  for (const row of batch) lines.push(JSON.stringify(row));
}
await Deno.writeTextFile(outPath, lines.join("\n") + "\n");
const failed = lines.filter((l) => !JSON.parse(l).status || JSON.parse(l).status !== 200).length;
console.log(`${target}: ${selected.length} cases, ${failed} non-200 -> ${outPath}`);
