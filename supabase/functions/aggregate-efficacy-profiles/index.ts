// Intervention Efficacy Engine: Aggregate Efficacy Profiles Edge Function
// Nightly cron job to update user_efficacy_profiles from intervention_efficacy data

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    // Authenticate cron job (service role or cron secret)
    const authHeader = req.headers.get("Authorization");
    const cronSecret = Deno.env.get("CRON_SECRET");

    // Check if request is authenticated via service role key OR cron secret
    const isServiceRole = authHeader?.includes(
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
    );
    const isCronSecret = cronSecret && authHeader?.includes(cronSecret);

    if (!isServiceRole && !isCronSecret) {
      return new Response(
        JSON.stringify({
          error:
            "Unauthorized - cron job requires service role key or cron secret",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log("Starting efficacy profile aggregation...");

    // This is a cron job, use service role key
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Get all unique user-exercise pairs that need aggregation
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const { data: recentRecords, error: recordsError } = await supabaseAdmin
      .from("intervention_efficacy")
      .select("user_id, exercise_id")
      .gte("completed_at", sevenDaysAgo.toISOString());

    if (recordsError) {
      throw recordsError;
    }

    const uniquePairs = new Map<
      string,
      { userId: string; exerciseId: string }
    >();
    for (const record of recentRecords || []) {
      const key = `${record.user_id}:${record.exercise_id}`;
      uniquePairs.set(key, {
        userId: record.user_id,
        exerciseId: record.exercise_id,
      });
    }

    console.log(
      `Found ${uniquePairs.size} unique user-exercise pairs to aggregate`,
    );

    // Fetch all intervention efficacy records for these pairs in ONE query (fix N+1 pattern)
    const { data: allRecords, error: allRecordsError } = await supabaseAdmin
      .from("intervention_efficacy")
      .select("*")
      .in(
        "user_id",
        Array.from(
          new Set(Array.from(uniquePairs.values()).map((p) => p.userId)),
        ),
      )
      .in(
        "exercise_id",
        Array.from(
          new Set(Array.from(uniquePairs.values()).map((p) => p.exerciseId)),
        ),
      )
      .gte(
        "completed_at",
        new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
      )
      .order("completed_at", { ascending: false });

    if (allRecordsError) {
      throw allRecordsError;
    }

    // Group records by user-exercise pair
    const recordsByPair = new Map<string, typeof allRecords>();
    for (const record of allRecords || []) {
      const key = `${record.user_id}:${record.exercise_id}`;
      if (!recordsByPair.has(key)) {
        recordsByPair.set(key, []);
      }
      recordsByPair.get(key)!.push(record);
    }

    const aggregatedProfiles = [];

    // Process each unique pair
    for (const [key, { userId, exerciseId }] of uniquePairs) {
      const records = recordsByPair.get(key) || [];

      if (records.length === 0) {
        continue;
      }

      // Calculate overall efficacy (weighted by recency)
      const alpha = 0.3; // Exponential decay factor
      let weightedSum = 0;
      let weightSum = 0;

      records.forEach((record, index) => {
        const weight = Math.pow(1 - alpha, index);
        weightedSum += record.efficacy_score * weight;
        weightSum += weight;
      });

      const overallEfficacy = weightedSum / weightSum;

      // Calculate confidence: min(1.0, completionCount / 20)
      const confidence = Math.min(1.0, records.length / 20);

      // Group by context
      const byState: Record<string, number[]> = {};
      const byTime: Record<string, number[]> = {};
      const byEmotion: Record<string, number[]> = {};

      records.forEach((record) => {
        const state = record.starting_state?.nervousSystemState || "unknown";
        const time = record.time_of_day;
        const emotion = record.starting_state?.primaryEmotion || "neutral";

        if (!byState[state]) byState[state] = [];
        byState[state].push(record.efficacy_score);

        if (!byTime[time]) byTime[time] = [];
        byTime[time].push(record.efficacy_score);

        if (!byEmotion[emotion]) byEmotion[emotion] = [];
        byEmotion[emotion].push(record.efficacy_score);
      });

      // Calculate averages
      const efficacyByState: Record<string, number> = {};
      Object.entries(byState).forEach(([state, scores]) => {
        efficacyByState[state] =
          scores.reduce((a, b) => a + b, 0) / scores.length;
      });

      const efficacyByTime: Record<string, number> = {};
      Object.entries(byTime).forEach(([time, scores]) => {
        efficacyByTime[time] =
          scores.reduce((a, b) => a + b, 0) / scores.length;
      });

      const efficacyByEmotion: Record<string, number> = {};
      Object.entries(byEmotion).forEach(([emotion, scores]) => {
        efficacyByEmotion[emotion] =
          scores.reduce((a, b) => a + b, 0) / scores.length;
      });

      // Determine trend (linear regression over last 10 sessions)
      let trend = "stable";
      if (records.length >= 10) {
        const recentScores = records
          .slice(0, 10)
          .map((r) => r.efficacy_score)
          .reverse();
        const slope = linearRegressionSlope(recentScores);

        if (slope > 0.5) trend = "improving";
        else if (slope < -0.5) trend = "declining";
      }

      // Generate best context
      let bestContext = "";
      const bestState = Object.entries(efficacyByState).sort(
        (a, b) => b[1] - a[1],
      )[0];
      const bestTime = Object.entries(efficacyByTime).sort(
        (a, b) => b[1] - a[1],
      )[0];

      if (bestState && bestState[1] > overallEfficacy * 0.9) {
        bestContext = `Works best when in ${bestState[0]} state`;
      }

      if (bestTime && bestTime[1] > overallEfficacy * 0.9) {
        bestContext += bestContext
          ? `, in the ${bestTime[0]}`
          : `Works best in the ${bestTime[0]}`;
      }

      // Collect profile for batch upsert
      aggregatedProfiles.push({
        user_id: userId,
        exercise_id: exerciseId,
        overall_efficacy_score: Math.round(overallEfficacy * 100) / 100,
        completion_count: records.length,
        confidence: Math.round(confidence * 100) / 100,
        efficacy_by_state: efficacyByState,
        efficacy_by_time_of_day: efficacyByTime,
        efficacy_by_emotion: efficacyByEmotion,
        best_context: bestContext || null,
        trend,
        updated_at: new Date().toISOString(),
      });
    }

    // Batch upsert all profiles in a single database operation
    let errorCount = 0;
    if (aggregatedProfiles.length > 0) {
      const { error: batchError } = await supabaseAdmin
        .from("user_efficacy_profiles")
        .upsert(aggregatedProfiles, { onConflict: "user_id,exercise_id" });

      if (batchError) {
        console.error("Batch upsert error:", batchError);
        errorCount = aggregatedProfiles.length; // All failed
      }
    }

    return new Response(
      JSON.stringify({
        success: errorCount === 0,
        updatedCount: aggregatedProfiles.length - errorCount,
        errorCount,
        totalPairs: uniquePairs.size,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error in aggregate-efficacy-profiles:", error);
    return new Response(
      JSON.stringify({
        error: "AGGREGATION_FAILED",
        message: (error as Error).message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});

function linearRegressionSlope(scores: number[]): number {
  const n = scores.length;
  if (n < 2) return 0; // Cannot calculate slope with fewer than 2 points

  const sumX = (n * (n - 1)) / 2; // Sum of indices 0..n-1
  const sumY = scores.reduce((a, b) => a + b, 0);
  const sumXY = scores.reduce((sum, score, index) => sum + score * index, 0);
  const sumX2 = (n * (n - 1) * (2 * n - 1)) / 6; // Sum of squares of indices

  const denominator = n * sumX2 - sumX * sumX;
  if (denominator === 0) return 0; // Prevent division by zero

  const slope = (n * sumXY - sumX * sumY) / denominator;
  return slope;
}
