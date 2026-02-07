/**
 * Aggregate Yearly Stats - Edge Function
 * Runs yearly (January 1 04:00 UTC) to calculate yearly statistics with seasonal patterns
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  getSeasonForMonth,
  getQuarterForMonth,
  calculateAverage,
  processBatches,
} from "../_shared/longitudinal-utils.ts";
import { getCorsHeaders } from "../_shared/cors.ts";


interface YearlyResult {
  userId: string;
  success: boolean;
  error?: string;
}

interface SeasonalPatterns {
  winter: number | null;
  spring: number | null;
  summer: number | null;
  fall: number | null;
  lowest_season: string | null;
  highest_season: string | null;
}

interface YearlyComparison {
  mood_delta: number | null;
  active_days_delta: number | null;
  exercises_delta: number | null;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

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

    // Calculate target year (previous complete year)
    const now = new Date();
    const targetYear = now.getUTCFullYear() - 1;

    console.log(`Aggregating year: ${targetYear}`);

    // Get all users with monthly stats in the target year
    const yearStart = new Date(Date.UTC(targetYear, 0, 1));
    const yearEnd = new Date(Date.UTC(targetYear + 1, 0, 1));

    const { data: usersWithStats, error: usersError } = await supabase
      .from("longitudinal_monthly_stats")
      .select("user_id")
      .gte("month_start", yearStart.toISOString())
      .lt("month_start", yearEnd.toISOString());

    if (usersError) throw usersError;

    const userIds = [...new Set(usersWithStats?.map((s) => s.user_id) || [])];
    console.log(`Found ${userIds.length} users with monthly stats`);

    if (userIds.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users with monthly stats in target year",
          years_processed: 0,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const results = await processBatches<YearlyResult>(
      userIds,
      50,
      async (batch) => {
        const batchResults: YearlyResult[] = [];

        for (const userId of batch) {
          try {
            // Fetch all monthly stats for this user in target year
            const { data: monthlyStats, error: statsError } = await supabase
              .from("longitudinal_monthly_stats")
              .select("month_start, avg_mood, active_days_pct")
              .eq("user_id", userId)
              .gte("month_start", yearStart.toISOString())
              .lt("month_start", yearEnd.toISOString())
              .order("month_start", { ascending: true });

            if (statsError) throw statsError;

            // Skip if insufficient data (< 6 months)
            if (!monthlyStats || monthlyStats.length < 6) {
              batchResults.push({ userId, success: true });
              continue;
            }

            // Calculate quarterly moods
            const quarterlyMoods: (number | null)[] = [null, null, null, null];
            const quarterData: number[][] = [[], [], [], []];

            for (const stat of monthlyStats) {
              if (stat.avg_mood === null) continue;
              const month = new Date(stat.month_start).getUTCMonth();
              const quarter = getQuarterForMonth(month);
              quarterData[quarter].push(stat.avg_mood);
            }

            for (let q = 0; q < 4; q++) {
              quarterlyMoods[q] = calculateAverage(quarterData[q]);
            }

            // Calculate seasonal patterns
            const seasonData: Record<string, number[]> = {
              winter: [],
              spring: [],
              summer: [],
              fall: [],
            };

            for (const stat of monthlyStats) {
              if (stat.avg_mood === null) continue;
              const month = new Date(stat.month_start).getUTCMonth();
              const season = getSeasonForMonth(month);
              seasonData[season].push(stat.avg_mood);
            }

            const seasonalPatterns: SeasonalPatterns = {
              winter: calculateAverage(seasonData.winter),
              spring: calculateAverage(seasonData.spring),
              summer: calculateAverage(seasonData.summer),
              fall: calculateAverage(seasonData.fall),
              lowest_season: null,
              highest_season: null,
            };

            // Find lowest and highest seasons
            const validSeasons = Object.entries(seasonalPatterns)
              .filter(
                ([key, val]) =>
                  !["lowest_season", "highest_season"].includes(key) &&
                  val !== null,
              )
              .map(([key, val]) => ({ season: key, avg: val as number }));

            if (validSeasons.length >= 2) {
              validSeasons.sort((a, b) => a.avg - b.avg);
              seasonalPatterns.lowest_season = validSeasons[0].season;
              seasonalPatterns.highest_season =
                validSeasons[validSeasons.length - 1].season;
            }

            // Get prior year stats for comparison
            const { data: priorYear } = await supabase
              .from("longitudinal_yearly_stats")
              .select("quarterly_moods, seasonal_patterns")
              .eq("user_id", userId)
              .eq("year", targetYear - 1)
              .single();

            let yearlyComparison: YearlyComparison | null = null;
            if (priorYear) {
              const currentYearAvg = calculateAverage(
                quarterlyMoods.filter((q): q is number => q !== null),
              );
              const priorYearMoods = priorYear.quarterly_moods as
                | number[]
                | null;
              const priorYearAvg = priorYearMoods
                ? calculateAverage(
                    priorYearMoods.filter((q): q is number => q !== null),
                  )
                : null;

              if (currentYearAvg !== null && priorYearAvg !== null) {
                yearlyComparison = {
                  mood_delta:
                    Math.round((currentYearAvg - priorYearAvg) * 100) / 100,
                  active_days_delta: null, // Could calculate if needed
                  exercises_delta: null,
                };
              }
            }

            // Fetch milestones (badges earned in year)
            const { data: badges } = await supabase
              .from("user_badges")
              .select("badge_id, earned_at")
              .eq("user_id", userId)
              .gte("earned_at", yearStart.toISOString())
              .lt("earned_at", yearEnd.toISOString());

            const milestones = (badges || []).map((b) => ({
              type: "badge",
              name: b.badge_id,
              achieved_date: b.earned_at,
            }));

            // Determine if year is partial
            const isPartial = monthlyStats.length < 12;

            // Upsert yearly stats
            const { error: upsertError } = await supabase
              .from("longitudinal_yearly_stats")
              .upsert(
                {
                  user_id: userId,
                  year: targetYear,
                  quarterly_moods: quarterlyMoods,
                  seasonal_patterns: seasonalPatterns,
                  yearly_comparison: yearlyComparison,
                  milestones_achieved: milestones,
                  is_partial: isPartial,
                },
                { onConflict: "user_id,year" },
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
      `Yearly aggregation complete: ${successful} successful, ${failed.length} failed`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        years_processed: successful,
        target_year: targetYear,
        errors: failed.map((f) => ({ userId: f.userId, error: f.error })),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Yearly aggregation error:", error);
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
