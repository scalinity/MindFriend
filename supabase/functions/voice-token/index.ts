import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  handleVoiceRelay,
  OPENAI_REALTIME_MODEL,
  OPENAI_REALTIME_URL,
  PROVIDER_URL,
} from "../_shared/voice-relay.ts";
import { selectedAIProvider } from "../_shared/ai-provider.ts";
import { openAINonImageKey } from "../_shared/openai-keys.ts";

// Phase 2 release gate: deploy only after relay-capable clients are available.
// Keep this function name: no extra deployed function is required.
Deno.serve((req) => {
  const headers = {
    ...getCorsHeaders(req.headers.get("Origin")),
    "Content-Type": "application/json",
  };
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ code: "CONFIG_ERROR" }), {
      status: 500,
      headers,
    });
  }
  // Missing local configuration cannot consume a claimed owner's allowance.
  // Capture once: issuance uses the same checked value after atomic admission.
  const vendor = selectedAIProvider() === "standard" ? "openai" : "xai";
  const providerKey = vendor === "openai"
    ? openAINonImageKey()
    : Deno.env.get("XAI_API_KEY")?.trim();
  if (req.method === "GET" && !providerKey) {
    return new Response(JSON.stringify({ code: "CONFIG_ERROR" }), {
      status: 503,
      headers,
    });
  }
  const client = (signal: AbortSignal) =>
    createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: (input, init) => fetch(input, { ...init, signal }) },
    });
  const runtime = (globalThis as typeof globalThis & {
    EdgeRuntime?: { waitUntil(work: Promise<unknown>): void };
  }).EdgeRuntime;
  return handleVoiceRelay(req, {
    vendor,
    waitUntil: runtime ? (work) => runtime.waitUntil(work) : undefined,
    anonKey,
    authenticate: async (jwt, signal) => {
      const { data, error } = await client(signal).auth.getUser(jwt);
      return error || data.user?.is_anonymous ? null : data.user?.id ?? null;
    },
    rpc: async (name, args, signal) => {
      const { data, error } = await client(signal).rpc(name, args);
      if (error) {
        const safeCodes = [
          "QUOTA_EXCEEDED",
          "VOICE_BUDGET_EXCEEDED",
          "MONTHLY_AI_BUDGET_EXCEEDED",
          "RATE_LIMITED",
          "INVALID_SESSION",
          "RELAY_ALREADY_ACTIVE",
        ];
        throw Error(
          safeCodes.includes(error.message)
            ? error.message
            : "VOICE_DATABASE_ERROR",
        );
      }
      return data;
    },
    issueSecret: async (signal) => {
      if (!providerKey) throw Error("CONFIG_ERROR");
      const result = await fetch(
        vendor === "openai"
          ? "https://api.openai.com/v1/realtime/client_secrets"
          : "https://api.x.ai/v1/realtime/client_secrets",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${providerKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(
            vendor === "openai"
              ? {
                expires_after: { anchor: "created_at", seconds: 300 },
                session: { type: "realtime", model: OPENAI_REALTIME_MODEL },
              }
              : { expires_after: { seconds: 300 } },
          ),
          signal,
        },
      );
      if (!result.ok) {
        await result.body?.cancel();
        throw Error("PROVIDER_ERROR");
      }
      // Bound the provider response without logging its contents.
      const reader = result.body?.getReader();
      if (!reader) throw Error("PROVIDER_ERROR");
      let size = 0, body = "";
      const decoder = new TextDecoder();
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > 16384) throw Error("PROVIDER_ERROR");
          body += decoder.decode(value, { stream: true });
        }
      } finally {
        await reader.cancel();
        reader.releaseLock();
      }
      const data = JSON.parse(body);
      const secret = data.value ?? data.client_secret?.value;
      if (typeof secret !== "string") throw Error("PROVIDER_ERROR");
      return secret;
    },
    connect: (secret) =>
      vendor === "openai"
        ? new WebSocket(OPENAI_REALTIME_URL, [
          "realtime",
          "openai-insecure-api-key." + secret,
        ])
        : new WebSocket(PROVIDER_URL, ["xai-client-secret." + secret]),
    upgrade: (request) => Deno.upgradeWebSocket(request),
  }, headers);
});
