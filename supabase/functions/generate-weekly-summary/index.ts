// MindFriend Weekly Summary Generator with AI Insights
// Runs hourly via Supabase cron, sends summary at 6 PM Sunday local time
// Also supports manual trigger via ?user_id=<uuid> query param
// See: specs/04-smart-notifications.md, specs/06-weekly-insights.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import { getMoodTrendMessage } from "../_shared/notification-utils.ts";
import {
  detectPatterns,
  Pattern,
  MoodData,
  ExerciseCorrelation,
} from "../_shared/pattern-detection.ts";
import {
  generateAIInsight,
  AIInsightResult,
  InsightContext,
} from "../_shared/ai-insights.ts";

// Concurrency limit for parallel processing
const CONCURRENCY_LIMIT = 10;

interface UserForSummary {
  user_id: string;
  push_token: string;
  timezone: string;
}

interface UserProfile {
  id: string;
  display_name: string | null;
  wellness_focus: string | null;
  current_streak_days: number;
}

interface ExtendedWeeklyStats {
  checkin_count: number;
  quest_count: number;
  exercise_count: number;
  avg_mood: number | null;
  mood_trend: "improving" | "stable" | "declining" | "insufficient_data" | null;
  mood_min: number | null;
  mood_max: number | null;
  mood_by_day: Record<string, number>;
  circle_checkin_count: number;
  exercise_minutes: number;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  // Require cron secret or service role key
  const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

  if (
    !isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey)
  ) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    // Initialize Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    const now = new Date();

    // Check for manual trigger via query param
    const url = new URL(req.url);
    const manualUserId = url.searchParams.get("user_id");

    if (manualUserId) {
      // Manual trigger for single user (development/testing)
      console.log(`Manual insight generation for user: ${manualUserId}`);

      const result = await processUserWithInsights(
        supabaseAdmin,
        manualUserId,
        now,
        xaiApiKey,
        false, // Don't send notification for manual triggers
      );

      return new Response(
        JSON.stringify({
          success: true,
          manual: true,
          userId: manualUserId,
          timestamp: now.toISOString(),
          ...result,
        }),
        { status: 200, headers },
      );
    }

    // Standard cron-triggered flow
    const results = {
      processed: 0,
      summariesGenerated: 0,
      notificationsSent: 0,
      errors: 0,
    };

    // Get users who should receive weekly summary (Sunday 6 PM local)
    const { data: usersForSummary, error: fetchError } =
      await supabaseAdmin.rpc("get_users_for_weekly_summary");

    if (fetchError) {
      console.error("Error fetching users for summary:", fetchError);
      return new Response(JSON.stringify({ error: "Failed to fetch users" }), {
        status: 500,
        headers,
      });
    }

    if (!usersForSummary || usersForSummary.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users ready for weekly summary",
          timestamp: now.toISOString(),
        }),
        { status: 200, headers },
      );
    }

    console.log(
      `Processing weekly insights for ${usersForSummary.length} users`,
    );

    // Process users in parallel with concurrency limit
    const users = usersForSummary as UserForSummary[];

    for (let i = 0; i < users.length; i += CONCURRENCY_LIMIT) {
      const chunk = users.slice(i, i + CONCURRENCY_LIMIT);
      const chunkResults = await Promise.allSettled(
        chunk.map((user) =>
          processUserWithInsights(
            supabaseAdmin,
            user.user_id,
            now,
            xaiApiKey,
            true,
          ),
        ),
      );

      for (const result of chunkResults) {
        results.processed++;
        if (result.status === "fulfilled") {
          results.summariesGenerated++;
          if (result.value.notificationSent) {
            results.notificationsSent++;
          }
        } else {
          console.error("User processing failed:", result.reason);
          results.errors++;
        }
      }
    }

    console.log("Weekly insights generation complete:", results);

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: now.toISOString(),
        ...results,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Weekly insights generator error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});

/**
 * Process a single user's weekly summary with AI insights
 */
async function processUserWithInsights(
  supabase: SupabaseClient,
  userId: string,
  now: Date,
  xaiApiKey: string | undefined,
  sendNotification: boolean,
): Promise<{
  success: boolean;
  notificationSent: boolean;
  stats?: ExtendedWeeklyStats;
  patterns?: Pattern[];
  aiInsight?: AIInsightResult;
}> {
  // Calculate week start (Monday of current week)
  const weekStart = new Date(now);
  weekStart.setDate(weekStart.getDate() - weekStart.getDay() + 1);
  weekStart.setHours(0, 0, 0, 0);
  const weekStartStr = weekStart.toISOString().split("T")[0];

  // Fetch user profile for personalization
  const { data: profile } = await supabase
    .from("profiles")
    .select("id, display_name, wellness_focus, current_streak_days")
    .eq("id", userId)
    .single();

  const userProfile = profile as UserProfile | null;

  // Calculate extended weekly stats
  const { data: statsData, error: statsError } = await supabase.rpc(
    "calculate_weekly_stats_extended",
    { p_user_id: userId },
  );

  if (statsError) {
    console.error("Error calculating stats for", userId, statsError);
    throw new Error(`Stats error: ${statsError.message}`);
  }

  const stats: ExtendedWeeklyStats = statsData?.[0] || {
    checkin_count: 0,
    quest_count: 0,
    exercise_count: 0,
    avg_mood: null,
    mood_trend: null,
    mood_min: null,
    mood_max: null,
    mood_by_day: {},
    circle_checkin_count: 0,
    exercise_minutes: 0,
  };

  // Fetch mood data for pattern detection
  const { data: moodData } = await supabase.rpc(
    "get_moods_for_pattern_analysis",
    {
      p_user_id: userId,
      p_weeks: 4,
    },
  );

  // Fetch exercise-mood correlations
  const { data: exerciseData } = await supabase.rpc(
    "get_exercise_mood_correlation",
    {
      p_user_id: userId,
      p_weeks: 4,
    },
  );

  // Detect patterns
  const patterns = detectPatterns(
    (moodData as MoodData[]) || [],
    (exerciseData as ExerciseCorrelation[]) || [],
    userProfile?.current_streak_days || 0,
    stats.avg_mood,
  );

  // Generate AI insight
  const insightContext: InsightContext = {
    userName: userProfile?.display_name || undefined,
    wellnessFocus: userProfile?.wellness_focus || undefined,
    avgMood: stats.avg_mood,
    moodTrend: stats.mood_trend,
    questCount: stats.quest_count,
    exerciseCount: stats.exercise_count,
    exerciseMinutes: stats.exercise_minutes,
    checkinCount: stats.checkin_count,
    circleCheckinCount: stats.circle_checkin_count,
    patterns,
    streakDays: userProfile?.current_streak_days || 0,
  };

  const aiInsight = await generateAIInsight(insightContext, xaiApiKey);

  // Upsert weekly summary with all extended data
  const { error: upsertError } = await supabase.from("weekly_summaries").upsert(
    {
      user_id: userId,
      week_start: weekStartStr,
      checkin_count: stats.checkin_count,
      quest_count: stats.quest_count,
      exercise_count: stats.exercise_count,
      avg_mood: stats.avg_mood,
      mood_trend: stats.mood_trend,
      mood_min: stats.mood_min,
      mood_max: stats.mood_max,
      mood_by_day: stats.mood_by_day,
      circle_checkin_count: stats.circle_checkin_count,
      exercise_minutes: stats.exercise_minutes,
      patterns_detected: patterns,
      ai_insight: aiInsight.insight,
      ai_recommendations: aiInsight.recommendations,
      generated_at: now.toISOString(),
    },
    {
      onConflict: "user_id,week_start",
    },
  );

  if (upsertError) {
    console.error("Error upserting summary for", userId, upsertError);
    throw new Error(`Upsert error: ${upsertError.message}`);
  }

  // Send notification if requested
  let notificationSent = false;
  if (sendNotification) {
    const moodMessage = getMoodTrendMessage(stats.mood_trend, stats.avg_mood);

    const response = await supabase.functions.invoke("send-notification", {
      body: {
        type: "weekly_summary",
        recipientId: userId,
        data: {
          checkins: stats.checkin_count,
          quests: stats.quest_count,
          exercises: stats.exercise_count,
          avgMood: stats.avg_mood,
          moodTrend: stats.mood_trend,
          moodMessage,
          hasInsights: true,
        },
      },
    });

    if (response.error) {
      console.error("Error sending notification to", userId, response.error);
    } else {
      notificationSent = true;
    }
  }

  return {
    success: true,
    notificationSent,
    stats,
    patterns,
    aiInsight,
  };
}
