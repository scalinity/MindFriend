import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  calculateAverageBedtime,
  calculateAverageDuration,
  calculateAverageScore,
  calculateAverageWakeTime,
  calculateConsistency,
  detectWeekendShift,
} from "../_shared/sleep-utils.ts";

interface SleepAnalysisResponse {
  weeklyStats: {
    avgDuration: number;
    avgScore: number;
    avgBedtime: string;
    avgWakeTime: string;
    consistency: number;
    totalNights: number;
  };
  sleepDebt: {
    currentMinutes: number;
    trend: string;
  } | null;
  moodCorrelation: {
    coefficient: number;
    insight: string;
  } | null;
  patterns: Array<{
    type: string;
    description: string;
    impact: string;
    recommendation: string;
  }>;
  recommendations: string[];
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
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

    // Fetch last 14 days of sleep data (for better pattern detection)
    const fourteenDaysAgo = new Date();
    fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);

    const { data: entries, error: entriesError } = await supabase
      .from("sleep_entries")
      .select("*")
      .eq("user_id", user.id)
      .gte("date", fourteenDaysAgo.toISOString().split("T")[0])
      .order("date", { ascending: false });

    if (entriesError) {
      throw entriesError;
    }

    // Check if we have enough data (at least 7 days)
    if (!entries || entries.length < 7) {
      return new Response(
        JSON.stringify({
          error: "INSUFFICIENT_DATA",
          message: "Need at least 7 days of sleep data",
          currentDays: entries?.length || 0,
          requiredDays: 7,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate weekly stats (last 7 days)
    const lastSevenDays = entries.slice(0, 7);

    const weeklyStats = {
      avgDuration: calculateAverageDuration(lastSevenDays),
      avgScore: calculateAverageScore(lastSevenDays),
      avgBedtime: calculateAverageBedtime(lastSevenDays),
      avgWakeTime: calculateAverageWakeTime(lastSevenDays),
      consistency: calculateConsistency(lastSevenDays),
      totalNights: lastSevenDays.length,
    };

    // Fetch sleep debt
    const { data: sleepDebtData } = await supabase
      .from("sleep_debt")
      .select("*")
      .eq("user_id", user.id)
      .single();

    const sleepDebt = sleepDebtData
      ? {
          currentMinutes: sleepDebtData.current_debt_minutes,
          trend: calculateDebtTrend(entries),
        }
      : null;

    // Fetch mood data for correlation analysis
    const { data: moods } = await supabase
      .from("moods")
      .select("*")
      .eq("user_id", user.id)
      .gte("created_at", fourteenDaysAgo.toISOString())
      .order("created_at", { ascending: false });

    const moodCorrelation = calculateMoodCorrelation(entries, moods || []);

    // Detect patterns
    const patterns = detectPatterns(entries);

    // Generate recommendations
    const recommendations = generateRecommendations(
      weeklyStats,
      sleepDebt,
      patterns,
    );

    // Cache the insight
    await cacheInsight(supabase, user.id, {
      weeklyStats,
      sleepDebt,
      moodCorrelation,
      patterns,
      recommendations,
    });

    const response: SleepAnalysisResponse = {
      weeklyStats,
      sleepDebt,
      moodCorrelation,
      patterns,
      recommendations,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error analyzing sleep patterns:", error);

    return new Response(
      JSON.stringify({
        error: "Failed to analyze sleep patterns",
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Calculate sleep debt trend (increasing, decreasing, stable)
 */
function calculateDebtTrend(entries: any[]): string {
  if (entries.length < 7) return "stable";

  const recentEntries = entries.slice(0, 3);
  const olderEntries = entries.slice(3, 6);

  const recentAvg = calculateAverageDuration(recentEntries);
  const olderAvg = calculateAverageDuration(olderEntries);

  const diff = recentAvg - olderAvg;

  if (diff > 15) return "decreasing"; // Sleeping more recently
  if (diff < -15) return "increasing"; // Sleeping less recently
  return "stable";
}

/**
 * Calculate correlation between sleep quality and next-day mood
 */
function calculateMoodCorrelation(
  sleepEntries: any[],
  moods: any[],
): { coefficient: number; insight: string } | null {
  if (sleepEntries.length < 7 || moods.length < 7) return null;

  // Create pairs of (sleep score, next-day mood)
  const pairs: Array<[number, number]> = [];

  for (const entry of sleepEntries) {
    if (!entry.sleep_score) continue;

    const entryDate = new Date(entry.date);
    const nextDay = new Date(entryDate);
    nextDay.setDate(nextDay.getDate() + 1);

    // Find moods on the next day
    const nextDayMoods = moods.filter((mood) => {
      const moodDate = new Date(mood.created_at);
      return moodDate.toDateString() === nextDay.toDateString();
    });

    if (nextDayMoods.length > 0) {
      // Average mood score for that day
      const avgMood =
        nextDayMoods.reduce((sum, m) => sum + m.score, 0) / nextDayMoods.length;
      pairs.push([entry.sleep_score, avgMood]);
    }
  }

  if (pairs.length < 5) return null; // Need at least 5 pairs

  // Calculate Pearson correlation coefficient
  const n = pairs.length;
  const sumX = pairs.reduce((sum, [x]) => sum + x, 0);
  const sumY = pairs.reduce((sum, [, y]) => sum + y, 0);
  const sumXY = pairs.reduce((sum, [x, y]) => sum + x * y, 0);
  const sumX2 = pairs.reduce((sum, [x]) => sum + x * x, 0);
  const sumY2 = pairs.reduce((sum, [, y]) => sum + y * y, 0);

  const numerator = n * sumXY - sumX * sumY;
  const denominator = Math.sqrt(
    (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY),
  );

  if (denominator === 0) return null;

  const coefficient = numerator / denominator;

  // Generate insight
  let insight: string;
  if (coefficient > 0.6) {
    insight = "Better sleep strongly correlates with improved mood next day";
  } else if (coefficient > 0.3) {
    insight = "Better sleep moderately correlates with improved mood next day";
  } else if (coefficient < -0.3) {
    insight = "Poor sleep is associated with lower mood next day";
  } else {
    insight =
      "Sleep and mood show weak correlation - other factors may be more influential";
  }

  return {
    coefficient: Math.round(coefficient * 100) / 100,
    insight,
  };
}

/**
 * Detect sleep patterns
 */
function detectPatterns(entries: any[]): Array<{
  type: string;
  description: string;
  impact: string;
  recommendation: string;
}> {
  const patterns = [];

  // Weekend sleep shift
  const weekendShift = detectWeekendShift(entries);
  if (weekendShift.hasShift && weekendShift.shiftHours > 1) {
    patterns.push({
      type: "weekend_shift",
      description: weekendShift.description,
      impact: "negative",
      recommendation:
        "Try keeping weekend bedtime within 30 minutes of weekday schedule",
    });
  }

  // Low consistency
  const consistency = calculateConsistency(entries);
  if (consistency < 0.6) {
    patterns.push({
      type: "inconsistent_schedule",
      description: "Your bedtime varies significantly night to night",
      impact: "negative",
      recommendation:
        "Try going to bed at the same time each night to improve sleep quality",
    });
  }

  // Improving trend
  const recentEntries = entries.slice(0, 7);
  const olderEntries = entries.slice(7, 14);
  if (olderEntries.length >= 7) {
    const recentAvgScore = calculateAverageScore(recentEntries);
    const olderAvgScore = calculateAverageScore(olderEntries);

    if (recentAvgScore - olderAvgScore > 10) {
      patterns.push({
        type: "improving_trend",
        description: `Sleep quality improved ${recentAvgScore - olderAvgScore} points this week`,
        impact: "positive",
        recommendation:
          "Keep up the great work - your sleep routine is working!",
      });
    } else if (olderAvgScore - recentAvgScore > 10) {
      patterns.push({
        type: "declining_trend",
        description: `Sleep quality declined ${olderAvgScore - recentAvgScore} points this week`,
        impact: "negative",
        recommendation:
          "Review what changed in your routine and try to get back on track",
      });
    }
  }

  // Low deep sleep (if data available)
  const entriesWithStages = entries.filter(
    (e) => e.deep_sleep_minutes !== null,
  );
  if (entriesWithStages.length >= 5) {
    const avgDeepSleep =
      entriesWithStages.reduce(
        (sum, e) => sum + (e.deep_sleep_minutes || 0),
        0,
      ) / entriesWithStages.length;
    const avgTotal =
      entriesWithStages.reduce(
        (sum, e) => sum + (e.time_asleep_minutes || 0),
        0,
      ) / entriesWithStages.length;
    const deepPercent = (avgDeepSleep / avgTotal) * 100;

    if (deepPercent < 15) {
      patterns.push({
        type: "low_deep_sleep",
        description: `Deep sleep is ${Math.round(deepPercent)}% (optimal: 15-25%)`,
        impact: "negative",
        recommendation:
          "Try the Deep Sleep meditation or avoid caffeine after 2 PM",
      });
    }
  }

  return patterns;
}

/**
 * Generate personalized recommendations
 */
function generateRecommendations(
  weeklyStats: any,
  sleepDebt: any,
  patterns: any[],
): string[] {
  const recommendations = [];

  // Sleep debt recommendations
  if (sleepDebt && sleepDebt.currentMinutes > 120) {
    const hours = Math.round(sleepDebt.currentMinutes / 60);
    recommendations.push(
      `You have ${hours}h sleep debt - try sleeping 30 min earlier for the next ${Math.ceil(hours * 2)} nights`,
    );
  }

  // Low score recommendations
  if (weeklyStats.avgScore < 70) {
    recommendations.push(
      "Your sleep score is below optimal - focus on consistency and wind-down routine",
    );
  }

  // Pattern-specific recommendations
  for (const pattern of patterns) {
    if (pattern.impact === "negative") {
      recommendations.push(pattern.recommendation);
    }
  }

  // Consistency recommendations
  if (weeklyStats.consistency < 0.7) {
    recommendations.push(
      "Improve sleep consistency by setting a regular bedtime and wake time",
    );
  }

  // If no issues, provide positive reinforcement
  if (recommendations.length === 0) {
    if (weeklyStats.avgScore >= 80) {
      recommendations.push(
        "Excellent sleep quality - keep up the great routine!",
      );
    } else {
      recommendations.push(
        "Your sleep is on track - maintain your current habits",
      );
    }
  }

  return recommendations;
}

/**
 * Cache the generated insight in the database
 */
async function cacheInsight(supabase: any, userId: string, analysisData: any) {
  const validUntil = new Date();
  validUntil.setDate(validUntil.getDate() + 7); // Valid for 7 days

  const insight = {
    user_id: userId,
    insight_type: "weekly_report",
    insight_data: {
      title: "Weekly Sleep Report",
      message: `Average sleep score: ${analysisData.weeklyStats.avgScore}/100`,
      metric: "sleep_score",
      value: analysisData.weeklyStats.avgScore,
      trend: analysisData.sleepDebt?.trend || "stable",
      recommendation:
        analysisData.recommendations[0] || "Keep up the good work!",
    },
    generated_at: new Date().toISOString(),
    valid_until: validUntil.toISOString(),
    viewed: false,
  };

  await supabase.from("sleep_insights").insert(insight);
}
