/**
 * Aggregate Monthly Stats - Edge Function
 * Runs monthly (1st of month 03:00 UTC) to calculate monthly statistics
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  calculateMoodTrend,
  getMonthBounds,
  getPreviousMonthStart,
  getDaysInMonth,
  calculateAverage,
  countUniqueDays,
  processBatches,
} from "../_shared/longitudinal-utils.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface MonthlyResult {
  userId: string;
  success: boolean;
  error?: string;
}

serve(async (req) => {
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

    // Calculate bounds for the previous complete month
    const now = new Date();
    const currentMonth = getMonthBounds(now);
    const previousMonthStart = getPreviousMonthStart(currentMonth.start);
    const previousMonth = getMonthBounds(previousMonthStart);

    const targetYear = previousMonthStart.getUTCFullYear();
    const targetMonthNum = previousMonthStart.getUTCMonth();
    const daysInMonth = getDaysInMonth(targetYear, targetMonthNum);

    console.log(
      `Aggregating month: ${previousMonth.start.toISOString()} to ${previousMonth.end.toISOString()}`,
    );

    // Get all users with mood data in the target month
    const { data: usersWithMoods, error: usersError } = await supabase
      .from("moods")
      .select("user_id")
      .gte("created_at", previousMonth.start.toISOString())
      .lt("created_at", previousMonth.end.toISOString());

    if (usersError) throw usersError;

    const userIds = [...new Set(usersWithMoods?.map((m) => m.user_id) || [])];
    console.log(`Found ${userIds.length} users with mood data`);

    if (userIds.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users with mood data in target month",
          months_processed: 0,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const results = await processBatches<MonthlyResult>(
      userIds,
      100,
      async (batch) => {
        const batchResults: MonthlyResult[] = [];

        for (const userId of batch) {
          try {
            // Fetch moods for this user in target month
            const { data: moods, error: moodsError } = await supabase
              .from("moods")
              .select("mood_score, created_at")
              .eq("user_id", userId)
              .gte("created_at", previousMonth.start.toISOString())
              .lt("created_at", previousMonth.end.toISOString());

            if (moodsError) throw moodsError;

            // Skip if insufficient data
            if (!moods || moods.length < 5) {
              batchResults.push({ userId, success: true });
              continue;
            }

            // Calculate avg_mood
            const moodScores = moods.map((m) => m.mood_score);
            const avgMood = calculateAverage(moodScores);

            // Calculate active_days_pct
            const activeDays = countUniqueDays(moods.map((m) => m.created_at));
            const activeDaysPct =
              Math.round((activeDays / daysInMonth) * 10000) / 100;

            // Get prior month avg_mood for trend calculation
            const priorMonthStart = getPreviousMonthStart(previousMonthStart);
            const { data: priorStats } = await supabase
              .from("longitudinal_monthly_stats")
              .select("avg_mood")
              .eq("user_id", userId)
              .eq("month_start", priorMonthStart.toISOString())
              .single();

            const moodTrend = calculateMoodTrend(
              avgMood,
              priorStats?.avg_mood ?? null,
            );

            // Get notable events (life events with high impact)
            const { data: lifeEvents } = await supabase
              .from("longitudinal_life_events")
              .select("id, event_type, event_date")
              .eq("user_id", userId)
              .gte(
                "event_date",
                previousMonth.start.toISOString().split("T")[0],
              )
              .lt("event_date", previousMonth.end.toISOString().split("T")[0]);

            const notableEvents = (lifeEvents || []).map((e) => ({
              event_id: e.id,
              event_type: e.event_type,
              event_date: e.event_date,
            }));

            // Upsert monthly stats
            const { error: upsertError } = await supabase
              .from("longitudinal_monthly_stats")
              .upsert(
                {
                  user_id: userId,
                  month_start: previousMonth.start.toISOString(),
                  avg_mood: avgMood,
                  mood_trend: moodTrend,
                  active_days_pct: activeDaysPct,
                  notable_events: notableEvents,
                },
                { onConflict: "user_id,month_start" },
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
      `Monthly aggregation complete: ${successful} successful, ${failed.length} failed`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        months_processed: successful,
        errors: failed.map((f) => ({ userId: f.userId, error: f.error })),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Monthly aggregation error:", error);
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
