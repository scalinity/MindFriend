/**
 * Generate Longitudinal Report - Edge Function
 * Generates personalized wellness reports based on longitudinal data
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ReportRequest {
  report_type: "quarterly" | "annual" | "custom";
  time_period?: {
    start: string;
    end: string;
  };
}

interface ReportContent {
  summary: string;
  key_insights: string[];
  charts_data: {
    mood_trend: { date: string; value: number }[];
    activity_heatmap: { week: string; days: number }[];
    seasonal_comparison: Record<string, number>;
  };
  recommendations: string[];
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  console.log("=== [generate-longitudinal-report] START ===");
  console.log("[1] Method:", req.method);
  console.log("[2] URL:", req.url);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    console.log("[3] Returning CORS preflight response");
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    console.log("[4] SUPABASE_URL present:", !!supabaseUrl);
    console.log("[4b] SUPABASE_ANON_KEY present:", !!supabaseAnonKey);
    console.log("[5] SUPABASE_SERVICE_ROLE_KEY present:", !!serviceRoleKey);

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      console.error("[ERROR] Missing environment variables");
      return new Response(
        JSON.stringify({ success: false, error: "Server configuration error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check Authorization header
    const authHeader = req.headers.get("Authorization");
    console.log("[6] Authorization header present:", !!authHeader);

    if (!authHeader) {
      console.error("[ERROR] No Authorization header");
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing authorization header",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(
      "[7] Auth header starts with Bearer:",
      authHeader.startsWith("Bearer "),
    );
    console.log("[8] Auth header length:", authHeader.length);

    if (!authHeader.startsWith("Bearer ")) {
      console.error("[ERROR] Authorization header doesn't start with Bearer");
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid authorization format",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    console.log("[9] Token extracted, length:", token.length);

    // Create user-scoped client with the JWT token (same pattern as privacy-lock-settings)
    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: `Bearer ${token}` },
      },
    });
    console.log("[10] User-scoped client created");

    // Create admin client for database operations (bypasses RLS)
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    console.log("[10b] Admin client created");

    // Validate user with user-scoped client
    console.log("[11] Calling auth.getUser...");
    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    console.log(
      "[12] auth.getUser returned, error:",
      authError?.message || "none",
    );
    console.log("[13] User returned:", !!user);

    if (authError || !user) {
      console.error(
        "[ERROR] Token validation failed:",
        authError?.message || "No user returned",
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: authError?.message || "Invalid token",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const userId = user.id;
    console.log("[14] Auth successful, userId:", userId);

    // Use the admin client for database operations (bypasses RLS)
    const supabase = supabaseAdmin;

    const body: ReportRequest = await req.json();
    const reportType = body.report_type || "quarterly";
    console.log("[15] Report type:", reportType);

    const now = new Date();
    let startDate: Date;
    let endDate: Date = now;

    if (body.time_period) {
      startDate = new Date(body.time_period.start);
      endDate = new Date(body.time_period.end);
    } else {
      startDate = new Date(now);
      if (reportType === "annual") {
        startDate.setFullYear(startDate.getFullYear() - 1);
      } else {
        startDate.setMonth(startDate.getMonth() - 3);
      }
    }
    console.log(
      "[16] Date range:",
      startDate.toISOString(),
      "to",
      endDate.toISOString(),
    );

    const { data: moods } = await supabase
      .from("moods")
      .select("mood_score, created_at")
      .eq("user_id", userId)
      .gte("created_at", startDate.toISOString())
      .lte("created_at", endDate.toISOString())
      .order("created_at", { ascending: true });

    const { data: sessions } = await supabase
      .from("exercise_sessions")
      .select("completed_at")
      .eq("user_id", userId)
      .eq("completed", true)
      .gte("completed_at", startDate.toISOString())
      .lte("completed_at", endDate.toISOString());

    const { data: patterns } = await supabase
      .from("longitudinal_patterns")
      .select("pattern_description, confidence")
      .eq("user_id", userId)
      .eq("is_active", true)
      .order("confidence", { ascending: false })
      .limit(5);

    const moodData = moods || [];
    const sessionData = sessions || [];
    const patternData = patterns || [];
    console.log(
      "[17] Data fetched - moods:",
      moodData.length,
      "sessions:",
      sessionData.length,
      "patterns:",
      patternData.length,
    );

    const moodScores = moodData.map((m) => m.mood_score);
    const avgMood =
      moodScores.length > 0
        ? moodScores.reduce((a, b) => a + b, 0) / moodScores.length
        : 0;

    let moodTrend = "stable";
    if (moodScores.length >= 10) {
      const mid = Math.floor(moodScores.length / 2);
      const firstAvg =
        moodScores.slice(0, mid).reduce((a, b) => a + b, 0) / mid;
      const secondAvg =
        moodScores.slice(mid).reduce((a, b) => a + b, 0) /
        (moodScores.length - mid);
      if (secondAvg - firstAvg > 0.3) moodTrend = "improving";
      else if (secondAvg - firstAvg < -0.3) moodTrend = "declining";
    }

    const moodTrendData = moodData.map((m) => ({
      date: m.created_at.split("T")[0],
      value: m.mood_score,
    }));

    const activityByWeek: Record<string, Set<string>> = {};
    for (const mood of moodData) {
      const d = new Date(mood.created_at);
      const day = d.getDay();
      const diff = d.getDate() - day;
      d.setDate(diff);
      const weekStart = d.toISOString().split("T")[0];
      const dayKey = mood.created_at.split("T")[0];
      if (!activityByWeek[weekStart]) activityByWeek[weekStart] = new Set();
      activityByWeek[weekStart].add(dayKey);
    }
    const activityHeatmap = Object.entries(activityByWeek).map(
      ([week, days]) => ({
        week,
        days: days.size,
      }),
    );

    const keyInsights: string[] = [];
    if (moodScores.length > 0) {
      keyInsights.push(
        "Your average mood score was " +
          avgMood.toFixed(1) +
          " out of 5 during this period.",
      );
    }
    if (moodTrend === "improving") {
      keyInsights.push("Your mood has been trending upward - great progress!");
    } else if (moodTrend === "declining") {
      keyInsights.push(
        "Your mood has been declining. Consider reaching out for support if needed.",
      );
    } else if (moodScores.length >= 10) {
      keyInsights.push(
        "Your mood has been relatively stable during this period.",
      );
    }
    if (sessionData.length > 0) {
      keyInsights.push(
        "You completed " +
          sessionData.length +
          " wellness exercises during this period.",
      );
    }
    for (const pattern of patternData.slice(0, 2)) {
      keyInsights.push(pattern.pattern_description);
    }

    const recommendations: string[] = [];
    if (avgMood < 3) {
      recommendations.push(
        "Try incorporating more self-care activities into your daily routine.",
      );
      recommendations.push(
        "Consider speaking with a mental health professional for additional support.",
      );
    } else {
      recommendations.push(
        "Keep up your current wellness habits - they seem to be working!",
      );
    }
    if (sessionData.length < 5) {
      recommendations.push(
        "Try to complete more wellness exercises to build healthy habits.",
      );
    }
    recommendations.push(
      "Continue tracking your mood regularly to build a clearer picture of your wellness journey.",
    );

    const periodLabel = reportType === "annual" ? "year" : "quarter";
    let summary =
      "Over the past " +
      periodLabel +
      ", you logged " +
      moodData.length +
      " mood entries";
    if (sessionData.length > 0) {
      summary +=
        " and completed " + sessionData.length + " wellness exercises.";
    } else {
      summary += ".";
    }
    summary += " Your mood has been " + moodTrend + ".";

    const contentJson: ReportContent = {
      summary,
      key_insights: keyInsights,
      charts_data: {
        mood_trend: moodTrendData.slice(-30),
        activity_heatmap: activityHeatmap.slice(-12),
        seasonal_comparison: {},
      },
      recommendations,
    };

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 90);

    console.log("[18] Inserting report into database...");
    const { data: reportData, error: insertError } = await supabase
      .from("longitudinal_reports")
      .insert({
        user_id: userId,
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

    if (insertError) {
      console.error("[ERROR] Error inserting report:", insertError);
      throw new Error("Failed to save report: " + insertError.message);
    }

    console.log("[19] Report saved successfully, id:", reportData.id);
    console.log("=== [generate-longitudinal-report] SUCCESS ===");

    return new Response(
      JSON.stringify({
        success: true,
        report_id: reportData.id,
        report_type: reportType,
        time_period: {
          start: startDate.toISOString().split("T")[0],
          end: endDate.toISOString().split("T")[0],
        },
        content_json: contentJson,
        generated_at: reportData.generated_at,
        expires_at: reportData.expires_at,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("=== [generate-longitudinal-report] ERROR ===");
    console.error("Report generation error:", error);
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
