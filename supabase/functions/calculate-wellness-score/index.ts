// Daily Wellness Score Calculation Edge Function
// Triggered nightly at 3 AM UTC to calculate canonical wellness scores
// and persist to daily_signals table

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { calculateWellnessScore } from "./algorithm.ts";
import type { WellnessScoreInput } from "./types.ts";

serve(async (req) => {
  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get target date from query params (defaults to yesterday)
    const url = new URL(req.url);
    const targetDate =
      url.searchParams.get("date") ||
      new Date(Date.now() - 86400000).toISOString().split("T")[0];

    console.log(`Calculating wellness scores for ${targetDate}`);

    // Get all active users (users with activity in the past 7 days)
    const { data: activeUsers, error: usersError } = await supabaseAdmin
      .from("profiles")
      .select("id")
      .gte("last_active_at", new Date(Date.now() - 7 * 86400000).toISOString());

    if (usersError) {
      throw new Error(`Failed to fetch active users: ${usersError.message}`);
    }

    let processed = 0;
    const errors: string[] = [];

    // Process each user
    for (const user of activeUsers || []) {
      try {
        // Gather data for target date
        const input = await gatherUserData(supabaseAdmin, user.id, targetDate);

        // Calculate score
        const result = calculateWellnessScore(input);

        // Persist to daily_signals
        const { error: upsertError } = await supabaseAdmin
          .from("daily_signals")
          .upsert(
            {
              user_id: user.id,
              signal_date: targetDate,
              wellness_score: result.score,
              wellness_confidence: result.confidence,
              wellness_components: result.components,
              wellness_calculated_at: new Date().toISOString(),
            },
            {
              onConflict: "user_id,signal_date",
            },
          );

        if (upsertError) {
          errors.push(`User ${user.id}: ${upsertError.message}`);
        } else {
          processed++;
        }
      } catch (error) {
        errors.push(`User ${user.id}: ${error.message}`);
      }
    }

    return new Response(
      JSON.stringify({ processed, errors: errors.slice(0, 10) }), // Limit error output
      {
        headers: { "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    console.error("Wellness score calculation failed:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        headers: { "Content-Type": "application/json" },
        status: 500,
      },
    );
  }
});

/**
 * Gather all data needed for wellness score calculation
 */
async function gatherUserData(
  supabase: any,
  userId: string,
  date: string,
): Promise<WellnessScoreInput> {
  const startOfDay = `${date}T00:00:00.000Z`;
  const endOfDay = `${date}T23:59:59.999Z`; // Fixed: include all milliseconds

  // Fetch moods for the day (including anxiety and energy)
  const { data: moods, error: moodsError } = await supabase
    .from("moods")
    .select("mood_score, anxiety_score, energy_score, timestamp")
    .eq("user_id", userId)
    .gte("timestamp", startOfDay)
    .lte("timestamp", endOfDay);

  if (moodsError) {
    console.error(`[${userId}] Moods fetch failed:`, moodsError);
  }

  // Fetch quest status
  const { data: quest } = await supabase
    .from("quests")
    .select("status")
    .eq("user_id", userId)
    .eq("local_date", date)
    .single();

  // Fetch circle check-ins
  const { data: circles } = await supabase
    .from("circle_posts")
    .select("id")
    .eq("user_id", userId)
    .gte("created_at", startOfDay)
    .lte("created_at", endOfDay);

  // Fetch exercises
  const { data: exercises } = await supabase
    .from("exercise_sessions")
    .select("duration_seconds")
    .eq("user_id", userId)
    .gte("completed_at", startOfDay)
    .lte("completed_at", endOfDay);

  const exerciseMinutes =
    exercises?.reduce((sum, e) => sum + e.duration_seconds / 60, 0) || 0;

  // Fetch biometric data (including HRV and resting heart rate)
  const { data: biometric } = await supabase
    .from("biometric_daily_summaries")
    .select(
      "sleep_duration_minutes, sleep_quality, steps_count, exercise_minutes, hrv_average_ms, resting_heart_rate",
    )
    .eq("user_id", userId)
    .eq("summary_date", date)
    .single();

  // Fetch mood variance from daily_signals
  const { data: dailySignal } = await supabase
    .from("daily_signals")
    .select("mood_variance, app_sessions, total_active_minutes")
    .eq("user_id", userId)
    .eq("signal_date", date)
    .single();

  return {
    userId,
    date,
    moods:
      moods?.map((m) => ({
        moodScore: m.mood_score,
        anxietyScore: m.anxiety_score,
        energyScore: m.energy_score,
        timestamp: m.timestamp,
      })) || [],
    moodVariance: dailySignal?.mood_variance,
    questCompleted: quest?.status === "completed",
    circleCheckins: circles?.length || 0,
    exerciseMinutes: Math.round(exerciseMinutes),
    appSessions: dailySignal?.app_sessions,
    totalActiveMinutes: dailySignal?.total_active_minutes,
    sleepHours: biometric?.sleep_duration_minutes
      ? biometric.sleep_duration_minutes / 60
      : undefined,
    sleepQuality: biometric?.sleep_quality,
    activitySteps: biometric?.steps_count,
    exerciseMinutesFromBiometrics: biometric?.exercise_minutes,
    hrvAverageMs: biometric?.hrv_average_ms,
    restingHeartRate: biometric?.resting_heart_rate,
  };
}
