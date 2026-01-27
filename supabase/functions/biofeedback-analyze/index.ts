// supabase/functions/biofeedback-analyze/index.ts
// Edge Function: Real-time biometric analysis for biofeedback adaptation

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface AnalyzeRequest {
  session_id: string;
  heart_rate: number;
  hrv_rmssd?: number;
  hrv_sdnn?: number;
  elapsed_seconds: number;
}

interface AdaptationSuggestion {
  type: string;
  priority: "high" | "medium" | "low";
  reason: string;
  params: Record<string, unknown>;
}

interface BiometricAnalysis {
  physiological_state: string;
  stress_level: number;
  trend: string;
  adaptations: AdaptationSuggestion[];
  should_extend: boolean;
  extension_reason?: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

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

    const body: AnalyzeRequest = await req.json();

    if (
      !body.session_id ||
      !body.heart_rate ||
      body.elapsed_seconds === undefined
    ) {
      return new Response(
        JSON.stringify({
          error:
            "Missing required fields: session_id, heart_rate, elapsed_seconds",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (body.heart_rate < 30 || body.heart_rate > 250) {
      return new Response(
        JSON.stringify({ error: "Invalid heart rate value" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: session } = await supabase
      .from("biofeedback_sessions")
      .select("id, user_id, adaptation_mode, started_at")
      .eq("id", body.session_id)
      .eq("user_id", user.id)
      .single();

    if (!session) {
      return new Response(
        JSON.stringify({ error: "Session not found or unauthorized" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: baseline } = await supabase
      .from("biometric_baselines")
      .select("*")
      .eq("user_id", user.id)
      .single();

    const { data: recentReadings } = await supabase
      .from("biofeedback_readings")
      .select("heart_rate, hrv_rmssd, timestamp")
      .eq("session_id", body.session_id)
      .order("timestamp", { ascending: false })
      .limit(10);

    const analysis = analyzeCurrentState(
      body.heart_rate,
      body.hrv_rmssd,
      baseline,
      recentReadings || [],
      body.elapsed_seconds,
      session.adaptation_mode,
    );

    const stressLevel = analysis.stress_level;
    await supabase.from("biofeedback_readings").insert({
      session_id: body.session_id,
      heart_rate: body.heart_rate,
      hrv_sdnn: body.hrv_sdnn,
      hrv_rmssd: body.hrv_rmssd,
      relative_stress_level: stressLevel,
      adaptation_applied:
        analysis.adaptations.length > 0
          ? { suggestions: analysis.adaptations.map((a) => a.type) }
          : {},
    });

    if (analysis.adaptations.length > 0) {
      const adaptationRecords = analysis.adaptations.map((a) => ({
        session_id: body.session_id,
        adaptation_type: a.type,
        new_value: a.params,
        trigger_reason: a.reason,
        biometric_trigger: {
          heart_rate: body.heart_rate,
          hrv_rmssd: body.hrv_rmssd,
          stress_level: stressLevel,
        },
      }));

      await supabase.from("biofeedback_adaptations").insert(adaptationRecords);
    }

    return new Response(JSON.stringify({ success: true, analysis }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function analyzeCurrentState(
  heartRate: number,
  hrvRmssd: number | undefined,
  baseline: Record<string, unknown> | null,
  recentReadings: Array<{
    heart_rate: number;
    hrv_rmssd?: number;
    timestamp: string;
  }>,
  elapsedSeconds: number,
  adaptationMode: string,
): BiometricAnalysis {
  const adaptations: AdaptationSuggestion[] = [];

  let stressLevel = 0.5;
  let physiologicalState = "baseline";

  const baselineTyped = baseline as {
    resting_heart_rate?: number;
    stress_hr_threshold?: number;
  } | null;

  if (baselineTyped?.resting_heart_rate && baselineTyped?.stress_hr_threshold) {
    const range =
      baselineTyped.stress_hr_threshold - baselineTyped.resting_heart_rate;
    const current = heartRate - baselineTyped.resting_heart_rate;
    stressLevel = Math.max(0, Math.min(1, current / range));

    if (stressLevel <= 0.2) {
      physiologicalState = "recovered";
    } else if (stressLevel <= 0.4) {
      physiologicalState = "relaxing";
    } else if (stressLevel <= 0.6) {
      physiologicalState = "baseline";
    } else if (stressLevel <= 0.8) {
      physiologicalState = "elevated";
    } else {
      physiologicalState = "stressed";
    }
  } else {
    if (heartRate < 70) {
      stressLevel = 0.2;
      physiologicalState = "relaxing";
    } else if (heartRate < 85) {
      stressLevel = 0.4;
      physiologicalState = "baseline";
    } else if (heartRate < 100) {
      stressLevel = 0.6;
      physiologicalState = "elevated";
    } else {
      stressLevel = 0.8;
      physiologicalState = "stressed";
    }
  }

  let trend: string = "stable";
  if (recentReadings.length >= 3) {
    const recentHRs = recentReadings.map((r) => r.heart_rate);
    const avgRecent = recentHRs.slice(0, 3).reduce((a, b) => a + b, 0) / 3;
    const avgOlder =
      recentHRs.length >= 6
        ? recentHRs.slice(3, 6).reduce((a, b) => a + b, 0) /
          Math.min(3, recentHRs.length - 3)
        : avgRecent;

    const diff = avgRecent - avgOlder;
    if (diff < -3) {
      trend = "improving";
    } else if (diff > 3) {
      trend = "worsening";
    }
  }

  if (adaptationMode !== "off") {
    const isAggressive = adaptationMode === "aggressive";
    const isAuto = adaptationMode === "auto";

    if (
      physiologicalState === "stressed" ||
      physiologicalState === "elevated"
    ) {
      if (isAggressive || isAuto) {
        adaptations.push({
          type: "breathing_pace",
          priority: physiologicalState === "stressed" ? "high" : "medium",
          reason: `Heart rate elevated (${Math.round(heartRate)} BPM). Adjusting breathing pace for calming.`,
          params:
            physiologicalState === "stressed"
              ? { inhale: 3, hold: 2, exhale: 5, pause: 1 }
              : { inhale: 4, hold: 4, exhale: 6, pause: 2 },
        });
      }
    } else if (
      physiologicalState === "relaxing" ||
      physiologicalState === "recovered"
    ) {
      if (isAggressive) {
        adaptations.push({
          type: "breathing_pace",
          priority: "low",
          reason:
            "Relaxed state achieved. Transitioning to deeper breathing pattern.",
          params: { inhale: 5, hold: 7, exhale: 8, pause: 3 },
        });
      }
    }

    if (
      (physiologicalState === "stressed" ||
        physiologicalState === "elevated") &&
      isAggressive
    ) {
      adaptations.push({
        type: "guidance_frequency",
        priority: "medium",
        reason:
          "Increasing guidance to help maintain focus during elevated stress.",
        params: { verbosity: "detailed", interval_seconds: 15 },
      });
    }

    if (physiologicalState === "stressed" && stressLevel > 0.85) {
      adaptations.push({
        type: "intensity_reduction",
        priority: "high",
        reason: "High stress detected. Reducing exercise intensity.",
        params: { visual_intensity: 0.4, audio_volume: 0.6 },
      });
    }
  }

  let shouldExtend = false;
  let extensionReason: string | undefined;

  if (
    elapsedSeconds >= 180 &&
    (physiologicalState === "stressed" || physiologicalState === "elevated")
  ) {
    shouldExtend = true;
    extensionReason =
      physiologicalState === "stressed"
        ? "Your heart rate is still elevated. A few more minutes may help you reach a calmer state."
        : "You're making progress! A bit more time could deepen your relaxation.";
  }

  return {
    physiological_state: physiologicalState,
    stress_level: Math.round(stressLevel * 100) / 100,
    trend,
    adaptations,
    should_extend: shouldExtend,
    extension_reason: extensionReason,
  };
}
