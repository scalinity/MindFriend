// Edge Function: support-memory-suggestions
// The explicit "Suggest memories from this session" flow (docs/SUPPORT_SESSION_SPEC.md section 8.4).
// All logic lives in _shared/support-memory-suggestions.ts and the database RPCs; this file only
// wires real auth, CORS, rate limiting, the non-image OpenAI key, the chat.memory budget and the
// account reads. No model call happens on prepare/status; generate is always an explicit request.

import { authenticateRequest, isAuthError } from "../_shared/auth.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { openAIBudgetReservation } from "../_shared/openai-budget.ts";
import { openAINonImageKey } from "../_shared/openai-keys.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { createMemorySuggestionHandler } from "../_shared/support-memory-suggestions.ts";

const handler = createMemorySuggestionHandler({
  cors: getCorsHeaders,
  apiKey: openAINonImageKey,
  async authenticate(req) {
    const auth = await authenticateRequest(req);
    if (isAuthError(auth)) return auth.response;
    const userId = auth.user.id;
    return {
      userId,
      // Runs as the caller: auth.uid() inside the RPC is the verified user.
      userRpc: (fn, args) => auth.supabaseUser.rpc(fn, args),
      // Service role; the handler only ever passes the verified user id as the owner argument.
      adminRpc: (fn, args) => auth.supabaseAdmin.rpc(fn, args),
      async readAccount() {
        const [settings, profile] = await Promise.all([
          auth.supabaseAdmin.from("user_settings").select("privacy_mode").eq("user_id", userId).maybeSingle(),
          auth.supabaseAdmin.from("profiles").select("subscription_tier").eq("id", userId).maybeSingle(),
        ]);
        // Missing/unreadable settings or profile must not opt anyone into saved personal context.
        if (settings.error || !settings.data || profile.error || !profile.data) return null;
        return {
          privacyMode: typeof settings.data.privacy_mode === "string" ? settings.data.privacy_mode : null,
          subscriptionTier: typeof profile.data.subscription_tier === "string" ? profile.data.subscription_tier : null,
        };
      },
      // Same helper and feature label as the baseline chat memory extraction.
      reserveBudget: (signal) => openAIBudgetReservation(auth.supabaseAdmin, userId, "chat.memory", signal),
    };
  },
  rateLimit(userId, bucket) {
    const limit = bucket === "generate" ? 6 : 60;
    const r = checkRateLimit(`support-memory-suggestions:${bucket}:${userId}`, limit, 60_000);
    return { allowed: r.allowed, resetInSeconds: Math.ceil(r.resetIn / 1000) };
  },
});

Deno.serve(handler);
