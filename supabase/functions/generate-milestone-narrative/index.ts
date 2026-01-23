// MindFriend Generate Milestone Narrative
// AI-powered personalized milestone story generation

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface MilestoneRequest {
  level: number;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: corsHeaders },
      );
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const body: MilestoneRequest = await req.json();
    const level = body.level;

    // Validate milestone level
    const milestones = [5, 10, 25, 50, 100];
    if (!milestones.includes(level)) {
      return new Response(
        JSON.stringify({ error: "Not a milestone level" }),
        { status: 400, headers: corsHeaders },
      );
    }

    // Check if narrative already exists
    const { data: existing } = await supabase
      .from("milestone_celebrations")
      .select("*")
      .eq("user_id", user.id)
      .eq("level_reached", level)
      .single();

    if (existing) {
      return new Response(
        JSON.stringify({
          success: true,
          narrative: existing.narrative,
          celebrationId: existing.id,
          stats: existing.journey_stats,
          cached: true,
        }),
        { status: 200, headers: corsHeaders },
      );
    }

    // Gather user journey stats
    const [quests, exercises, moods, profile, badges] = await Promise.all([
      supabase
        .from("quests")
        .select("*", { count: "exact", head: true })
        .eq("user_id", user.id)
        .eq("completed", true),
      supabase
        .from("exercise_sessions")
        .select("*", { count: "exact", head: true })
        .eq("user_id", user.id),
      supabase
        .from("moods")
        .select("*", { count: "exact", head: true })
        .eq("user_id", user.id),
      supabase
        .from("profiles")
        .select("stats, created_at")
        .eq("id", user.id)
        .single(),
      supabase
        .from("user_badges_v2")
        .select("*", { count: "exact", head: true })
        .eq("user_id", user.id)
        .eq("is_earned", true),
    ]);

    const stats = {
      total_quests: quests.count || 0,
      total_exercises: exercises.count || 0,
      total_mood_logs: moods.count || 0,
      current_streak: profile.data?.stats?.currentStreak || 0,
      longest_streak: profile.data?.stats?.longestStreak || 0,
      total_circle_posts: 0,
      badges_earned: badges.count || 0,
      days_active: Math.floor(
        (Date.now() - new Date(profile.data?.created_at || Date.now()).getTime()) /
          (1000 * 60 * 60 * 24),
      ),
    };

    // Generate narrative with XAI
    const prompt = `You are a compassionate wellness companion. Write a personalized 150-200 word celebration for a user reaching level ${level} in their wellness journey.

User's journey:
- Completed ${stats.total_quests} daily quests
- Practiced ${stats.total_exercises} exercises
- Logged ${stats.total_mood_logs} mood entries
- Current streak: ${stats.current_streak} days
- Longest streak: ${stats.longest_streak} days
- Earned ${stats.badges_earned} badges
- Active for ${stats.days_active} days

Write in a warm, encouraging tone. Focus on growth, resilience, and self-compassion. Make it feel personal and meaningful. Use 2-3 relevant emoji. Keep it 150-200 words.`;

    const xaiResponse = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${Deno.env.get("XAI_API_KEY")}`,
      },
      body: JSON.stringify({
        model: "grok-beta",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.8,
        max_tokens: 500,
      }),
    });

    if (!xaiResponse.ok) {
      throw new Error("XAI API request failed");
    }

    const xaiData = await xaiResponse.json();
    const narrative = xaiData.choices[0].message.content;

    // Store milestone celebration
    const { data: celebration, error: dbError } = await supabase
      .from("milestone_celebrations")
      .insert({
        user_id: user.id,
        level_reached: level,
        narrative: narrative,
        journey_stats: stats,
      })
      .select()
      .single();

    if (dbError) {
      console.error("Error storing milestone:", dbError);
      return new Response(
        JSON.stringify({ error: "Failed to store milestone" }),
        { status: 500, headers: corsHeaders },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        narrative: narrative,
        celebrationId: celebration.id,
        stats: stats,
      }),
      { status: 200, headers: corsHeaders },
    );
  } catch (error) {
    console.error("Error:", error);
    
    // Fallback template
    const fallbackNarrative = `Congratulations on reaching level ${(await req.json()).level}! 🎉 This is a significant milestone in your wellness journey. You've shown incredible dedication and commitment to your mental health. Every quest completed, every mood logged, and every exercise practiced has brought you here. Your resilience and self-compassion are truly inspiring. Keep nurturing your well-being—you're doing amazing! 🌟`;
    
    return new Response(
      JSON.stringify({
        success: true,
        narrative: fallbackNarrative,
        fallback: true,
        error: error.message,
      }),
      { status: 200, headers: corsHeaders },
    );
  }
});
