// MindFriend Get Quest Arcs Edge Function
// Lists available quest arcs with user progress
// See: docs/specs/quest-arcs-formal-spec.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { enforceHTTPS, getSecurityHeaders } from "../_shared/https-enforcement.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

interface QuestArc {
  id: string;
  title: string;
  description: string;
  category: string;
  durationDays: number;
  difficultyLevel: string;
  isPremium: boolean;
  milestoneDays: number[];
  iconName: string | null;
  stepCount: number;
  userEnrolled: boolean;
  userCompleted: boolean;
  userProgress?: number;
}

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
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
        },
      },
    );

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    // SECURITY: Rate limiting
    const rateLimit = checkRateLimit(user.id, 120); // Higher limit for read-only operation
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

    // Parse query parameters
    const url = new URL(req.url);
    const category = url.searchParams.get("category");
    const includeCompleted =
      url.searchParams.get("includeCompleted") === "true";

    // Get all active arcs - SECURITY: Explicit column selection
    let query = supabase
      .from("quest_arcs")
      .select(
        "id, title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name",
      )
      .eq("is_active", true);

    if (category) {
      query = query.eq("category", category);
    }

    const { data: arcs, error: arcsError } = await query;

    if (arcsError) {
      console.error("Error fetching arcs:", { code: arcsError.code });
      return new Response(JSON.stringify({ error: "Failed to fetch arcs" }), {
        status: 500,
        headers,
      });
    }

    // Get user's enrollments
    const { data: enrollments, error: enrollmentError } = await supabase
      .from("user_quest_arcs")
      .select("arc_id, status, current_day")
      .eq("user_id", user.id);

    if (enrollmentError) {
      console.error("Error fetching enrollments:", { code: enrollmentError.code });
    }

    // Get step counts for each arc
    const arcIds = arcs?.map((a) => a.id) || [];
    const { data: stepCounts, error: stepsError } = await supabase
      .from("quest_arc_steps")
      .select("arc_id")
      .in("arc_id", arcIds);

    if (stepsError) {
      console.error("Error fetching step counts:", { code: stepsError.code });
    }

    // Build enrollment map
    const enrollmentMap = new Map(enrollments?.map((e) => [e.arc_id, e]) || []);

    // Count steps per arc
    const stepCountMap = new Map<string, number>();
    stepCounts?.forEach((step) => {
      stepCountMap.set(step.arc_id, (stepCountMap.get(step.arc_id) || 0) + 1);
    });

    // Enrich arcs with user data
    const enrichedArcs: QuestArc[] = (arcs || []).map((arc) => {
      const enrollment = enrollmentMap.get(arc.id);
      const userEnrolled = enrollment?.status === "active";
      const userCompleted = enrollment?.status === "completed";

      return {
        id: arc.id,
        title: arc.title,
        description: arc.description,
        category: arc.category,
        durationDays: arc.duration_days,
        difficultyLevel: arc.difficulty_level,
        isPremium: arc.is_premium,
        milestoneDays: arc.milestone_days || [],
        iconName: arc.icon_name,
        stepCount: stepCountMap.get(arc.id) || 0,
        userEnrolled,
        userCompleted,
        userProgress: userEnrolled ? enrollment?.current_day : undefined,
      };
    });

    // Filter out completed arcs if not requested
    const filteredArcs = includeCompleted
      ? enrichedArcs
      : enrichedArcs.filter((a) => !a.userCompleted);

    // Sort by difficulty: easy, medium, hard
    const difficultyOrder: Record<string, number> = {
      easy: 1,
      medium: 2,
      hard: 3,
    };
    filteredArcs.sort((a, b) => {
      const categoryCompare = a.category.localeCompare(b.category);
      if (categoryCompare !== 0) return categoryCompare;
      return (
        (difficultyOrder[a.difficultyLevel] || 0) -
        (difficultyOrder[b.difficultyLevel] || 0)
      );
    });

    return new Response(JSON.stringify({ arcs: filteredArcs }), {
      status: 200,
      headers,
    });
  } catch (error) {
    console.error("get-quest-arcs error:", { message: (error as Error).message });
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
