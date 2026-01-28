// MindFriend Start Quest Arc Edge Function
// Enrolls user in a quest arc
// See: docs/specs/quest-arcs-formal-spec.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  getCorsHeaders,
  validateContentType,
  parseJsonBody,
} from "../_shared/cors.ts";
import {
  enforceHTTPS,
  getSecurityHeaders,
} from "../_shared/https-enforcement.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { validateUuid } from "../_shared/uuid-validation.ts";

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
      return new Response(
        JSON.stringify({ error: "Missing or invalid Authorization header" }),
        {
          status: 401,
          headers,
        },
      );
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

    // SECURITY: Rate limiting (60 requests per hour per user)
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
            "Retry-After": String(
              Math.ceil((rateLimit.resetAt.getTime() - Date.now()) / 1000),
            ),
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": rateLimit.resetAt.toISOString(),
          },
        },
      );
    }

    // SECURITY: Validate Content-Type
    const contentTypeError = validateContentType(req, headers);
    if (contentTypeError) return contentTypeError;

    // SECURITY: Safe JSON parsing
    const body = await parseJsonBody<{ arcId?: string }>(req);
    if (!body || !body.arcId) {
      return new Response(
        JSON.stringify({ error: "Invalid request body or missing arcId" }),
        {
          status: 400,
          headers,
        },
      );
    }

    const { arcId } = body;

    // SECURITY: Validate UUID format before database operations
    const arcIdValidation = validateUuid(arcId, "arcId");
    if (!arcIdValidation.valid) {
      return new Response(JSON.stringify({ error: arcIdValidation.error }), {
        status: 400,
        headers,
      });
    }
    const validatedArcId = arcIdValidation.normalized!;

    // Check if user already has an active arc
    const { data: activeArc } = await supabase
      .from("user_quest_arcs")
      .select("id, arc_id, current_day, quest_arcs(title)")
      .eq("user_id", user.id)
      .eq("status", "active")
      .single();

    if (activeArc) {
      // Return 200 with success: false so Swift SDK can parse the response
      // (SDK throws on non-2xx before parsing body)
      return new Response(
        JSON.stringify({
          success: false,
          error: "You already have an active arc. Complete or exit it first.",
          code: "ALREADY_ENROLLED",
          currentArc: {
            id: activeArc.arc_id,
            title: (activeArc.quest_arcs as { title: string })?.title,
            currentDay: activeArc.current_day,
          },
        }),
        { status: 200, headers },
      );
    }

    // Get arc details - SECURITY: Explicit column selection instead of SELECT *
    const { data: arc, error: arcError } = await supabase
      .from("quest_arcs")
      .select(
        "id, title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name",
      )
      .eq("id", validatedArcId)
      .eq("is_active", true)
      .single();

    if (arcError || !arc) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Arc not found",
          code: "ARC_NOT_FOUND",
        }),
        { status: 400, headers },
      );
    }

    // Check if arc has steps
    const { data: firstStep } = await supabase
      .from("quest_arc_steps")
      .select("quest_template_id")
      .eq("arc_id", validatedArcId)
      .eq("day_number", 1)
      .single();

    if (!firstStep) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Arc has no steps defined",
          code: "NO_STEPS",
        }),
        { status: 400, headers },
      );
    }

    // Check premium requirement
    if (arc.is_premium) {
      const { data: subscription } = await supabase
        .from("subscriptions")
        .select("status")
        .eq("user_id", user.id)
        .eq("status", "active")
        .single();

      if (!subscription) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Premium subscription required",
            code: "PREMIUM_REQUIRED",
            paywallContext: {
              arcTitle: arc.title,
              arcDescription: arc.description,
              benefits: [
                "Access premium arcs",
                "Unlimited quest rerolls",
                "Advanced tracking",
              ],
            },
          }),
          { status: 403, headers },
        );
      }
    }

    // Create enrollment with snapshots
    const { data: enrollment, error: enrollError } = await supabase
      .from("user_quest_arcs")
      .insert({
        user_id: user.id,
        arc_id: validatedArcId,
        current_day: 0,
        status: "active",
        snapshot_duration_days: arc.duration_days,
        snapshot_milestone_days: arc.milestone_days || [],
      })
      .select()
      .single();

    if (enrollError) {
      console.error("Error creating enrollment:", { code: enrollError.code });
      return new Response(JSON.stringify({ error: "Failed to start arc" }), {
        status: 500,
        headers,
      });
    }

    // Get first quest template - SECURITY: Explicit column selection
    const { data: firstQuestTemplate } = await supabase
      .from("quest_templates")
      .select(
        "id, title, description, category, difficulty, xp_reward, time_estimate_minutes",
      )
      .eq("id", firstStep.quest_template_id)
      .single();

    // Get step count for this arc
    const { count: arcStepCount } = await supabase
      .from("quest_arc_steps")
      .select("*", { count: "exact", head: true })
      .eq("arc_id", validatedArcId);

    return new Response(
      JSON.stringify({
        success: true,
        userArcId: enrollment.id,
        arc: {
          id: arc.id,
          title: arc.title,
          description: arc.description,
          category: arc.category,
          duration_days: arc.duration_days,
          difficulty_level: arc.difficulty_level,
          is_premium: arc.is_premium,
          milestone_days: arc.milestone_days || [],
          icon_name: arc.icon_name,
          step_count: arcStepCount || 0,
          user_enrolled: true, // User just enrolled
          user_completed: false,
          user_progress: 0,
        },
        // Note: firstQuestTemplate omitted as it requires complex mapping to Swift model
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("start-quest-arc error:", {
      message: (error as Error).message,
    });
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
