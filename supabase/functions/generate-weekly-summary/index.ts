// MindFriend Weekly Summary Generator with AI Insights
// Runs hourly via Supabase cron, sends summary at 6 PM Sunday local time
// Also supports manual trigger via ?user_id=<uuid> query param
// See: specs/04-smart-notifications.md, specs/06-weekly-insights.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  isAuthorizedCronRequest,
  authenticateRequest,
  isAuthError,
} from "../_shared/auth.ts";
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
  avg_anxiety: number | null;
  avg_energy: number | null;
  mood_trend: "improving" | "stable" | "declining" | "insufficient_data" | null;
  anxiety_trend:
    | "improving"
    | "stable"
    | "declining"
    | "insufficient_data"
    | null;
  energy_trend:
    | "improving"
    | "stable"
    | "declining"
    | "insufficient_data"
    | null;
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

  // Check for cron/service role auth
  const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const isCronOrServiceRole = isAuthorizedCronRequest(
    req.headers,
    expectedCronSecret,
    serviceRoleKey,
  );

  // Check for user JWT auth (for on-demand generation)
  let authenticatedUserId: string | null = null;
  const authHeader = req.headers.get("Authorization");

  console.log(
    `Auth check - isCronOrServiceRole: ${isCronOrServiceRole}, hasAuthHeader: ${!!authHeader}`,
  );

  if (!isCronOrServiceRole && authHeader?.startsWith("Bearer ")) {
    // Use shared auth utility for consistent token validation
    const authResult = await authenticateRequest(req);

    if (isAuthError(authResult)) {
      console.error("Auth error validating user token");
      // Don't return the error response yet - we'll check below
    } else {
      authenticatedUserId = authResult.user.id;
      console.log(`Authenticated user: ${authResult.user.id}`);
    }
  }

  // Must be either cron/service role OR authenticated user
  if (!isCronOrServiceRole && !authenticatedUserId) {
    console.error(
      `Unauthorized request - no valid cron/service role auth and no authenticated user`,
    );
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    // Initialize Supabase client with service role for data operations
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    const now = new Date();

    // If authenticated user, generate their own insight (on-demand)
    if (authenticatedUserId) {
      console.log(
        `On-demand insight generation for user: ${authenticatedUserId}`,
      );

      const result = await processUserWithInsights(
        supabaseAdmin,
        authenticatedUserId,
        now,
        xaiApiKey,
        false, // Don't send notification for on-demand triggers
      );

      return new Response(
        JSON.stringify({
          success: true,
          onDemand: true,
          userId: authenticatedUserId,
          timestamp: now.toISOString(),
          ...result,
        }),
        { status: 200, headers },
      );
    }

    // Check for manual trigger via query param (cron/service role only)
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
  // getDay(): 0=Sunday, 1=Monday, ..., 6=Saturday
  // For Sunday (0), go back 6 days; for Monday (1), go back 0 days; etc.
  const weekStart = new Date(now);
  const dayOfWeek = weekStart.getDay();
  const daysFromMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
  weekStart.setDate(weekStart.getDate() - daysFromMonday);
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
    avg_anxiety: null,
    avg_energy: null,
    mood_trend: null,
    anxiety_trend: null,
    energy_trend: null,
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

  // Fetch recent mood notes from this week
  const { data: moodNotes } = await supabase
    .from("moods")
    .select("note")
    .eq("user_id", userId)
    .gte("local_date", weekStartStr)
    .not("note", "is", null)
    .order("created_at", { ascending: false })
    .limit(10);

  const recentNotes: string[] = (moodNotes || [])
    .map((m: { note: string | null }) => m.note)
    .filter((n): n is string => n !== null && n.trim().length > 0);

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
    avgAnxiety: stats.avg_anxiety,
    avgEnergy: stats.avg_energy,
    moodTrend: stats.mood_trend,
    anxietyTrend: stats.anxiety_trend,
    energyTrend: stats.energy_trend,
    questCount: stats.quest_count,
    exerciseCount: stats.exercise_count,
    exerciseMinutes: stats.exercise_minutes,
    checkinCount: stats.checkin_count,
    circleCheckinCount: stats.circle_checkin_count,
    patterns,
    streakDays: userProfile?.current_streak_days || 0,
    recentNotes,
  };

  const aiInsight = await generateAIInsight(insightContext, xaiApiKey);

  // Aggregate cognitive distortions for this week
  const { data: distortionData, error: distortionError } = await supabase
    .from("distortion_encounters")
    .select("distortion_code")
    .eq("user_id", userId)
    .gte("occurred_at", `${weekStartStr}T00:00:00Z`)
    .lt(
      "occurred_at",
      new Date(
        new Date(weekStartStr).getTime() + 7 * 24 * 60 * 60 * 1000,
      ).toISOString(),
    );

  if (distortionError) {
    console.error("Error fetching distortions for", userId, distortionError);
  }

  // Count distortions by code
  const distortionCounts: Record<string, number> = {};
  (distortionData || []).forEach((encounter: { distortion_code: string }) => {
    distortionCounts[encounter.distortion_code] =
      (distortionCounts[encounter.distortion_code] || 0) + 1;
  });

  // Determine new patterns (distortions not seen in previous weeks)
  const { data: previousWeekDistortions } = await supabase
    .from("distortion_encounters")
    .select("DISTINCT distortion_code")
    .eq("user_id", userId)
    .lt("occurred_at", `${weekStartStr}T00:00:00Z`);

  const previousCodes = new Set(
    (previousWeekDistortions || []).map(
      (d: { distortion_code: string }) => d.distortion_code,
    ),
  );

  const newPatterns = Object.keys(distortionCounts).filter(
    (code) => !previousCodes.has(code),
  );

  // Upsert into weekly_pattern_summaries if there are distortions
  if (Object.keys(distortionCounts).length > 0) {
    const { error: patternError } = await supabase
      .from("weekly_pattern_summaries")
      .upsert(
        {
          user_id: userId,
          week_start: weekStartStr,
          distortion_counts: distortionCounts,
          new_patterns: newPatterns,
          total_encounters: Object.values(distortionCounts).reduce(
            (a, b) => a + b,
            0,
          ),
          generated_at: now.toISOString(),
        },
        {
          onConflict: "user_id,week_start",
        },
      );

    if (patternError) {
      console.error(
        "Error upserting pattern summary for",
        userId,
        patternError,
      );
      // Don't throw - this is secondary data, don't block weekly summary
    }
  }

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
