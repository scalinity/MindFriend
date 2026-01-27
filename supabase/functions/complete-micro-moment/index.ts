// MindFriend Complete Micro-Moment Edge Function
// Records micro-moment completions and updates streaks

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface CompletionRequest {
  templateId: string;
  triggerSource?: string;
  context?: string;
  startedAt: string;
  completedAt: string;
  durationActualSeconds: number;
  feltHelpful?: boolean;
}

interface MicroStreak {
  id: string;
  user_id: string;
  current_streak: number;
  longest_streak: number;
  last_micro_date: string | null;
  total_micro_moments: number;
  total_check_ins: number;
  total_seconds_practiced: number;
  achievements_unlocked: string[] | null;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body: CompletionRequest = await req.json();

    // Validate required fields
    if (!body.templateId || !body.startedAt || !body.completedAt) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: templateId, startedAt, completedAt",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate templateId exists
    const { data: template, error: templateError } = await supabase
      .from("micro_moment_templates")
      .select("id, title, type, duration_seconds")
      .eq("id", body.templateId)
      .single();

    if (templateError || !template) {
      return new Response(JSON.stringify({ error: "Template not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate trigger_source enum
    const validSources = [
      "manual",
      "notification",
      "widget",
      "siri",
      "watch",
      "suggestion",
    ];
    const triggerSource =
      body.triggerSource && validSources.includes(body.triggerSource)
        ? body.triggerSource
        : "manual";

    // Sanitize duration
    const durationActualSeconds =
      typeof body.durationActualSeconds === "number"
        ? Math.max(0, Math.min(body.durationActualSeconds, 300))
        : template.duration_seconds;

    // Record completion (trigger will update streak)
    const { data: completion, error: completionError } = await supabase
      .from("micro_moment_completions")
      .insert({
        user_id: user.id,
        template_id: body.templateId,
        trigger_source: triggerSource,
        context: body.context || null,
        started_at: body.startedAt,
        completed_at: body.completedAt,
        duration_actual_seconds: durationActualSeconds,
        completed: true,
        felt_helpful: body.feltHelpful ?? null,
      })
      .select()
      .single();

    if (completionError) {
      console.error("Completion insert error:", completionError);
      return new Response(
        JSON.stringify({ error: "Failed to record completion" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get updated streak (trigger should have updated it)
    const { data: streak, error: streakError } = await supabase
      .from("micro_streaks")
      .select("*")
      .eq("user_id", user.id)
      .single();

    // If no streak exists yet, the trigger should have created one
    // But just in case, provide a default response
    const streakData: MicroStreak = streak || {
      id: "",
      user_id: user.id,
      current_streak: 1,
      longest_streak: 1,
      last_micro_date: new Date().toISOString().split("T")[0],
      total_micro_moments: 1,
      total_check_ins: 0,
      total_seconds_practiced: durationActualSeconds,
      achievements_unlocked: ["first_micro"],
    };

    // Check for new achievements to notify about
    // An achievement is "new" if the user just hit the exact threshold for earning it
    const newAchievements: string[] = [];
    const achievements = streakData.achievements_unlocked || [];

    // First micro-moment ever
    if (
      streakData.total_micro_moments === 1 &&
      achievements.includes("first_micro")
    ) {
      newAchievements.push("first_micro");
    }

    // 7-day streak (exact threshold - only on first reaching 7)
    if (
      streakData.current_streak === 7 &&
      achievements.includes("week_streak")
    ) {
      newAchievements.push("week_streak");
    }

    // 30-day streak (exact threshold - only on first reaching 30)
    if (
      streakData.current_streak === 30 &&
      achievements.includes("month_streak")
    ) {
      newAchievements.push("month_streak");
    }

    // 100 micro-moments milestone
    if (
      streakData.total_micro_moments === 100 &&
      achievements.includes("micro_century")
    ) {
      newAchievements.push("micro_century");
    }

    // 50 micro-moments milestone
    if (
      streakData.total_micro_moments === 50 &&
      achievements.includes("micro_half_century")
    ) {
      newAchievements.push("micro_half_century");
    }

    return new Response(
      JSON.stringify({
        completion: {
          id: completion.id,
          templateId: completion.template_id,
          completed: true,
          createdAt: completion.created_at,
        },
        streak: {
          currentStreak: streakData.current_streak,
          longestStreak: streakData.longest_streak,
          lastMicroDate: streakData.last_micro_date,
          totalMicroMoments: streakData.total_micro_moments,
          totalCheckIns: streakData.total_check_ins,
          totalSecondsPracticed: streakData.total_seconds_practiced,
          achievementsUnlocked: streakData.achievements_unlocked || [],
        },
        newAchievements,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error completing micro-moment:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...getCorsHeaders(null), "Content-Type": "application/json" },
    });
  }
});
