// MindFriend Risk Assessment Edge Function
// Runs daily via cron or on-demand for individual users
// Calculates risk scores and triggers proactive interventions

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import {
  calculateBaseline,
  calculateRiskScore,
  classifyRiskLevel,
  predictTrend,
  predictMood24h,
  getInterventionType,
  getInterventionMessage,
  getSuggestedActions,
  type DailySignals,
  type BiometricSummary,
} from "../_shared/risk-scoring.ts";

interface AssessmentResult {
  userId: string;
  score: number;
  riskLevel: string;
  interventionTriggered: boolean;
  error?: string;
}

interface PredictionSettings {
  user_id: string;
  predictions_enabled: boolean;
  use_mood_data: boolean;
  use_chat_sentiment: boolean;
  use_biometrics: boolean;
  use_app_usage: boolean;
  use_sleep_data: boolean;
  allow_gentle_nudges: boolean;
  allow_active_checkins: boolean;
  preferred_intervention_time: string | null;
  allow_family_alerts: boolean;
  family_alert_threshold: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Check authorization
    const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const isCronOrService = isAuthorizedCronRequest(
      req.headers,
      expectedCronSecret,
      serviceRoleKey,
    );

    let requestUserId: string | null = null;

    // If not cron/service, verify JWT for single-user request
    if (!isCronOrService) {
      const authHeader = req.headers.get("Authorization");
      if (!authHeader) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers,
        });
      }

      const token = authHeader.replace("Bearer ", "");
      const {
        data: { user },
        error: userError,
      } = await supabaseAdmin.auth.getUser(token);

      if (userError || !user) {
        return new Response(JSON.stringify({ error: "Invalid token" }), {
          status: 401,
          headers,
        });
      }

      requestUserId = user.id;
    }

    // Parse request body
    const body = await req.json().catch(() => ({}));

    // SECURITY: Prevent IDOR - non-service requests can only assess themselves
    if (!isCronOrService && body.user_id && body.user_id !== requestUserId) {
      return new Response(
        JSON.stringify({ error: "Cannot assess other users" }),
        { status: 403, headers },
      );
    }

    const targetUserId = body.user_id || requestUserId;

    let usersToAssess: string[] = [];

    if (targetUserId) {
      // Single user assessment (on-demand)
      usersToAssess = [targetUserId];
    } else if (isCronOrService) {
      // Batch assessment for all users with predictions enabled
      const { data: users, error: usersError } = await supabaseAdmin
        .from("prediction_settings")
        .select("user_id")
        .eq("predictions_enabled", true);

      if (usersError) {
        console.error("Error fetching users:", usersError);
        return new Response(
          JSON.stringify({ error: "Failed to fetch eligible users" }),
          { status: 500, headers },
        );
      }

      usersToAssess = users?.map((u) => u.user_id) || [];
    } else {
      return new Response(JSON.stringify({ error: "No user specified" }), {
        status: 400,
        headers,
      });
    }

    console.log(`Starting risk assessment for ${usersToAssess.length} users`);

    const results: AssessmentResult[] = [];
    let interventionsCreated = 0;

    for (const userId of usersToAssess) {
      try {
        const result = await assessUser(supabaseAdmin, userId);
        results.push(result);
        if (result.interventionTriggered) {
          interventionsCreated++;
        }
      } catch (error) {
        console.error(`Error assessing user ${userId}:`, error);
        results.push({
          userId,
          score: 0,
          riskLevel: "error",
          interventionTriggered: false,
          error: String(error),
        });
      }
    }

    const summary = {
      assessed: results.length,
      successful: results.filter((r) => !r.error).length,
      interventionsCreated,
      byRiskLevel: {
        low: results.filter((r) => r.riskLevel === "low").length,
        medium: results.filter((r) => r.riskLevel === "medium").length,
        high: results.filter((r) => r.riskLevel === "high").length,
        crisis: results.filter((r) => r.riskLevel === "crisis").length,
      },
    };

    console.log("Assessment complete:", summary);

    return new Response(
      JSON.stringify({
        success: true,
        summary,
        results: targetUserId ? results[0] : undefined, // Only return single result for on-demand
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Risk assessment error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});

async function assessUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<AssessmentResult> {
  // 1. Check if user has predictions enabled
  const { data: settings, error: settingsError } = await supabase
    .from("prediction_settings")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (settingsError || !settings?.predictions_enabled) {
    return {
      userId,
      score: 0,
      riskLevel: "skipped",
      interventionTriggered: false,
    };
  }

  // 2. Aggregate today's signals (upsert)
  await supabase.rpc("aggregate_daily_signals", {
    p_user_id: userId,
    p_date: new Date().toISOString().split("T")[0],
  });

  // 3. Fetch recent signals (last 30 days)
  const { data: signals, error: signalsError } = await supabase
    .from("daily_signals")
    .select("*")
    .eq("user_id", userId)
    .order("signal_date", { ascending: true })
    .limit(30);

  if (signalsError) {
    throw new Error(`Failed to fetch signals: ${signalsError.message}`);
  }

  if (!signals || signals.length < 7) {
    // Need at least 7 days of data for meaningful assessment
    return {
      userId,
      score: 0,
      riskLevel: "insufficient_data",
      interventionTriggered: false,
    };
  }

  // 4. Fetch biometric data for today if available
  const today = signals[signals.length - 1];
  let biometrics: BiometricSummary | null = null;

  if (today.biometric_summary_id && settings.use_biometrics) {
    const { data: bioData } = await supabase
      .from("biometric_daily_summaries")
      .select(
        "sleep_duration_minutes, sleep_quality_score, hrv_average_ms, resting_heart_rate, steps_count, exercise_minutes, overall_wellness_score",
      )
      .eq("id", today.biometric_summary_id)
      .single();

    biometrics = bioData;
  }

  // 5. Calculate baseline from older data (excluding last 7 days)
  const baseline = calculateBaseline(signals.slice(0, -7));

  // 6. Calculate risk score
  const { score, factors, topFactors, confidence } = calculateRiskScore(
    signals as DailySignals[],
    baseline,
    biometrics,
  );

  const riskLevel = classifyRiskLevel(score);
  const predictedTrend = predictTrend(signals as DailySignals[]);
  const predictedMood = predictMood24h(signals as DailySignals[]);

  // 7. Store risk assessment
  const { data: assessment, error: assessmentError } = await supabase
    .from("risk_assessments")
    .insert({
      user_id: userId,
      risk_score: score,
      risk_level: riskLevel,
      factors,
      top_factors: topFactors,
      predicted_mood_24h: predictedMood,
      predicted_trend_7d: predictedTrend,
      model_version: "v1.0.0",
      confidence,
      daily_signal_id: today.id,
    })
    .select()
    .single();

  if (assessmentError) {
    throw new Error(`Failed to store assessment: ${assessmentError.message}`);
  }

  // 8. Trigger intervention if needed
  let interventionTriggered = false;

  if (riskLevel !== "low") {
    interventionTriggered = await triggerIntervention(
      supabase,
      userId,
      assessment,
      settings as PredictionSettings,
      topFactors,
      factors,
    );

    // Update assessment with intervention status
    if (interventionTriggered) {
      await supabase
        .from("risk_assessments")
        .update({ intervention_triggered: true })
        .eq("id", assessment.id);
    }
  }

  return {
    userId,
    score,
    riskLevel,
    interventionTriggered,
  };
}

async function triggerIntervention(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  assessment: { id: string; risk_level: string; risk_score: number },
  settings: PredictionSettings,
  topFactors: string[],
  factors: Record<string, unknown>,
): Promise<boolean> {
  const riskLevel = assessment.risk_level as
    | "low"
    | "medium"
    | "high"
    | "crisis";

  // Check user preferences
  const interventionType = getInterventionType(riskLevel);
  if (!interventionType) return false;

  if (interventionType === "gentle_nudge" && !settings.allow_gentle_nudges) {
    return false;
  }
  if (
    interventionType === "active_checkin" &&
    !settings.allow_active_checkins
  ) {
    return false;
  }

  // Check rate limiting: 1 intervention per 24 hours (unless crisis)
  if (riskLevel !== "crisis") {
    const { data: recentInterventions } = await supabase
      .from("interventions")
      .select("id")
      .eq("user_id", userId)
      .gte(
        "scheduled_at",
        new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      );

    if (recentInterventions && recentInterventions.length > 0) {
      console.log(`Rate limited: User ${userId} had intervention in last 24h`);
      return false;
    }

    // Also check proactive_messages for deduplication
    const { data: recentProactive } = await supabase
      .from("proactive_messages")
      .select("id")
      .eq("user_id", userId)
      .gte(
        "scheduled_for",
        new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      );

    if (recentProactive && recentProactive.length > 0) {
      console.log(
        `Deduplicated: User ${userId} had proactive message in last 24h`,
      );
      return false;
    }
  }

  // Generate intervention content
  const message = getInterventionMessage(interventionType, topFactors);
  const suggestedActions = getSuggestedActions(
    riskLevel,
    factors as Parameters<typeof getSuggestedActions>[1],
  );

  // Find a relevant exercise to suggest (breathing for crisis/high, variety for medium)
  let suggestedExerciseId: string | null = null;
  if (suggestedActions.includes("breathing_exercise")) {
    const { data: exercise } = await supabase
      .from("exercises")
      .select("id")
      .eq("type", "breathing")
      .eq("is_premium", false)
      .limit(1)
      .single();
    suggestedExerciseId = exercise?.id || null;
  }

  // Calculate optimal delivery time
  let scheduledAt = new Date();
  if (settings.preferred_intervention_time && riskLevel !== "crisis") {
    // Parse preferred time and schedule for that time today/tomorrow
    const [hours, minutes] = settings.preferred_intervention_time.split(":");
    const preferred = new Date();
    preferred.setHours(parseInt(hours, 10), parseInt(minutes, 10), 0, 0);

    if (preferred > scheduledAt) {
      scheduledAt = preferred;
    } else {
      // Schedule for tomorrow
      preferred.setDate(preferred.getDate() + 1);
      scheduledAt = preferred;
    }
  }

  // Create intervention
  const { data: intervention, error: interventionError } = await supabase
    .from("interventions")
    .insert({
      user_id: userId,
      risk_assessment_id: assessment.id,
      intervention_type: interventionType,
      channel: riskLevel === "crisis" ? "push" : "in_app",
      message_template: message,
      personalization: {
        risk_score: assessment.risk_score,
        top_factors: topFactors,
      },
      suggested_actions: suggestedActions,
      suggested_exercise_id: suggestedExerciseId,
      scheduled_at: scheduledAt.toISOString(),
      expires_at: new Date(
        scheduledAt.getTime() + 24 * 60 * 60 * 1000,
      ).toISOString(),
      response: "pending",
    })
    .select()
    .single();

  if (interventionError) {
    console.error("Failed to create intervention:", interventionError);
    return false;
  }

  console.log(
    `Created ${interventionType} intervention for user ${userId} (score: ${assessment.risk_score})`,
  );

  // For crisis level, also notify family if enabled
  if (
    riskLevel === "crisis" ||
    (riskLevel === "high" && settings.family_alert_threshold === "high")
  ) {
    if (settings.allow_family_alerts) {
      await sendFamilyAlert(supabase, userId, assessment, intervention.id);
    }
  }

  // Send push notification for crisis immediately
  if (riskLevel === "crisis" || interventionType === "crisis_protocol") {
    await sendCrisisNotification(supabase, userId, message);
  }

  return true;
}

async function sendFamilyAlert(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  assessment: { id: string; risk_level: string; risk_score: number },
  interventionId: string,
): Promise<void> {
  // Find family members who should be alerted (parents/guardians)
  const { data: familyMembers } = await supabase
    .from("family_members")
    .select("parent_user_id")
    .eq("child_user_id", userId);

  if (!familyMembers || familyMembers.length === 0) return;

  for (const member of familyMembers) {
    // Use existing family_alerts table
    await supabase.from("family_alerts").insert({
      family_group_id: null, // Will be filled if needed
      triggered_by_user_id: userId,
      alert_type: "mental_health_risk",
      severity: assessment.risk_level === "crisis" ? "high" : "medium",
      title: "Wellness Check Recommended",
      message:
        "Your family member may benefit from some extra support right now.",
      action_url: `/family/wellness/${userId}`,
      metadata: {
        risk_assessment_id: assessment.id,
        intervention_id: interventionId,
        risk_level: assessment.risk_level,
      },
    });

    console.log(
      `Sent family alert for user ${userId} to ${member.parent_user_id}`,
    );
  }
}

async function sendCrisisNotification(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  message: string,
): Promise<void> {
  // Get user's device token
  const { data: deviceToken } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", userId)
    .eq("is_active", true)
    .single();

  if (!deviceToken) return;

  // Send via notification service
  try {
    await supabase.functions.invoke("send-notification", {
      body: {
        user_id: userId,
        title: "MindFriend Check-in",
        body: message,
        data: {
          type: "crisis_intervention",
          action: "open_crisis_resources",
        },
        priority: "high",
      },
    });
  } catch (error) {
    console.error("Failed to send crisis notification:", error);
  }
}
