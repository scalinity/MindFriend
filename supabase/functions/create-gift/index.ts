import { getCorsHeaders } from "../_shared/cors.ts";

// Gift purchases and new redemptions stay unavailable until a verified StoreKit
// gift flow exists. Existing records and already redeemed access are untouched.
Deno.serve((req) => {
  const headers = { ...getCorsHeaders(req.headers.get("origin") ?? ""), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers });
  }
  return new Response(JSON.stringify({
    success: false,
    code: "GIFTING_UNAVAILABLE",
    error: "Gifting and gift redemption are temporarily unavailable. Please try again later.",
  }), { status: 503, headers });
});
