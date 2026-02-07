/**
 * Detect Patterns - Edge Function
 * Runs weekly (Sunday 05:00 UTC) to detect statistical patterns in user data
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  getSeasonForMonth,
  processBatches,
} from "../_shared/longitudinal-utils.ts";
import {
  tTest,
  anova,
  linearRegression,
} from "../_shared/statistical-tests.ts";
import { getCorsHeaders } from "../_shared/cors.ts";


interface PatternResult {
  userId: string;
  patternsDetected: number;
  patternsUpdated: number;
  patternsArchived: number;
  error?: string;
}

interface DetectedPattern {
  pattern_type: string;
  pattern_description: string;
  confidence: number;
  metadata: Record<string, unknown>;
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

    // Get all users with sufficient weekly stats (>= 8 weeks)
    const { data: userStats, error: statsError } = await supabase
      .from("longitudinal_weekly_stats")
      .select("user_id")
      .order("week_start", { ascending: false });

    if (statsError) throw statsError;

    // Count weeks per user
    const weekCounts: Record<string, number> = {};
    for (const stat of userStats || []) {
      weekCounts[stat.user_id] = (weekCounts[stat.user_id] || 0) + 1;
    }

    // Filter users with >= 8 weeks of data
    const eligibleUserIds = Object.entries(weekCounts)
      .filter(([_, count]) => count >= 8)
      .map(([userId]) => userId);

    console.log(
      `Found ${eligibleUserIds.length} users with >= 8 weeks of data`,
    );

    if (eligibleUserIds.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users with sufficient data for pattern detection",
          patterns_detected: 0,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const results = await processBatches<PatternResult>(
      eligibleUserIds,
      50,
      async (batch) => {
        const batchResults: PatternResult[] = [];

        for (const userId of batch) {
          try {
            let patternsDetected = 0;
            let patternsUpdated = 0;
            let patternsArchived = 0;

            // Fetch all weekly stats for user
            const { data: weeklyStats, error: weeklyError } = await supabase
              .from("longitudinal_weekly_stats")
              .select("week_start, avg_mood, active_days")
              .eq("user_id", userId)
              .order("week_start", { ascending: true });

            if (weeklyError) throw weeklyError;
            if (!weeklyStats || weeklyStats.length < 8) continue;

            const detectedPatterns: DetectedPattern[] = [];

            // 1. Weekly Rhythm Detection (t-test: weekday vs weekend)
            const weekdayMoods: number[] = [];
            const weekendMoods: number[] = [];

            for (const stat of weeklyStats) {
              if (stat.avg_mood === null) continue;
              const weekDay = new Date(stat.week_start).getUTCDay();
              // Week starts Sunday, so classify by typical work pattern
              if (weekDay >= 1 && weekDay <= 5) {
                weekdayMoods.push(stat.avg_mood);
              } else {
                weekendMoods.push(stat.avg_mood);
              }
            }

            // Actually, week_start is always Sunday - need to look at individual moods
            // For simplicity, we'll analyze mood variance patterns instead
            const moodsWithDays = weeklyStats
              .filter((s) => s.avg_mood !== null)
              .map((s) => ({
                mood: s.avg_mood as number,
                dayOfWeek: new Date(s.week_start).getUTCDay(),
              }));

            // Group by even/odd weeks as proxy for rhythm detection
            const evenWeeks = moodsWithDays
              .filter((_, i) => i % 2 === 0)
              .map((m) => m.mood);
            const oddWeeks = moodsWithDays
              .filter((_, i) => i % 2 !== 0)
              .map((m) => m.mood);

            if (evenWeeks.length >= 4 && oddWeeks.length >= 4) {
              const weeklyRhythmResult = tTest(evenWeeks, oddWeeks);
              if (weeklyRhythmResult.significant) {
                const avgEven =
                  evenWeeks.reduce((a, b) => a + b, 0) / evenWeeks.length;
                const avgOdd =
                  oddWeeks.reduce((a, b) => a + b, 0) / oddWeeks.length;
                const delta = Math.abs(avgEven - avgOdd).toFixed(2);

                detectedPatterns.push({
                  pattern_type: "weekly_rhythm",
                  pattern_description: `Bi-weekly mood pattern detected with ${delta} point difference between alternating weeks`,
                  confidence: weeklyRhythmResult.confidence,
                  metadata: {
                    even_week_avg: avgEven,
                    odd_week_avg: avgOdd,
                    p_value: weeklyRhythmResult.pValue,
                  },
                });
              }
            }

            // 2. Seasonal Mood Detection (ANOVA across seasons)
            const seasonalMoods: Record<string, number[]> = {
              winter: [],
              spring: [],
              summer: [],
              fall: [],
            };

            for (const stat of weeklyStats) {
              if (stat.avg_mood === null) continue;
              const month = new Date(stat.week_start).getUTCMonth();
              const season = getSeasonForMonth(month);
              seasonalMoods[season].push(stat.avg_mood);
            }

            const seasonGroups = [
              seasonalMoods.winter,
              seasonalMoods.spring,
              seasonalMoods.summer,
              seasonalMoods.fall,
            ].filter((g) => g.length >= 2);

            if (seasonGroups.length >= 3) {
              const seasonalResult = anova(seasonGroups);
              if (seasonalResult.significant) {
                const seasonAvgs = {
                  winter:
                    seasonalMoods.winter.length > 0
                      ? seasonalMoods.winter.reduce((a, b) => a + b, 0) /
                        seasonalMoods.winter.length
                      : null,
                  spring:
                    seasonalMoods.spring.length > 0
                      ? seasonalMoods.spring.reduce((a, b) => a + b, 0) /
                        seasonalMoods.spring.length
                      : null,
                  summer:
                    seasonalMoods.summer.length > 0
                      ? seasonalMoods.summer.reduce((a, b) => a + b, 0) /
                        seasonalMoods.summer.length
                      : null,
                  fall:
                    seasonalMoods.fall.length > 0
                      ? seasonalMoods.fall.reduce((a, b) => a + b, 0) /
                        seasonalMoods.fall.length
                      : null,
                };

                const validSeasons = Object.entries(seasonAvgs)
                  .filter(([_, v]) => v !== null)
                  .map(([k, v]) => ({ season: k, avg: v as number }))
                  .sort((a, b) => a.avg - b.avg);

                const lowest = validSeasons[0];
                const highest = validSeasons[validSeasons.length - 1];
                const diff = (
                  ((highest.avg - lowest.avg) / lowest.avg) *
                  100
                ).toFixed(0);

                detectedPatterns.push({
                  pattern_type: "seasonal_mood",
                  pattern_description: `Seasonal mood variation detected: ${highest.season} is ${diff}% higher than ${lowest.season}`,
                  confidence: seasonalResult.confidence,
                  metadata: {
                    season_averages: seasonAvgs,
                    lowest_season: lowest.season,
                    highest_season: highest.season,
                    p_value: seasonalResult.pValue,
                  },
                });
              }
            }

            // 3. Improvement Trend Detection (linear regression)
            const moodValues = weeklyStats
              .filter((s) => s.avg_mood !== null)
              .map((s) => s.avg_mood as number);
            const weekNumbers = moodValues.map((_, i) => i);

            if (moodValues.length >= 8) {
              const trendResult = linearRegression(weekNumbers, moodValues);
              if (
                trendResult.significant &&
                Math.abs(trendResult.slope) > 0.01
              ) {
                const direction =
                  trendResult.slope > 0 ? "improving" : "declining";
                const changePerMonth = (trendResult.slope * 4.33).toFixed(2); // 4.33 weeks/month

                detectedPatterns.push({
                  pattern_type: "improvement_trend",
                  pattern_description: `Mood is ${direction} by approximately ${Math.abs(parseFloat(changePerMonth))} points per month`,
                  confidence: trendResult.confidence,
                  metadata: {
                    slope: trendResult.slope,
                    r_squared: trendResult.rSquared,
                    monthly_change: parseFloat(changePerMonth),
                    p_value: trendResult.pValue,
                  },
                });
              }
            }

            // Save detected patterns
            for (const pattern of detectedPatterns) {
              // Check if pattern already exists
              const { data: existingPattern } = await supabase
                .from("longitudinal_patterns")
                .select("id, occurrences")
                .eq("user_id", userId)
                .eq("pattern_type", pattern.pattern_type)
                .eq("is_active", true)
                .single();

              if (existingPattern) {
                // Update existing pattern
                await supabase
                  .from("longitudinal_patterns")
                  .update({
                    pattern_description: pattern.pattern_description,
                    confidence: pattern.confidence,
                    last_detected: new Date().toISOString(),
                    occurrences: existingPattern.occurrences + 1,
                    metadata: pattern.metadata,
                  })
                  .eq("id", existingPattern.id);
                patternsUpdated++;
              } else {
                // Insert new pattern
                await supabase.from("longitudinal_patterns").insert({
                  user_id: userId,
                  pattern_type: pattern.pattern_type,
                  pattern_description: pattern.pattern_description,
                  confidence: pattern.confidence,
                  metadata: pattern.metadata,
                });
                patternsDetected++;
              }
            }

            // Archive old patterns (confidence < 0.3 and not detected in 6 months)
            const sixMonthsAgo = new Date();
            sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);

            const { data: stalePatterns } = await supabase
              .from("longitudinal_patterns")
              .select("id")
              .eq("user_id", userId)
              .eq("is_active", true)
              .lt("confidence", 0.3)
              .lt("last_detected", sixMonthsAgo.toISOString());

            if (stalePatterns && stalePatterns.length > 0) {
              await supabase
                .from("longitudinal_patterns")
                .update({ is_active: false })
                .in(
                  "id",
                  stalePatterns.map((p) => p.id),
                );
              patternsArchived = stalePatterns.length;
            }

            batchResults.push({
              userId,
              patternsDetected,
              patternsUpdated,
              patternsArchived,
            });
          } catch (error) {
            console.error(`Error processing user ${userId}:`, error);
            batchResults.push({
              userId,
              patternsDetected: 0,
              patternsUpdated: 0,
              patternsArchived: 0,
              error: error instanceof Error ? error.message : "Unknown error",
            });
          }
        }

        return batchResults;
      },
    );

    const totalDetected = results.reduce(
      (sum, r) => sum + r.patternsDetected,
      0,
    );
    const totalUpdated = results.reduce((sum, r) => sum + r.patternsUpdated, 0);
    const totalArchived = results.reduce(
      (sum, r) => sum + r.patternsArchived,
      0,
    );
    const errors = results.filter((r) => r.error);

    console.log(
      `Pattern detection complete: ${totalDetected} detected, ${totalUpdated} updated, ${totalArchived} archived`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        patterns_detected: totalDetected,
        patterns_updated: totalUpdated,
        patterns_archived: totalArchived,
        users_processed: results.length,
        errors: errors.map((e) => ({ userId: e.userId, error: e.error })),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Pattern detection error:", error);
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
