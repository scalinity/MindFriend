// MindFriend Exit Quest Arc Edge Function
// Abandons user's active or paused quest arc
// See: docs/specs/quest-arcs-formal-spec.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders, validateContentType, parseJsonBody } from "../_shared/cors.ts";
import { enforceHTTPS, getSecurityHeaders } from "../_shared/https-enforcement.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

serve(async (req) => {
  // SECURITY: Enforce HTTPS in production
  const httpsCheck = enforceHTTPS(req);
  if (!httpsCheck.secure) {
    return httpsCheck.error!;
  }

  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    ...getSecurityHeaders(),
    "Content-Type": "application/json",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(origin) });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // SECURITY: Validate Authorization header exists
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing or invalid Authorization header" }), {
        status: 401,
        headers,
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    // SECURITY: Rate limiting
    const rateLimit = checkRateLimit(user.id, 60);
    if (!rateLimit.allowed) {
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          resetAt: rateLimit.resetAt,
        }),
        {
          status: 429,
          headers: {
            ...headers,
            "Retry-After": String(Math.ceil((rateLimit.resetAt.getTime() - Date.now()) / 1000)),
          },
        },
      );
    }

    // SECURITY: Safe JSON parsing (allow empty body)
    const body = await parseJsonBody<{ userArcId?: string }>(req) || {};
    const { userArcId } = body;

    // Find active or paused arc
    let query = supabase
      .from("user_quest_arcs")
      .select("id, status")
      .eq("user_id", user.id);

    if (userArcId) {
      query = query.eq("id", userArcId);
    } else {
      query = query.in("status", ["active", "paused"]);
    }

    const { data: arc, error: arcError } = await query.single();

    if (arcError || !arc) {
      return new Response(
        JSON.stringify({ error: "No active or paused arc found" }),
        { status: 404, headers },
      );
    }

    // Abandon the arc
    const abandonedAt = new Date().toISOString();
    const { error: updateError } = await supabase
      .from("user_quest_arcs")
      .update({
        status: "abandoned",
        abandoned_at: abandonedAt,
      })
      .eq("id", arc.id)
      .eq("user_id", user.id); // SECURITY: Double-check ownership

    if (updateError) {
      console.error("Error abandoning arc:", { code: updateError.code });
      return new Response(JSON.stringify({ error: "Failed to exit arc" }), {
        status: 500,
        headers,
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        abandonedAt,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("exit-quest-arc error:", { message: (error as Error).message });
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
