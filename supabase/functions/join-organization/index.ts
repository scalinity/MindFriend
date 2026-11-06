import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers,
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ") || !authHeader.slice(7)) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        { status: 401, headers },
      );
    }
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.slice(7),
    );
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        { status: 401, headers },
      );
    }

    const body = await req.json();
    if (typeof body?.inviteCode !== "string" || !body.inviteCode.trim()) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid invite code format" }),
        { status: 400, headers },
      );
    }

    // The service-only RPC locks the organization and invite before claiming a
    // seat, consuming one use and granting the validated sponsorship together.
    // Identity comes only from the verified token; the invite owns organization.
    const { data, error } = await supabase.rpc(
      "join_organization_with_invite",
      {
        p_user_id: user.id,
        p_invite_code: body.inviteCode.trim().toUpperCase(),
      },
    );
    if (error || !data) {
      console.error("Organization join transaction failed:", error?.code);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to join organization",
        }),
        { status: 500, headers },
      );
    }
    const status = data.success
      ? 200
      : ["INVITE_NOT_FOUND", "ORG_NOT_FOUND"].includes(data.errorCode)
      ? 404
      : data.errorCode === "SPONSORSHIP_INACTIVE"
      ? 403
      : 400;
    return new Response(JSON.stringify(data), { status, headers });
  } catch {
    return new Response(
      JSON.stringify({ success: false, error: "Internal server error" }),
      { status: 500, headers },
    );
  }
});
