import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import * as jose from "npm:jose@6.2.13";
import { verifyAppleNotification } from "./apple-notification.ts";

const headers = { "Content-Type": "application/json" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers });
  }
  let body: unknown;
  try { body = await req.json(); }
  catch { return new Response(JSON.stringify({ error: "Invalid request body" }), { status: 400, headers }); }
  const token = body && typeof body === "object" ? (body as { payload?: unknown }).payload : undefined;
  if (typeof token !== "string" || !token || token.length > 65536) {
    return new Response(JSON.stringify({ error: "Missing or invalid payload" }), { status: 400, headers });
  }

  let event;
  try {
    event = await verifyAppleNotification(token, Deno.env.get("APPLE_CLIENT_ID")?.trim() || "com.mindfriend.app");
  } catch (error) {
    const invalid = error instanceof jose.errors.JOSEError && !(error instanceof jose.errors.JWKSTimeout);
    return new Response(JSON.stringify({ error: invalid ? "Invalid notification" : "Verification unavailable" }), {
      status: invalid ? 401 : 503, headers,
    });
  }

  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Only this service-only RPC resolves the trusted Apple provider identity.
    // Apple subject identifiers and client-editable metadata are never user UUIDs.
    const { error } = await supabase.rpc("process_apple_account_event", {
      p_subject: event.sub,
      p_type: event.type,
      p_event_time: event.event_time,
      p_email: event.email ?? null,
    });
    if (error) throw new Error("Apple event persistence failed");
    return new Response(JSON.stringify({ success: true }), { status: 200, headers });
  } catch {
    // Retry delivery when processing fails; never acknowledge an unapplied event.
    return new Response(JSON.stringify({ error: "Unable to process notification" }), { status: 500, headers });
  }
});
