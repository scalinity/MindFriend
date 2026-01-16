// MindFriend Sync Biometrics Edge Function
// Receives biometric data from iOS HealthKit and stores it in the database
// See: docs/specs/04-biometric-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders, validateContentType } from "../_shared/cors.ts";

interface SyncPayload {
  dailySummaries: DailySummary[];
  workouts: WorkoutData[];
}

interface DailySummary {
  date: string;
  sleepDurationMinutes?: number;
  sleepQualityScore?: number;
  sleepStartTime?: string;
  sleepEndTime?: string;
  timeInBedMinutes?: number;
  hrvAverageMs?: number;
  hrvMinMs?: number;
  hrvMaxMs?: number;
  restingHeartRate?: number;
  stepsCount?: number;
  activeEnergyKcal?: number;
  exerciseMinutes?: number;
  standHours?: number;
  distanceMeters?: number;
  mindfulMinutes?: number;
}

interface WorkoutData {
  healthkitUuid: string;
  workoutType: string;
  startTime: string;
  endTime: string;
  durationMinutes: number;
  activeEnergyKcal?: number;
  distanceMeters?: number;
  averageHeartRate?: number;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Validate content type
  const contentTypeError = validateContentType(req, corsHeaders);
  if (contentTypeError) return contentTypeError;

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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

    const payload: SyncPayload = await req.json();

    // Upsert daily summaries
    let summariesSynced = 0;
    for (const summary of payload.dailySummaries || []) {
      const sleepEfficiency =
        summary.timeInBedMinutes && summary.sleepDurationMinutes
          ? summary.sleepDurationMinutes / summary.timeInBedMinutes
          : null;

      const { error } = await supabase.from("biometric_daily_summaries").upsert(
        {
          user_id: user.id,
          date: summary.date,
          sleep_duration_minutes: summary.sleepDurationMinutes,
          sleep_quality_score: summary.sleepQualityScore,
          sleep_start_time: summary.sleepStartTime,
          sleep_end_time: summary.sleepEndTime,
          time_in_bed_minutes: summary.timeInBedMinutes,
          sleep_efficiency: sleepEfficiency,
          hrv_average_ms: summary.hrvAverageMs,
          hrv_min_ms: summary.hrvMinMs,
          hrv_max_ms: summary.hrvMaxMs,
          resting_heart_rate: summary.restingHeartRate,
          steps_count: summary.stepsCount,
          active_energy_kcal: summary.activeEnergyKcal,
          exercise_minutes: summary.exerciseMinutes,
          stand_hours: summary.standHours,
          distance_meters: summary.distanceMeters,
          mindful_minutes: summary.mindfulMinutes,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id,date" },
      );

      if (!error) summariesSynced++;
    }

    // Insert workouts
    let workoutsSynced = 0;
    for (const workout of payload.workouts || []) {
      const { error } = await supabase.from("biometric_workouts").upsert(
        {
          user_id: user.id,
          healthkit_uuid: workout.healthkitUuid,
          workout_type: workout.workoutType,
          start_time: workout.startTime,
          end_time: workout.endTime,
          duration_minutes: workout.durationMinutes,
          active_energy_kcal: workout.activeEnergyKcal,
          distance_meters: workout.distanceMeters,
          average_heart_rate: workout.averageHeartRate,
        },
        { onConflict: "user_id,healthkit_uuid" },
      );

      if (!error) workoutsSynced++;
    }

    // Update connection status
    await supabase.from("healthkit_connections").upsert(
      {
        user_id: user.id,
        is_connected: true,
        last_sync_at: new Date().toISOString(),
        last_sync_status: "success",
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );

    // Update baselines if we have enough data
    await updateBaselines(supabase, user.id);

    console.log(
      `Synced biometrics for user ${user.id}: ${summariesSynced} summaries, ${workoutsSynced} workouts`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        summariesSynced,
        workoutsSynced,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Sync biometrics error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function updateBaselines(supabase: any, userId: string) {
  // Get last 30 days of data
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data: summaries } = await supabase
    .from("biometric_daily_summaries")
    .select("*")
    .eq("user_id", userId)
    .gte("date", thirtyDaysAgo.toISOString().split("T")[0]);

  if (!summaries || summaries.length < 7) return; // Need at least 7 days

  // Calculate baselines for each metric
  const metrics = [
    { type: "sleep_duration", field: "sleep_duration_minutes" },
    { type: "hrv", field: "hrv_average_ms" },
    { type: "steps", field: "steps_count" },
    { type: "resting_hr", field: "resting_heart_rate" },
  ];

  for (const metric of metrics) {
    const values = summaries
      .map((s: any) => s[metric.field])
      .filter((v: any) => v != null);

    if (values.length < 7) continue;

    const mean =
      values.reduce((a: number, b: number) => a + b, 0) / values.length;
    const variance =
      values.reduce(
        (sum: number, v: number) => sum + Math.pow(v - mean, 2),
        0,
      ) / values.length;
    const stdDev = Math.sqrt(variance);

    await supabase.from("biometric_baselines").upsert(
      {
        user_id: userId,
        metric_type: metric.type,
        baseline_value: mean,
        baseline_std_dev: stdDev,
        baseline_min: Math.min(...values),
        baseline_max: Math.max(...values),
        computed_from_days: values.length,
        last_computed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,metric_type" },
    );
  }
}
