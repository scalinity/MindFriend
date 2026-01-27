// MindFriend Analyze Biometrics Edge Function
// Analyzes biometric data to generate insights, correlations, and alerts
// Triggered by cron job (daily) or directly
// See: docs/specs/04-biometric-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface AnalysisResult {
  userId: string;
  insights: GeneratedInsight[];
  alerts: GeneratedAlert[];
  correlationsUpdated: boolean;
}

interface GeneratedInsight {
  type: string;
  category: string;
  title: string;
  description: string;
  correlationStrength?: number;
  confidence: number;
}

interface GeneratedAlert {
  type: string;
  severity: string;
  title: string;
  message: string;
  triggerMetric: string;
  triggerValue: number;
  baselineValue: number;
  suggestedActionType?: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
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

    // Check for cron secret or auth header
    const cronSecret = req.headers.get("X-Cron-Secret");
    const expectedSecret = Deno.env.get("CRON_SECRET");
    const authHeader = req.headers.get("Authorization");

    let targetUserId: string | null = null;

    // If cron request, process all connected users
    if (cronSecret && cronSecret === expectedSecret) {
      console.log("Processing biometric analysis (cron)");
    } else if (authHeader) {
      // Single user request
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
      targetUserId = user.id;
    } else {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Get users with HealthKit connected and insights enabled
    let connectionQuery = supabase
      .from("healthkit_connections")
      .select("user_id")
      .eq("is_connected", true)
      .eq("enable_insights", true);

    if (targetUserId) {
      connectionQuery = connectionQuery.eq("user_id", targetUserId);
    }

    const { data: connections } = await connectionQuery;

    if (!connections?.length) {
      return new Response(
        JSON.stringify({ processed: 0, message: "No connected users" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const results: AnalysisResult[] = [];

    for (const conn of connections) {
      const result = await analyzeUserBiometrics(supabase, conn.user_id);
      results.push(result);
    }

    // Process alerts for users who have them enabled
    let alertConnectionQuery = supabase
      .from("healthkit_connections")
      .select("user_id")
      .eq("is_connected", true)
      .eq("enable_alerts", true);

    if (targetUserId) {
      alertConnectionQuery = alertConnectionQuery.eq("user_id", targetUserId);
    }

    const { data: alertConnections } = await alertConnectionQuery;

    if (alertConnections) {
      for (const conn of alertConnections) {
        await processUserAlerts(supabase, conn.user_id);
      }
    }

    const totalInsights = results.reduce(
      (sum, r) => sum + r.insights.length,
      0,
    );
    const totalAlerts = results.reduce((sum, r) => sum + r.alerts.length, 0);

    console.log(
      `Analysis complete: ${results.length} users, ${totalInsights} insights, ${totalAlerts} alerts`,
    );

    return new Response(
      JSON.stringify({
        processed: results.length,
        insightsGenerated: totalInsights,
        alertsGenerated: totalAlerts,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Analyze biometrics error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function analyzeUserBiometrics(
  supabase: any,
  userId: string,
): Promise<AnalysisResult> {
  const insights: GeneratedInsight[] = [];
  const alerts: GeneratedAlert[] = [];

  // Get last 30 days of biometric data
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data: biometrics } = await supabase
    .from("biometric_daily_summaries")
    .select("*")
    .eq("user_id", userId)
    .gte("date", thirtyDaysAgo.toISOString().split("T")[0])
    .order("date", { ascending: true });

  // Get last 30 days of mood data
  const { data: moods } = await supabase
    .from("moods")
    .select("created_at, score")
    .eq("user_id", userId)
    .gte("created_at", thirtyDaysAgo.toISOString())
    .order("created_at", { ascending: true });

  if (!biometrics?.length || !moods?.length) {
    return { userId, insights, alerts, correlationsUpdated: false };
  }

  // Calculate sleep-mood correlation
  const sleepMoodCorrelation = calculateSleepMoodCorrelation(biometrics, moods);
  if (sleepMoodCorrelation) {
    // Store correlation
    await supabase.from("mood_biometric_correlations").upsert(
      {
        user_id: userId,
        biometric_type: "sleep_duration",
        correlation_coefficient: sleepMoodCorrelation.coefficient,
        data_points: sleepMoodCorrelation.dataPoints,
        period_days: 30,
        computed_at: new Date().toISOString(),
        strength_label: getStrengthLabel(sleepMoodCorrelation.coefficient),
        direction_label:
          sleepMoodCorrelation.coefficient > 0 ? "positive" : "negative",
      },
      { onConflict: "user_id,biometric_type,period_days" },
    );

    // Generate insight if correlation is significant
    if (Math.abs(sleepMoodCorrelation.coefficient) > 0.3) {
      insights.push({
        type: "sleep_mood_correlation",
        category: "sleep",
        title: "Sleep & Mood Connection Found",
        description: generateSleepInsightDescription(sleepMoodCorrelation),
        correlationStrength: sleepMoodCorrelation.coefficient,
        confidence: Math.min(sleepMoodCorrelation.dataPoints / 20, 1),
      });
    }
  }

  // Calculate activity-mood correlation
  const activityMoodCorrelation = calculateActivityMoodCorrelation(
    biometrics,
    moods,
  );
  if (activityMoodCorrelation) {
    // Store correlation
    await supabase.from("mood_biometric_correlations").upsert(
      {
        user_id: userId,
        biometric_type: "steps",
        correlation_coefficient: activityMoodCorrelation.coefficient,
        data_points: activityMoodCorrelation.dataPoints,
        period_days: 30,
        computed_at: new Date().toISOString(),
        strength_label: getStrengthLabel(activityMoodCorrelation.coefficient),
        direction_label:
          activityMoodCorrelation.coefficient > 0 ? "positive" : "negative",
      },
      { onConflict: "user_id,biometric_type,period_days" },
    );

    if (Math.abs(activityMoodCorrelation.coefficient) > 0.25) {
      insights.push({
        type: "activity_mood_correlation",
        category: "activity",
        title: "Activity & Mood Pattern",
        description: generateActivityInsightDescription(
          activityMoodCorrelation,
        ),
        correlationStrength: activityMoodCorrelation.coefficient,
        confidence: Math.min(activityMoodCorrelation.dataPoints / 20, 1),
      });
    }
  }

  // Check HRV trends
  const hrvTrend = analyzeHRVTrend(biometrics);
  if (hrvTrend.significant) {
    insights.push({
      type: "hrv_trend",
      category: "stress",
      title:
        hrvTrend.direction === "down"
          ? "Stress Indicators Rising"
          : "Recovery Improving",
      description: generateHRVInsightDescription(hrvTrend),
      confidence: 0.7,
    });
  }

  // Store insights
  for (const insight of insights) {
    await supabase.from("biometric_insights").insert({
      user_id: userId,
      insight_type: insight.type,
      insight_category: insight.category,
      title: insight.title,
      description: insight.description,
      correlation_strength: insight.correlationStrength,
      confidence_score: insight.confidence,
      period_start_date: thirtyDaysAgo.toISOString().split("T")[0],
      period_end_date: new Date().toISOString().split("T")[0],
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(), // 7 days
    });
  }

  return { userId, insights, alerts, correlationsUpdated: true };
}

function calculateSleepMoodCorrelation(biometrics: any[], moods: any[]) {
  // Match sleep data with next-day mood
  const pairs: { sleep: number; mood: number }[] = [];

  for (const bio of biometrics) {
    const nextDay = new Date(bio.date);
    nextDay.setDate(nextDay.getDate() + 1);
    const nextDayStr = nextDay.toISOString().split("T")[0];

    // Find mood entry for next day
    const moodEntry = moods.find((m: any) =>
      m.created_at.startsWith(nextDayStr),
    );

    if (moodEntry && bio.sleep_duration_minutes) {
      pairs.push({
        sleep: bio.sleep_duration_minutes,
        mood: moodEntry.score,
      });
    }
  }

  if (pairs.length < 7) return null;

  return calculatePearsonCorrelation(
    pairs.map((p) => p.sleep),
    pairs.map((p) => p.mood),
  );
}

function calculateActivityMoodCorrelation(biometrics: any[], moods: any[]) {
  // Same-day correlation with steps
  const pairs: { activity: number; mood: number }[] = [];

  for (const bio of biometrics) {
    const dateStr = bio.date;
    const moodEntry = moods.find((m: any) => m.created_at.startsWith(dateStr));

    if (moodEntry && bio.steps_count) {
      pairs.push({
        activity: bio.steps_count,
        mood: moodEntry.score,
      });
    }
  }

  if (pairs.length < 7) return null;

  return calculatePearsonCorrelation(
    pairs.map((p) => p.activity),
    pairs.map((p) => p.mood),
  );
}

function calculatePearsonCorrelation(x: number[], y: number[]) {
  const n = x.length;
  const sumX = x.reduce((a, b) => a + b, 0);
  const sumY = y.reduce((a, b) => a + b, 0);
  const sumXY = x.reduce((sum, xi, i) => sum + xi * y[i], 0);
  const sumX2 = x.reduce((sum, xi) => sum + xi * xi, 0);
  const sumY2 = y.reduce((sum, yi) => sum + yi * yi, 0);

  const numerator = n * sumXY - sumX * sumY;
  const denominator = Math.sqrt(
    (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY),
  );

  if (denominator === 0) return null;

  return {
    coefficient: numerator / denominator,
    dataPoints: n,
  };
}

function analyzeHRVTrend(biometrics: any[]) {
  const hrvValues = biometrics
    .filter((b) => b.hrv_average_ms)
    .map((b) => b.hrv_average_ms);

  if (hrvValues.length < 14) {
    return { significant: false, direction: "stable", change: 0 };
  }

  // Compare last 7 days to previous 7 days
  const recent = hrvValues.slice(-7);
  const previous = hrvValues.slice(-14, -7);

  if (previous.length < 7) {
    return { significant: false, direction: "stable", change: 0 };
  }

  const recentAvg = recent.reduce((a, b) => a + b, 0) / recent.length;
  const previousAvg = previous.reduce((a, b) => a + b, 0) / previous.length;
  const change = (recentAvg - previousAvg) / previousAvg;

  return {
    significant: Math.abs(change) > 0.1, // 10% change
    direction: change > 0 ? "up" : "down",
    change: change * 100,
  };
}

function getStrengthLabel(coefficient: number): string {
  const abs = Math.abs(coefficient);
  if (abs >= 0.7) return "strong";
  if (abs >= 0.4) return "moderate";
  if (abs >= 0.2) return "weak";
  return "none";
}

function generateSleepInsightDescription(correlation: any): string {
  const strength = getStrengthLabel(correlation.coefficient);
  const direction = correlation.coefficient > 0 ? "better" : "lower";

  if (strength === "strong") {
    return `We found a strong connection between your sleep and mood. On days after you sleep longer, your mood tends to be ${direction}. Prioritizing sleep could significantly impact your wellbeing.`;
  } else if (strength === "moderate") {
    return `There's a noticeable pattern: your mood tends to be ${direction} after nights with more sleep. This insight is based on ${correlation.dataPoints} days of data.`;
  }
  return `We're seeing early signs that sleep affects your mood. Keep logging to strengthen this insight.`;
}

function generateActivityInsightDescription(correlation: any): string {
  const direction = correlation.coefficient > 0 ? "better" : "variable";
  return `Your mood tends to be ${direction} on more active days. This pattern appeared in ${correlation.dataPoints} days of your data.`;
}

function generateHRVInsightDescription(trend: any): string {
  if (trend.direction === "down") {
    return `Your heart rate variability has decreased by ${Math.abs(trend.change).toFixed(0)}% over the past week. This can indicate elevated stress. Consider adding relaxation practices.`;
  }
  return `Your heart rate variability has improved by ${trend.change.toFixed(0)}% recently. This suggests better recovery and stress management. Keep up what you're doing!`;
}

async function processUserAlerts(supabase: any, userId: string) {
  // Get user's baseline
  const { data: baselines } = await supabase
    .from("biometric_baselines")
    .select("*")
    .eq("user_id", userId);

  if (!baselines?.length) return;

  // Get yesterday's data
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = yesterday.toISOString().split("T")[0];

  const { data: yesterdayData } = await supabase
    .from("biometric_daily_summaries")
    .select("*")
    .eq("user_id", userId)
    .eq("date", yesterdayStr)
    .single();

  if (!yesterdayData) return;

  const baselineMap = new Map(baselines.map((b: any) => [b.metric_type, b]));

  // Check sleep
  const sleepBaseline = baselineMap.get("sleep_duration");
  if (sleepBaseline && yesterdayData.sleep_duration_minutes) {
    const deviation =
      (yesterdayData.sleep_duration_minutes - sleepBaseline.baseline_value) /
      sleepBaseline.baseline_value;

    if (deviation < -0.2) {
      // 20% below baseline
      await supabase.from("biometric_alerts").insert({
        user_id: userId,
        alert_type: "low_sleep",
        severity: deviation < -0.3 ? "warning" : "info",
        title: "Sleep Alert",
        message:
          "You slept less than usual last night. Today might be a good day for extra self-care.",
        trigger_metric: "sleep_duration",
        trigger_value: yesterdayData.sleep_duration_minutes,
        baseline_value: sleepBaseline.baseline_value,
        deviation_percent: deviation * 100,
        suggested_action_type: "rest",
      });
    }
  }

  // Check HRV
  const hrvBaseline = baselineMap.get("hrv");
  if (hrvBaseline && yesterdayData.hrv_average_ms) {
    const deviation =
      (yesterdayData.hrv_average_ms - hrvBaseline.baseline_value) /
      hrvBaseline.baseline_value;

    if (deviation < -0.15) {
      // 15% below baseline
      await supabase.from("biometric_alerts").insert({
        user_id: userId,
        alert_type: "hrv_drop",
        severity: deviation < -0.25 ? "warning" : "info",
        title: "Stress Indicator",
        message:
          "Your stress indicators are elevated. Would you like a quick breathing exercise?",
        trigger_metric: "hrv",
        trigger_value: yesterdayData.hrv_average_ms,
        baseline_value: hrvBaseline.baseline_value,
        deviation_percent: deviation * 100,
        suggested_action_type: "breathing",
      });
    }
  }

  // Check activity
  const stepsBaseline = baselineMap.get("steps");
  if (stepsBaseline && yesterdayData.steps_count) {
    const deviation =
      (yesterdayData.steps_count - stepsBaseline.baseline_value) /
      stepsBaseline.baseline_value;

    if (deviation < -0.4) {
      // 40% below baseline
      await supabase.from("biometric_alerts").insert({
        user_id: userId,
        alert_type: "inactivity",
        severity: "info",
        title: "Activity Reminder",
        message:
          "You were less active than usual yesterday. Movement often helps mood—even a short walk counts!",
        trigger_metric: "steps",
        trigger_value: yesterdayData.steps_count,
        baseline_value: stepsBaseline.baseline_value,
        deviation_percent: deviation * 100,
        suggested_action_type: "exercise",
      });
    }
  }
}
