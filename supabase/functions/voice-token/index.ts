import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  handleVoiceRelay,
  type RelayVendor,
  voiceDispatchFor,
  voiceRouteFor,
} from "../_shared/voice-relay.ts";
import { selectedAIProvider } from "../_shared/ai-provider.ts";
import { openAINonImageKey } from "../_shared/openai-keys.ts";
import { createSupabaseContextSources } from "../_shared/support-context-policy.ts";
import {
  createVoiceContextPort,
  VOICE_CONTEXT_DB_CODES,
  VOICE_CONTEXT_RPCS,
} from "../_shared/support-voice.ts";

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
  // Ambient vendor: captured once per request. It decides legacy requests and the route that
  // a NEW admission (POST) freezes; a new-contract GET uses the stored route instead.
  const vendor: RelayVendor = selectedAIProvider() === "standard"
    ? "openai"
    : "xai";
  const keyFor = (route: RelayVendor) =>
    route === "openai"
      ? openAINonImageKey()
      : Deno.env.get("XAI_API_KEY")?.trim();
  const newContractGet = req.method === "GET" &&
    new URL(req.url).searchParams.has("voice_context");
  // Legacy GET keeps its early, ambient-route check. A new-contract GET is checked by the
  // relay against the route frozen at POST, still before any claim.
  if (req.method === "GET" && !newContractGet && !keyFor(vendor)) {
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
  const rpc = async (
    name: string,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) => {
    const { data, error } = await client(signal).rpc(name, args);
    if (error) {
      // A missing new function means "not deployed": fail closed, never fall back.
      if (
        VOICE_CONTEXT_RPCS.has(name) &&
        (error.code === "PGRST202" ||
          /could not find the function/i.test(error.message ?? ""))
      ) throw Error("VOICE_CONTEXT_UNAVAILABLE");
      const safeCodes: string[] = [
        "QUOTA_EXCEEDED",
        "VOICE_BUDGET_EXCEEDED",
        "MONTHLY_AI_BUDGET_EXCEEDED",
        "RATE_LIMITED",
        "INVALID_SESSION",
        "RELAY_ALREADY_ACTIVE",
        ...VOICE_CONTEXT_DB_CODES,
      ];
      throw Error(
        safeCodes.includes(error.message)
          ? error.message
          : VOICE_CONTEXT_RPCS.has(name)
          ? "VOICE_CONTEXT_UNAVAILABLE"
          : "VOICE_DATABASE_ERROR",
      );
    }
    return data;
  };
  return handleVoiceRelay(req, {
    vendor,
    waitUntil: runtime ? (work) => runtime.waitUntil(work) : undefined,
    anonKey,
    providerConfigured: (route) => !!keyFor(route),
    voiceContext: createVoiceContextPort({
      rpc,
      // Same ContextPolicy and sources the text path uses; every read is owner-scoped.
      sources: (signal) =>
        createSupabaseContextSources(
          client(signal) as unknown as Parameters<
            typeof createSupabaseContextSources
          >[0],
        ),
    }),
    authenticate: async (jwt, signal) => {
      const { data, error } = await client(signal).auth.getUser(jwt);
      return error || data.user?.is_anonymous ? null : data.user?.id ?? null;
    },
    rpc,
    // `route` is the FULL vendor/model/route_version tuple stored at admission (new contract);
    // legacy callers pass nothing and keep today's ambient vendor and current model. A stored
    // tuple that is not exactly supported by this deployment is refused before any key is read
    // or any request is made, and is never replaced by the currently deployed model.
    issueSecret: async (signal, route) => {
      const dispatch = voiceDispatchFor(route ?? voiceRouteFor(vendor));
      if (!dispatch) throw Error("VOICE_ROUTE_UNSUPPORTED");
      const providerKey = keyFor(route?.vendor ?? vendor);
      if (!providerKey) throw Error("CONFIG_ERROR");
      const result = await fetch(
        dispatch.secretUrl,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${providerKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(dispatch.secretBody),
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
    connect: (secret, route) => {
      const dispatch = voiceDispatchFor(route ?? voiceRouteFor(vendor));
      if (!dispatch) throw Error("VOICE_ROUTE_UNSUPPORTED");
      return new WebSocket(dispatch.socketUrl, dispatch.protocols(secret));
    },
    upgrade: (request) => Deno.upgradeWebSocket(request),
  }, headers);
});
