import { authenticateRequest, isAuthError } from "./auth.ts";
import type { AuthError, AuthResult } from "./auth.ts";

/** Staff roles come only from the server-managed metadata returned by Auth. */
export async function authenticateStaffRequest(
  req: Request,
  allowedRoles: readonly string[],
): Promise<AuthResult | AuthError> {
  const auth = await authenticateRequest(req);
  if (isAuthError(auth)) return auth;

  const role: unknown = auth.user.app_metadata?.role;
  if (typeof role !== "string" || !allowedRoles.includes(role)) {
    return {
      response: new Response(JSON.stringify({ error: "Staff access required" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      }),
    };
  }
  return auth;
}
