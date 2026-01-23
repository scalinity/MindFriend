// MindFriend Suggest Intervention Edge Function
// Determines intervention type and content based on prediction factors
// See: docs/specs/005-predictive-mood-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest, isValidUUID } from "../_shared/auth.ts";
import type {
  InterventionRequest,
  InterventionType,
  InterventionContent,
  MatchedExercise,
} from "./types.ts";

// Intervention content templates
const INTERVENTION_TEMPLATES: Record<InterventionType, InterventionContent> = {
  rest_suggestion: {
    type: "rest_suggestion",
    message:
      "Based on your sleep patterns, today might be challenging. A calming exercise could help you feel more grounded.",
    exerciseCategory: "meditation",
  },
  movement_suggestion: {
    type: "movement_suggestion",
    message:
      "Your activity has been lower lately. A gentle movement practice could boost your mood today.",
    exerciseCategory: "movement",
  },
  pattern_break: {
    type: "pattern_break",
    message:
      "We noticed a pattern that suggests today might be tough. Breaking routines with a new exercise can help.",
    exerciseCategory: "breathing",
  },
  general_support: {
    type: "general_support",
    message:
      "Today might be a bit challenging. Let's prepare together with a quick wellness exercise.",
    exerciseCategory: "grounding",
  },
};

// Thresholds for intervention decision
const SLEEP_HOURS_LOW = 6;
const STEPS_LOW = 3000;
const CONSECUTIVE_LOW_DAYS = 2;

/**
 * Determine intervention type based on prediction factors
 */
function determineInterventionType(
  request: InterventionRequest,
): InterventionType {
  const { features, factors } = request;

  // Check for sleep deficit (highest priority)
  if (
    features.sleep_hours !== null &&
    features.sleep_hours !== undefined &&
    features.sleep_hours < SLEEP_HOURS_LOW
  ) {
    return "rest_suggestion";
  }

  // Check for low activity
  if (
    features.steps_yesterday !== null &&
    features.steps_yesterday !== undefined &&
    features.steps_yesterday < STEPS_LOW
  ) {
    return "movement_suggestion";
  }

  // Check for pattern in factors (day of week, trend)
  const hasPatternFactor = factors.some(
    (f) =>
      f.factor === "day_of_week" ||
      f.factor === "mood_trend" ||
      f.factor.includes("pattern"),
  );

  if (hasPatternFactor) {
    return "pattern_break";
  }

  // Default to general support
  return "general_support";
}

/**
 * Match an exercise based on intervention type
 */
async function matchExercise(
  supabase: ReturnType<typeof createClient>,
  interventionType: InterventionType,
  userId: string,
): Promise<MatchedExercise | null> {
  const template = INTERVENTION_TEMPLATES[interventionType];

  if (!template.exerciseCategory) {
    return null;
  }

  // Find an exercise from the matching category that user hasn't done recently
  const { data: exercises, error } = await supabase
    .from("exercises")
    .select("id, title, type, duration_minutes")
    .eq("type", template.exerciseCategory)
    .eq("is_premium", false) // Start with free exercises
    .order("duration_minutes", { ascending: true }) // Prefer shorter exercises
    .limit(5);

  if (error || !exercises || exercises.length === 0) {
    // Fallback: get any short exercise
    const { data: fallback } = await supabase
      .from("exercises")
      .select("id, title, type, duration_minutes")
      .eq("is_premium", false)
      .lte("duration_minutes", 10)
      .order("duration_minutes", { ascending: true })
      .limit(1);

    return fallback?.[0] || null;
  }

  // Get exercises user has done in last 7 days
  const { data: recentSessions } = await supabase
    .from("exercise_sessions")
    .select("exercise_id")
    .eq("user_id", userId)
    .gte(
      "completed_at",
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
    );

  const recentExerciseIds = new Set(
    (recentSessions || []).map((s) => s.exercise_id),
  );

  // Prefer exercise user hasn't done recently
  const unseenExercise = exercises.find((e) => !recentExerciseIds.has(e.id));
  const selectedExercise = unseenExercise || exercises[0];

  // Defensive check - should never hit due to line 114 check
  if (!selectedExercise) {
    return null;
  }

  return selectedExercise as MatchedExercise;
}

/**
 * Generate personalized intervention message
 */
function generateMessage(
  interventionType: InterventionType,
  request: InterventionRequest,
  exercise: MatchedExercise | null,
): string {
  const template = INTERVENTION_TEMPLATES[interventionType];
  let message = template.message;

  // Add exercise suggestion if available
  if (exercise) {
    message += ` Try "${exercise.title}" (${exercise.duration_minutes} min)?`;
  }

  return message;
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

  // Require service role key (this is called by predict-mood function)
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cronSecret = Deno.env.get("CRON_SECRET");

  // Fail fast if required secrets are missing
  if (!serviceRoleKey || !cronSecret) {
    console.error("CRITICAL: Missing CRON_SECRET or SUPABASE_SERVICE_ROLE_KEY");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers },
    );
  }

  if (!isAuthorizedCronRequest(req.headers, cronSecret, serviceRoleKey)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Parse and validate request body
    let request: InterventionRequest;
    try {
      request = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
        status: 400,
        headers,
      });
    }

    // Validate required fields
    if (!request.userId || !request.predictionId) {
      return new Response(
        JSON.stringify({ error: "Missing userId or predictionId" }),
        { status: 400, headers },
      );
    }

    // Validate UUID format
    if (!isValidUUID(request.userId) || !isValidUUID(request.predictionId)) {
      return new Response(
        JSON.stringify({ error: "Invalid userId or predictionId format" }),
        { status: 400, headers },
      );
    }

    // Validate predictedMood is in valid range
    if (
      typeof request.predictedMood !== "number" ||
      request.predictedMood < 1 ||
      request.predictedMood > 10
    ) {
      return new Response(
        JSON.stringify({
          error: "predictedMood must be a number between 1 and 10",
        }),
        { status: 400, headers },
      );
    }

    // Determine intervention type
    const interventionType = determineInterventionType(request);

    // Match an exercise
    const exercise = await matchExercise(
      supabaseAdmin,
      interventionType,
      request.userId,
    );

    // Generate personalized message
    const message = generateMessage(interventionType, request, exercise);

    // Insert intervention record
    const { data: intervention, error: insertError } = await supabaseAdmin
      .from("preemptive_interventions")
      .insert({
        user_id: request.userId,
        prediction_id: request.predictionId,
        intervention_type: interventionType,
        content: message,
        suggested_exercise_id: exercise?.id || null,
        status: "pending",
      })
      .select()
      .single();

    if (insertError) {
      console.error("Error inserting intervention:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create intervention" }),
        { status: 500, headers },
      );
    }

    // Check if user has notifications enabled and is outside quiet hours
    const { data: settings } = await supabaseAdmin
      .from("user_settings")
      .select(
        "notifications_enabled, quiet_hours_start_local, quiet_hours_end_local",
      )
      .eq("user_id", request.userId)
      .single();

    let notificationSent = false;

    // Only send notification if enabled
    if (settings?.notifications_enabled !== false) {
      try {
        // Call send-notification function
        const notificationResponse = await supabaseAdmin.functions.invoke(
          "send-notification",
          {
            body: {
              type: "mood_prediction_alert",
              recipientId: request.userId,
              data: {
                interventionId: intervention.id,
                message: message,
                exerciseTitle: exercise?.title,
                exerciseId: exercise?.id,
              },
            },
          },
        );

        if (!notificationResponse.error) {
          notificationSent = true;

          // Update intervention as delivered
          await supabaseAdmin
            .from("preemptive_interventions")
            .update({
              status: "delivered",
              delivered_at: new Date().toISOString(),
            })
            .eq("id", intervention.id);

          // Update prediction notification_sent flag
          await supabaseAdmin
            .from("mood_predictions")
            .update({
              notification_sent: true,
              notification_sent_at: new Date().toISOString(),
            })
            .eq("id", request.predictionId);
        }
      } catch (notificationError) {
        console.error("Notification error:", notificationError);
        // Intervention still created, just not notified
      }
    }

    console.log("Intervention created:", {
      userId: request.userId,
      predictionId: request.predictionId,
      interventionType,
      exerciseId: exercise?.id,
      notificationSent,
    });

    return new Response(
      JSON.stringify({
        success: true,
        interventionId: intervention.id,
        type: interventionType,
        content: message,
        suggestedExerciseId: exercise?.id || null,
        notificationSent,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Suggest intervention error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
