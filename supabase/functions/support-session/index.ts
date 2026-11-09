// Edge Function: support-session
// One authenticated facade for the resumable support-session contract
// (docs/SUPPORT_SESSION_SPEC.md section 9.4). All logic lives in the database RPCs and
// _shared/support-*.ts; this file only wires real auth, CORS and rate limiting.

import { authenticateRequest, isAuthError } from "../_shared/auth.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { createSupportSessionHandler } from "../_shared/support-session-handler.ts";

const handler = createSupportSessionHandler({
  cors: getCorsHeaders,
  async authenticate(req) {
    const auth = await authenticateRequest(req);
    if (isAuthError(auth)) return auth.response;
    // The user-scoped client carries the caller's JWT, so auth.uid() in the RPCs is the
    // verified user. The admin client is intentionally not exposed to the handler.
    return {
      userId: auth.user.id,
      rpc: (fn, args) => auth.supabaseUser.rpc(fn, args),
    };
  },
  rateLimit(userId, bucket) {
    const limit = bucket === "write" ? 120 : 300;
    const r = checkRateLimit(
      `support-session:${bucket}:${userId}`,
      limit,
      60_000,
    );
    return { allowed: r.allowed, resetInSeconds: Math.ceil(r.resetIn / 1000) };
  },
});

Deno.serve(handler);
