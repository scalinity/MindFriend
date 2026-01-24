// Intervention Efficacy Engine: Aggregate Efficacy Profiles Edge Function
// Nightly cron job to update user_efficacy_profiles from intervention_efficacy data

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    // This is a cron job, use service role key
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get all user-exercise pairs with >= 5 sessions
    const { data: pairs, error: pairsError } = await supabaseAdmin
      .from("intervention_efficacy")
      .select("user_id, exercise_id")
      .gte("created_at", new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString()); // Last 90 days

    if (pairsError) {
      throw new Error(\`Failed to fetch pairs: \${pairsError.message}\`);
    }

    // Group by user_id and exercise_id
    const uniquePairs = new Map<string, { userId: string; exerciseId: string }>();
    pairs?.forEach((pair) => {
      const key = \`\${pair.user_id}-\${pair.exercise_id}\`;
      uniquePairs.set(key, { userId: pair.user_id, exerciseId: pair.exercise_id });
    });

    let updatedCount = 0;
    let errorCount = 0;

    // Process each pair
    for (const { userId, exerciseId } of uniquePairs.values()) {
      try {
        // Fetch all efficacy records for this pair
        const { data: records, error: recordsError } = await supabaseAdmin
          .from("intervention_efficacy")
          .select("*")
          .eq("user_id", userId)
          .eq("exercise_id", exerciseId)
          .order("completed_at", { ascending: false });

        if (recordsError || !records || records.length < 5) {
          continue; // Skip if < 5 sessions
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
          efficacyByState[state] = scores.reduce((a, b) => a + b, 0) / scores.length;
        });

        const efficacyByTime: Record<string, number> = {};
        Object.entries(byTime).forEach(([time, scores]) => {
          efficacyByTime[time] = scores.reduce((a, b) => a + b, 0) / scores.length;
        });

        const efficacyByEmotion: Record<string, number> = {};
        Object.entries(byEmotion).forEach(([emotion, scores]) => {
          efficacyByEmotion[emotion] = scores.reduce((a, b) => a + b, 0) / scores.length;
        });

        // Determine trend (linear regression over last 10 sessions)
        let trend = "stable";
        if (records.length >= 10) {
          const recentScores = records.slice(0, 10).map((r) => r.efficacy_score).reverse();
          const slope = linearRegressionSlope(recentScores);

          if (slope > 0.5) trend = "improving";
          else if (slope < -0.5) trend = "declining";
        }

        // Generate best context
        let bestContext = "";
        const bestState = Object.entries(efficacyByState).sort((a, b) => b[1] - a[1])[0];
        const bestTime = Object.entries(efficacyByTime).sort((a, b) => b[1] - a[1])[0];

        if (bestState && bestState[1] > overallEfficacy * 0.9) {
          bestContext = \`Works best when in \${bestState[0]} state\`;
        }

        if (bestTime && bestTime[1] > overallEfficacy * 0.9) {
          bestContext += bestContext ? \`, in the \${bestTime[0]}\` : \`Works best in the \${bestTime[0]}\`;
        }

        // Upsert profile
        const { error: upsertError } = await supabaseAdmin
          .from("user_efficacy_profiles")
          .upsert(
            {
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
            },
            { onConflict: "user_id,exercise_id" }
          );

        if (upsertError) {
          console.error("Upsert error:", upsertError);
          errorCount++;
        } else {
          updatedCount++;
        }
      } catch (error) {
        console.error(\`Error processing pair \${userId}-\${exerciseId}:\`, error);
        errorCount++;
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        updatedCount,
        errorCount,
        totalPairs: uniquePairs.size,
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in aggregate-efficacy-profiles:", error);
    return new Response(
      JSON.stringify({
        error: "AGGREGATION_FAILED",
        message: error.message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});

function linearRegressionSlope(scores: number[]): number {
  const n = scores.length;
  const sumX = (n * (n - 1)) / 2; // Sum of indices 0..n-1
  const sumY = scores.reduce((a, b) => a + b, 0);
  const sumXY = scores.reduce((sum, score, index) => sum + score * index, 0);
  const sumX2 = (n * (n - 1) * (2 * n - 1)) / 6; // Sum of squares of indices

  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  return slope;
}
