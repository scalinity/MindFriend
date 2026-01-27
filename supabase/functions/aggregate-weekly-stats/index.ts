/**
 * Aggregate Weekly Stats - Edge Function
 * Runs weekly (Sunday 02:00 UTC) to calculate weekly statistics for all users
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  calculatePopulationVariance,
  getWeekBounds,
  getPreviousWeekStart,
  countUniqueDays,
  calculateAverage,
  processBatches,
} from "../_shared/longitudinal-utils.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface AggregationResult {
  userId: string;
  success: boolean;
  error?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing environment variables");
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Calculate bounds for the previous complete week
    const now = new Date();
    const currentWeek = getWeekBounds(now);
    const previousWeekStart = getPreviousWeekStart(currentWeek.start);
    const previousWeek = getWeekBounds(previousWeekStart);

    console.log(
      `Aggregating week: ${previousWeek.start.toISOString()} to ${previousWeek.end.toISOString()}`,
    );

    // Get all users with mood data in the target week
    const { data: usersWithMoods, error: usersError } = await supabase
      .from("moods")
      .select("user_id")
      .gte("created_at", previousWeek.start.toISOString())
      .lt("created_at", previousWeek.end.toISOString());

    if (usersError) throw usersError;

    // Get unique user IDs
    const userIds = [...new Set(usersWithMoods?.map((m) => m.user_id) || [])];
    console.log(`Found ${userIds.length} users with mood data`);

    if (userIds.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users with mood data in target week",
          stats_created: 0,
          stats_updated: 0,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Process users in batches of 100
    const results = await processBatches<AggregationResult>(
      userIds,
      100,
      async (batch) => {
        const batchResults: AggregationResult[] = [];

        for (const userId of batch) {
          try {
            // Fetch moods for this user in target week
            const { data: moods, error: moodsError } = await supabase
              .from("moods")
              .select("mood_score, created_at")
              .eq("user_id", userId)
              .gte("created_at", previousWeek.start.toISOString())
              .lt("created_at", previousWeek.end.toISOString());

            if (moodsError) throw moodsError;

            // Skip if insufficient data (< 3 mood entries)
            if (!moods || moods.length < 3) {
              batchResults.push({ userId, success: true }); // Skip silently
              continue;
            }

            // Calculate avg_mood and mood_variance
            const moodScores = moods.map((m) => m.mood_score);
            const avgMood = calculateAverage(moodScores);
            const moodVariance = calculatePopulationVariance(moodScores);

            // Count active days
            const activeDays = countUniqueDays(moods.map((m) => m.created_at));

            // Fetch exercises completed in target week
            const { data: exercises, error: exercisesError } = await supabase
              .from("exercise_sessions")
              .select("id")
              .eq("user_id", userId)
              .gte("completed_at", previousWeek.start.toISOString())
              .lt("completed_at", previousWeek.end.toISOString());

            if (exercisesError) throw exercisesError;

            const exercisesCompleted = exercises?.length || 0;

            // Upsert weekly stats
            const { error: upsertError } = await supabase
              .from("longitudinal_weekly_stats")
              .upsert(
                {
                  user_id: userId,
                  week_start: previousWeek.start.toISOString(),
                  avg_mood: avgMood,
                  mood_variance: moodVariance,
                  active_days: activeDays,
                  exercises_completed: exercisesCompleted,
                  updated_at: new Date().toISOString(),
                },
                { onConflict: "user_id,week_start" },
              );

            if (upsertError) throw upsertError;

            batchResults.push({ userId, success: true });
          } catch (error) {
            console.error(`Error processing user ${userId}:`, error);
            batchResults.push({
              userId,
              success: false,
              error: error instanceof Error ? error.message : "Unknown error",
            });
          }
        }

        return batchResults;
      },
    );

    const successful = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success);

    console.log(
      `Aggregation complete: ${successful} successful, ${failed.length} failed`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        stats_created: successful,
        stats_updated: 0, // Upsert handles both
        errors: failed.map((f) => ({ userId: f.userId, error: f.error })),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Weekly aggregation error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
