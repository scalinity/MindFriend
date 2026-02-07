// supabase/functions/calculate-baseline/index.ts
// Edge Function: Calculate biometric baseline from HealthKit data

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface CalculateBaselineRequest {
  lookback_days?: number;
  force_recalculate?: boolean;
}

interface BiometricBaseline {
  user_id: string;
  resting_heart_rate: number | null;
  resting_hrv: number | null;
  exercise_recovery_rate: number | null;
  stress_hr_threshold: number | null;
  relaxed_hr_threshold: number | null;
  sample_count: number;
  confidence_score: number;
  calculated_at: string;
  updated_at: string;
}


serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
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

    // Parse request
    const body: CalculateBaselineRequest = await req.json().catch(() => ({}));
    const lookbackDays = Math.min(Math.max(body.lookback_days || 14, 7), 90);

    // Calculate lookback date
    const lookbackDate = new Date();
    lookbackDate.setDate(lookbackDate.getDate() - lookbackDays);

    // Fetch heart rate samples
    const { data: heartRateSamples, error: hrError } = await supabase
      .from("healthkit_heart_rate")
      .select("value, timestamp, context")
      .eq("user_id", user.id)
      .gte("timestamp", lookbackDate.toISOString())
      .order("timestamp", { ascending: true });

    if (hrError) {
      console.error("Error fetching heart rate samples:", hrError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch heart rate data" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch HRV samples
    const { data: hrvSamples, error: hrvError } = await supabase
      .from("healthkit_hrv")
      .select("value, timestamp, measurement_type")
      .eq("user_id", user.id)
      .gte("timestamp", lookbackDate.toISOString())
      .order("timestamp", { ascending: true });

    if (hrvError) {
      console.error("Error fetching HRV samples:", hrvError);
    }

    // Check minimum data requirements
    const sampleCount = heartRateSamples?.length || 0;
    if (sampleCount < 10) {
      return new Response(
        JSON.stringify({
          error: "Insufficient data for baseline calculation",
          required: 10,
          actual: sampleCount,
          message:
            "Please sync more HealthKit data to calculate an accurate baseline.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate resting heart rate (lowest 10th percentile during rest/sleep)
    const restingContextSamples = heartRateSamples
      .filter((s: any) => s.context === "resting" || s.context === "sleep")
      .map((s: any) => s.value)
      .sort((a: number, b: number) => a - b);

    const allHRValues = heartRateSamples
      .map((s: any) => s.value)
      .sort((a: number, b: number) => a - b);

    const restingHR =
      restingContextSamples.length >= 5
        ? percentile(restingContextSamples, 10)
        : percentile(allHRValues, 10);

    // Calculate stress threshold (85th percentile of active readings)
    const activeHRSamples = heartRateSamples
      .filter((s: any) => s.context !== "sleep")
      .map((s: any) => s.value)
      .sort((a: number, b: number) => a - b);

    const stressThreshold =
      activeHRSamples.length >= 5
        ? percentile(activeHRSamples, 85)
        : percentile(allHRValues, 85);

    // Calculate relaxed threshold (resting + 30% of range to stress)
    const relaxedThreshold = restingHR + (stressThreshold - restingHR) * 0.3;

    // Calculate resting HRV (median of SDNN readings)
    const hrvValues = (hrvSamples || [])
      .filter((s: any) => s.measurement_type === "sdnn" || !s.measurement_type)
      .map((s: any) => s.value)
      .sort((a: number, b: number) => a - b);

    const restingHRV = hrvValues.length > 0 ? median(hrvValues) : null;

    // Calculate recovery rate from biofeedback sessions
    let recoveryRate: number | null = null;
    const { data: sessions } = await supabase
      .from("biofeedback_sessions")
      .select(
        `
        id,
        biofeedback_readings (
          heart_rate,
          timestamp
        )
      `,
      )
      .eq("user_id", user.id)
      .not("completed_at", "is", null)
      .gte("created_at", lookbackDate.toISOString())
      .order("created_at", { ascending: false })
      .limit(10);

    if (sessions && sessions.length >= 3) {
      const recoveryRates = sessions
        .filter(
          (s: any) =>
            s.biofeedback_readings && s.biofeedback_readings.length >= 5,
        )
        .map((session: any) =>
          calculateRecoveryRate(session.biofeedback_readings),
        )
        .filter((rate: number) => rate > 0);

      if (recoveryRates.length > 0) {
        recoveryRate = median(recoveryRates.sort((a, b) => a - b));
      }
    }

    // Calculate confidence score
    // Higher score with: more samples, HRV data available, recent data
    let confidence = Math.min(1.0, sampleCount / 100);
    if (hrvValues.length > 0) confidence *= 1.2;
    if (restingContextSamples.length >= 10) confidence *= 1.1;
    confidence = Math.min(1.0, Math.round(confidence * 100) / 100);

    // Prepare baseline object
    const baseline: BiometricBaseline = {
      user_id: user.id,
      resting_heart_rate: Math.round(restingHR * 100) / 100,
      resting_hrv: restingHRV ? Math.round(restingHRV * 100) / 100 : null,
      exercise_recovery_rate: recoveryRate
        ? Math.round(recoveryRate * 100) / 100
        : null,
      stress_hr_threshold: Math.round(stressThreshold * 100) / 100,
      relaxed_hr_threshold: Math.round(relaxedThreshold * 100) / 100,
      sample_count: sampleCount,
      confidence_score: confidence,
      calculated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    // Upsert baseline
    const { error: upsertError } = await supabase
      .from("biometric_baselines")
      .upsert(baseline, { onConflict: "user_id" });

    if (upsertError) {
      console.error("Error upserting baseline:", upsertError);
      return new Response(
        JSON.stringify({ error: "Failed to save baseline" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        baseline: {
          resting_heart_rate: baseline.resting_heart_rate,
          resting_hrv: baseline.resting_hrv,
          exercise_recovery_rate: baseline.exercise_recovery_rate,
          stress_hr_threshold: baseline.stress_hr_threshold,
          relaxed_hr_threshold: baseline.relaxed_hr_threshold,
          confidence_score: baseline.confidence_score,
          sample_count: baseline.sample_count,
        },
        meta: {
          lookback_days: lookbackDays,
          heart_rate_samples: sampleCount,
          hrv_samples: hrvValues.length,
          resting_context_samples: restingContextSamples.length,
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Helper: Calculate percentile of sorted array
function percentile(sortedArr: number[], p: number): number {
  if (sortedArr.length === 0) return 0;
  if (sortedArr.length === 1) return sortedArr[0];

  const index = (p / 100) * (sortedArr.length - 1);
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  const weight = index - lower;

  if (upper >= sortedArr.length) return sortedArr[sortedArr.length - 1];
  return sortedArr[lower] * (1 - weight) + sortedArr[upper] * weight;
}

// Helper: Calculate median of sorted array
function median(sortedArr: number[]): number {
  if (sortedArr.length === 0) return 0;
  const mid = Math.floor(sortedArr.length / 2);
  return sortedArr.length % 2 === 0
    ? (sortedArr[mid - 1] + sortedArr[mid]) / 2
    : sortedArr[mid];
}

// Helper: Calculate recovery rate from session readings
function calculateRecoveryRate(
  readings: Array<{ heart_rate: number; timestamp: string }>,
): number {
  if (!readings || readings.length < 3) return 0;

  const sorted = [...readings].sort(
    (a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime(),
  );

  // Find peak heart rate
  let peakIndex = 0;
  let peakHR = 0;
  sorted.forEach((r, i) => {
    if (r.heart_rate > peakHR) {
      peakHR = r.heart_rate;
      peakIndex = i;
    }
  });

  // Calculate recovery from peak to end
  const recoveryReadings = sorted.slice(peakIndex);
  if (recoveryReadings.length < 3) return 0;

  const first = recoveryReadings[0];
  const last = recoveryReadings[recoveryReadings.length - 1];
  const hrDrop = first.heart_rate - last.heart_rate;
  const minutesDuration =
    (new Date(last.timestamp).getTime() - new Date(first.timestamp).getTime()) /
    60000;

  return minutesDuration > 0 ? hrDrop / minutesDuration : 0;
}
