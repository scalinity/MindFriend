// MindFriend Resume Quest Arc Edge Function
// Resumes user's paused quest arc
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

    // SECURITY: Validate Content-Type and parse JSON
    const contentTypeError = validateContentType(req, headers);
    if (contentTypeError) return contentTypeError;

    const body = await parseJsonBody<{ userArcId?: string }>(req);
    if (!body || !body.userArcId) {
      return new Response(JSON.stringify({ error: "Invalid request body or missing userArcId" }), {
        status: 400,
        headers,
      });
    }

    const { userArcId } = body;

    // Get arc enrollment
    const { data: arc, error: arcError } = await supabase
      .from("user_quest_arcs")
      .select("id, arc_id, current_day, status, paused_at")
      .eq("id", userArcId)
      .eq("user_id", user.id)
      .single();

    if (arcError || !arc) {
      return new Response(
        JSON.stringify({ error: "Arc enrollment not found" }),
        { status: 404, headers },
      );
    }

    // Check if paused and not expired (30 days)
    if (arc.status === "paused" && arc.paused_at) {
      const pausedDate = new Date(arc.paused_at);
      const daysSincePaused = Math.floor(
        (Date.now() - pausedDate.getTime()) / (1000 * 60 * 60 * 24),
      );

      if (daysSincePaused > 30) {
        return new Response(
          JSON.stringify({
            error:
              "Arc expired (paused > 30 days). Start a new arc or abandon this one.",
            code: "ARC_EXPIRED",
          }),
          { status: 410, headers },
        );
      }
    }

    // Resume the arc
    const { error: updateError } = await supabase
      .from("user_quest_arcs")
      .update({
        status: "active",
        paused_at: null,
      })
      .eq("id", arc.id)
      .eq("user_id", user.id); // SECURITY: Double-check ownership

    if (updateError) {
      console.error("Error resuming arc:", { code: updateError.code });
      return new Response(JSON.stringify({ error: "Failed to resume arc" }), {
        status: 500,
        headers,
      });
    }

    // Get next quest template
    const { data: nextStep } = await supabase
      .from("quest_arc_steps")
      .select("quest_template_id, quest_templates(id, title, description, category, difficulty, xp_reward)")
      .eq("arc_id", arc.arc_id)
      .eq("day_number", arc.current_day + 1)
      .single();

    return new Response(
      JSON.stringify({
        success: true,
        currentDay: arc.current_day,
        nextQuestTemplate: nextStep?.quest_templates || null,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("resume-quest-arc error:", { message: (error as Error).message });
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
