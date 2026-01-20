import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface WeeklyWellbeingRequest {
  metrics: { category: string; score: number }[];
  highlight?: string;
  challenge?: string;
  gratitude?: string;
}

serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false } },
  );

  // Verify authorization
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "UNAUTHORIZED",
          message: "Please sign in to submit wellbeing check",
        },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "UNAUTHORIZED", message: "Invalid or expired token" },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const body: WeeklyWellbeingRequest = await req.json();
    const { metrics, highlight, challenge, gratitude } = body;

    // Calculate total score
    const totalScore = metrics.reduce((sum, m) => sum + m.score, 0);

    // Get previous week's score for trend calculation
    const oneWeekAgo = new Date();
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);

    const { data: previousCheck } = await supabase
      .from("weekly_wellbeing_checks")
      .select("total_score")
      .eq("user_id", user.id)
      .gte("created_at", oneWeekAgo.toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    const previousScore = previousCheck?.total_score;
    let trend: "improving" | "declining" | "stable" = "stable";

    if (previousScore !== null && previousScore !== undefined) {
      if (totalScore > previousScore + 2) trend = "improving";
      else if (totalScore < previousScore - 2) trend = "declining";
      else trend = "stable";
    }

    // Create the check-in
    const metricsMap = Object.fromEntries(
      metrics.map((m) => [m.category, m.score]),
    );
    const weekStartDate = getWeekStart(new Date());

    const { data: check, error } = await supabase
      .from("weekly_wellbeing_checks")
      .insert({
        user_id: user.id,
        week_start_date: weekStartDate.toISOString(),
        overall_mood: metricsMap.mood || 5,
        energy_level: metricsMap.energy || 5,
        stress_level: metricsMap.stress || 5,
        sleep_quality: metricsMap.sleep || 5,
        social_connection: metricsMap.social || 5,
        sense_of_purpose: metricsMap.purpose || 5,
        highlight_of_week: highlight,
        challenge_of_week: challenge,
        gratitude_note: gratitude,
        total_score: totalScore,
        previous_week_score: previousScore,
        trend,
      })
      .select()
      .single();

    if (error) throw error;

    // Generate insights based on scores
    const insights = generateInsights(metricsMap);

    // Get previous trends for chart
    const { data: previousTrends } = await supabase
      .from("weekly_wellbeing_checks")
      .select(
        "overall_mood, energy_level, stress_level, sleep_quality, social_connection, sense_of_purpose, created_at",
      )
      .eq("user_id", user.id)
      .lt("created_at", oneWeekAgo.toISOString())
      .order("created_at", { ascending: false })
      .limit(4);

    const trendData = (previousTrends || []).map((prev, idx) => ({
      category: Object.keys(prev)[0],
      current: metricsMap[Object.keys(prev)[idx]] || 5,
      previous: Object.values(prev)[idx] as number,
      trend: "stable", // Simplified
    }));

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          check: {
            id: check.id,
            user_id: check.user_id,
            week_start_date: check.week_start_date,
            created_at: check.created_at,
            overall_mood: check.overall_mood,
            energy_level: check.energy_level,
            stress_level: check.stress_level,
            sleep_quality: check.sleep_quality,
            social_connection: check.social_connection,
            sense_of_purpose: check.sense_of_purpose,
            highlight_of_week: check.highlight_of_week,
            challenge_of_week: check.challenge_of_week,
            gratitude_note: check.gratitude_note,
            total_score: check.total_score,
            previous_week_score: check.previous_week_score,
            trend: check.trend,
          },
          previous_trend: trendData,
          insights,
        },
        error: null,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in weekly wellbeing function:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "SERVER_ERROR",
          message: "Unable to save your check-in; please try again",
        },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

function getWeekStart(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  d.setDate(diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

function generateInsights(metrics: Record<string, number>): string[] {
  const insights: string[] = [];

  if (metrics.mood >= 8) {
    insights.push("Your mood has been consistently positive this week!");
  } else if (metrics.mood <= 4) {
    insights.push(
      "It's been a challenging week emotionally. Be kind to yourself.",
    );
  }

  if (metrics.stress >= 8) {
    insights.push("High stress levels might benefit from breathing exercises.");
  }

  if (metrics.sleep <= 4) {
    insights.push(
      "Sleep quality impacts many areas of wellbeing. Consider a sleep routine.",
    );
  }

  if (metrics.social <= 4) {
    insights.push(
      "Connecting with others can boost your mood and sense of purpose.",
    );
  }

  return insights;
}
