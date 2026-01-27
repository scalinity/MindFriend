/**
 * Generate Longitudinal Report - Edge Function
 * HTTP POST endpoint to generate quarterly/annual/custom wellness reports
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getMonthBounds } from "../_shared/longitudinal-utils.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ReportRequest {
  reportType: "quarterly" | "annual" | "custom";
  timePeriod?: {
    start: string;
    end: string;
  };
}

interface ChartDataPoint {
  date: string;
  value: number;
}

interface ReportContent {
  summary: string;
  key_insights: string[];
  charts_data: {
    mood_trend: ChartDataPoint[];
    activity_heatmap: Array<{ week: string; days: number }>;
    seasonal_comparison: Record<string, number>;
  };
  recommendations: string[];
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const xaiApiKey = Deno.env.get("XAI_API_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing environment variables");
    }

    // Validate authorization
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          code: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Get user from JWT
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ code: "UNAUTHORIZED", message: "Invalid token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: ReportRequest = await req.json();
    const { reportType, timePeriod } = body;

    if (
      !reportType ||
      !["quarterly", "annual", "custom"].includes(reportType)
    ) {
      return new Response(
        JSON.stringify({
          code: "INVALID_REQUEST",
          message: "Invalid report type",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate time period based on report type
    let startDate: Date;
    let endDate: Date;
    const now = new Date();

    if (reportType === "quarterly") {
      // Last 3 complete months
      const currentMonth = getMonthBounds(now);
      endDate = currentMonth.start;
      startDate = new Date(endDate);
      startDate.setUTCMonth(startDate.getUTCMonth() - 3);
    } else if (reportType === "annual") {
      // Last 12 complete months
      const currentMonth = getMonthBounds(now);
      endDate = currentMonth.start;
      startDate = new Date(endDate);
      startDate.setUTCFullYear(startDate.getUTCFullYear() - 1);
    } else {
      // Custom period
      if (!timePeriod || !timePeriod.start || !timePeriod.end) {
        return new Response(
          JSON.stringify({
            code: "INVALID_REQUEST",
            message: "Custom report requires timePeriod",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      startDate = new Date(timePeriod.start);
      endDate = new Date(timePeriod.end);

      // Validate date range (max 24 months)
      const diffMonths =
        (endDate.getFullYear() - startDate.getFullYear()) * 12 +
        (endDate.getMonth() - startDate.getMonth());

      if (diffMonths > 24) {
        return new Response(
          JSON.stringify({
            code: "INVALID_REQUEST",
            message: "Maximum range is 24 months",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (startDate >= endDate) {
        return new Response(
          JSON.stringify({
            code: "INVALID_REQUEST",
            message: "Start date must be before end date",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Fetch data for the report
    const [monthlyStats, weeklyStats, patterns, lifeEvents, yearlyStats] =
      await Promise.all([
        supabase
          .from("longitudinal_monthly_stats")
          .select("*")
          .eq("user_id", user.id)
          .gte("month_start", startDate.toISOString())
          .lt("month_start", endDate.toISOString())
          .order("month_start", { ascending: true }),

        supabase
          .from("longitudinal_weekly_stats")
          .select("*")
          .eq("user_id", user.id)
          .gte("week_start", startDate.toISOString())
          .lt("week_start", endDate.toISOString())
          .order("week_start", { ascending: true }),

        supabase
          .from("longitudinal_patterns")
          .select("*")
          .eq("user_id", user.id)
          .eq("is_active", true),

        supabase
          .from("longitudinal_life_events")
          .select("*")
          .eq("user_id", user.id)
          .gte("event_date", startDate.toISOString().split("T")[0])
          .lt("event_date", endDate.toISOString().split("T")[0]),

        supabase
          .from("longitudinal_yearly_stats")
          .select("*")
          .eq("user_id", user.id)
          .order("year", { ascending: false })
          .limit(2),
      ]);

    // Check for sufficient data
    const hasMonthlyData = (monthlyStats.data?.length || 0) >= 1;
    const hasWeeklyData = (weeklyStats.data?.length || 0) >= 4;

    if (!hasMonthlyData && !hasWeeklyData) {
      return new Response(
        JSON.stringify({
          code: "INSUFFICIENT_DATA",
          message:
            "Not enough data for this report type. Try again after more activity.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build chart data
    const moodTrend: ChartDataPoint[] = (weeklyStats.data || [])
      .filter((s) => s.avg_mood !== null)
      .map((s) => ({
        date: s.week_start.split("T")[0],
        value: s.avg_mood,
      }));

    const activityHeatmap = (weeklyStats.data || []).map((s) => ({
      week: s.week_start.split("T")[0],
      days: s.active_days || 0,
    }));

    // Calculate seasonal comparison from yearly stats
    const seasonalComparison: Record<string, number> = {};
    const latestYear = yearlyStats.data?.[0];
    if (latestYear?.seasonal_patterns) {
      const sp = latestYear.seasonal_patterns as Record<string, number | null>;
      if (sp.winter !== null) seasonalComparison.winter = sp.winter;
      if (sp.spring !== null) seasonalComparison.spring = sp.spring;
      if (sp.summer !== null) seasonalComparison.summer = sp.summer;
      if (sp.fall !== null) seasonalComparison.fall = sp.fall;
    }

    // Generate insights and summary
    const insights: string[] = [];
    const recommendations: string[] = [];

    // Calculate overall statistics
    const avgMoods = (monthlyStats.data || [])
      .filter((s) => s.avg_mood !== null)
      .map((s) => s.avg_mood as number);

    const overallAvg =
      avgMoods.length > 0
        ? (avgMoods.reduce((a, b) => a + b, 0) / avgMoods.length).toFixed(2)
        : "N/A";

    // Trend insight
    const trendCounts = (monthlyStats.data || []).reduce(
      (acc, s) => {
        if (s.mood_trend === "improving") acc.improving++;
        else if (s.mood_trend === "declining") acc.declining++;
        else acc.stable++;
        return acc;
      },
      { improving: 0, declining: 0, stable: 0 },
    );

    if (trendCounts.improving > trendCounts.declining) {
      insights.push(
        `Your mood has been generally improving over the past ${avgMoods.length} months`,
      );
    } else if (trendCounts.declining > trendCounts.improving) {
      insights.push(
        `Your mood has shown some decline recently - consider reaching out for support`,
      );
      recommendations.push(
        "Consider scheduling a check-in with a mental health professional",
      );
    } else {
      insights.push(
        `Your mood has remained relatively stable over the reporting period`,
      );
    }

    // Pattern insights
    const activePatterns = patterns.data || [];
    for (const pattern of activePatterns) {
      if (pattern.confidence > 0.7) {
        insights.push(pattern.pattern_description);
      }
    }

    // Life event insights
    const events = lifeEvents.data || [];
    if (events.length > 0) {
      const positiveEvents = events.filter((e) => (e.impact_score || 0) > 0);
      const negativeEvents = events.filter((e) => (e.impact_score || 0) < 0);

      if (positiveEvents.length > 0) {
        insights.push(
          `${positiveEvents.length} positive life event(s) occurred during this period`,
        );
      }
      if (negativeEvents.length > 0) {
        insights.push(
          `${negativeEvents.length} challenging life event(s) occurred during this period`,
        );
        recommendations.push(
          "Continue self-care practices during challenging times",
        );
      }
    }

    // Seasonal insight
    if (Object.keys(seasonalComparison).length >= 2) {
      const seasons = Object.entries(seasonalComparison).sort(
        (a, b) => b[1] - a[1],
      );
      const best = seasons[0];
      const worst = seasons[seasons.length - 1];
      insights.push(
        `Your mood tends to be highest in ${best[0]} and lowest in ${worst[0]}`,
      );
      recommendations.push(
        `Plan additional self-care activities during ${worst[0]} months`,
      );
    }

    // Activity insight
    const totalActiveDays = (weeklyStats.data || []).reduce(
      (sum, s) => sum + (s.active_days || 0),
      0,
    );
    const avgActiveDaysPerWeek = weeklyStats.data?.length
      ? (totalActiveDays / weeklyStats.data.length).toFixed(1)
      : "0";
    insights.push(`You averaged ${avgActiveDaysPerWeek} active days per week`);

    // Generate summary
    let summary = `Your ${reportType} mental wellness report covers ${startDate.toISOString().split("T")[0]} to ${endDate.toISOString().split("T")[0]}. `;
    summary += `Your average mood score was ${overallAvg}. `;

    if (activePatterns.length > 0) {
      summary += `${activePatterns.length} wellness pattern(s) were detected. `;
    }
    if (events.length > 0) {
      summary += `You logged ${events.length} significant life event(s). `;
    }

    // Add AI-generated insights if API key available
    if (xaiApiKey && insights.length > 0) {
      try {
        const aiPrompt = `You are a supportive mental wellness assistant. Based on the following insights about a user's mental health journey, provide 2-3 personalized, actionable recommendations in a warm, encouraging tone:

Insights:
${insights.join("\n")}

Provide recommendations that are specific, achievable, and supportive. Do not diagnose or prescribe. Format as a simple list.`;

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);

        const aiResponse = await fetch("https://api.x.ai/v1/chat/completions", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${xaiApiKey}`,
          },
          body: JSON.stringify({
            model: "grok-2-latest",
            messages: [{ role: "user", content: aiPrompt }],
            max_tokens: 300,
            temperature: 0.7,
          }),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (aiResponse.ok) {
          const aiData = await aiResponse.json();
          const aiRecommendations = aiData.choices?.[0]?.message?.content;
          if (aiRecommendations) {
            // Parse bullet points
            const aiRecs = aiRecommendations
              .split("\n")
              .filter(
                (line: string) =>
                  line.trim().startsWith("-") || line.trim().startsWith("•"),
              )
              .map((line: string) => line.replace(/^[-•]\s*/, "").trim())
              .slice(0, 3);
            recommendations.push(...aiRecs);
          }
        }
      } catch (aiError) {
        console.warn("AI recommendation generation failed:", aiError);
        // Continue without AI recommendations
      }
    }

    // Default recommendations if none generated
    if (recommendations.length === 0) {
      recommendations.push(
        "Continue tracking your mood to build long-term insights",
      );
      recommendations.push(
        "Try to maintain consistent sleep and exercise routines",
      );
    }

    // Build report content
    const contentJson: ReportContent = {
      summary,
      key_insights: insights.slice(0, 10), // Limit to 10 insights
      charts_data: {
        mood_trend: moodTrend,
        activity_heatmap: activityHeatmap,
        seasonal_comparison: seasonalComparison,
      },
      recommendations: [...new Set(recommendations)].slice(0, 5), // Unique, limit to 5
    };

    // Calculate expiration (24 months from now)
    const expiresAt = new Date();
    expiresAt.setMonth(expiresAt.getMonth() + 24);

    // Save report to database
    const { data: report, error: insertError } = await supabase
      .from("longitudinal_reports")
      .insert({
        user_id: user.id,
        report_type: reportType,
        time_period: {
          start: startDate.toISOString().split("T")[0],
          end: endDate.toISOString().split("T")[0],
        },
        content_json: contentJson,
        expires_at: expiresAt.toISOString(),
      })
      .select()
      .single();

    if (insertError) throw insertError;

    return new Response(
      JSON.stringify({
        success: true,
        report_id: report.id,
        report_type: reportType,
        time_period: {
          start: startDate.toISOString().split("T")[0],
          end: endDate.toISOString().split("T")[0],
        },
        content_json: contentJson,
        generated_at: report.generated_at,
        expires_at: report.expires_at,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Report generation error:", error);
    return new Response(
      JSON.stringify({
        code: "GENERATION_FAILED",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
