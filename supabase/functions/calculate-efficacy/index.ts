import { observedTrajectory } from "./observations.ts";
import { calculateEfficacy, type EfficacyResult, type TrajectoryPoint } from "./calculation.ts";
// Intervention Efficacy Engine: Calculate Efficacy Edge Function
// Calculates efficacy scores from emotional trajectories

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import {
  createLogger,
  generateRequestId,
  getUserIdFromRequest,
} from "../_shared/logger.ts";
import {
  createErrorMonitor,
  ERROR_RATE_THRESHOLDS,
} from "../_shared/errorMonitor.ts";

interface CalculateEfficacyRequest {
  sessionId: string;
  exerciseId: string;
  trajectoryPoints?: TrajectoryPoint[]; // Legacy clients may send these; never used as observations.
  sessionDuration: number;
  // Note: userId is derived from JWT auth token, not request body
}

Deno.serve(async (req) => {
  const startTime = performance.now();
  const requestId = generateRequestId();
  const logger = createLogger("calculate-efficacy", { requestId });

  try {
    logger.logRequest(req.method, "/calculate-efficacy");

    // Validate HTTP method
    if (req.method !== "POST") {
      logger.warn("Invalid HTTP method", { method: req.method });

      return new Response(
        JSON.stringify({
          error: "METHOD_NOT_ALLOWED",
          message: "Only POST requests are accepted",
        }),
        {
          status: 405,
          headers: {
            "Content-Type": "application/json",
            Allow: "POST",
          },
        },
      );
    }

    // Validate authentication
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      logger.warn("Authentication failed", { error: authError?.message });
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Invalid or expired authentication token",
        }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    logger.addContext({ userId: user.id });
    logger.info("User authenticated");

    // Parse request
    const body: CalculateEfficacyRequest = await req.json();
    logger.addContext({
      sessionId: body.sessionId,
      exerciseId: body.exerciseId,
      trajectoryPointsCount: body.trajectoryPoints?.length ?? 0,
    });
    logger.info("Request parsed");

    if (typeof body.sessionId !== "string" || typeof body.exerciseId !== "string") {
      return new Response(JSON.stringify({ error: "INVALID_SESSION" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    // Swift sends uppercase UUID strings; PostgREST returns lowercase.
    body.sessionId = body.sessionId.toLowerCase();
    body.exerciseId = body.exerciseId.toLowerCase();

    // Verify session ownership (prevent unauthorized efficacy submission)
    const { data: session, error: sessionError } = await supabaseAdmin
      .from("exercise_sessions")
      .select("user_id, exercise_id")
      .eq("id", body.sessionId)
      .single();

    if (sessionError || !session) {
      return new Response(
        JSON.stringify({
          error: "SESSION_NOT_FOUND",
          message: "The specified session does not exist",
        }),
        {
          status: 404,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (session.user_id !== user.id) {
      logger.warn("Session ownership mismatch", {
        sessionUserId: session.user_id,
        requestUserId: user.id,
      });
      return new Response(
        JSON.stringify({
          error: "FORBIDDEN",
          message:
            "You do not have permission to submit efficacy data for this session",
        }),
        {
          status: 403,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    logger.info("Session ownership verified");

    if (session.exercise_id !== body.exerciseId) {
      return new Response(JSON.stringify({ error: "EXERCISE_MISMATCH" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    // An older client can submit simulated samples. Use only owned, explicitly
    // sourced stored observations; lack of measurement never fails completion.
    const { data: storedTrajectory, error: trajectoryError } = await supabaseAdmin
      .from("emotional_trajectories")
      .select("samples, measurement_status, measurement_source")
      .eq("session_id", body.sessionId)
      .eq("exercise_id", body.exerciseId)
      .eq("user_id", user.id)
      .eq("measurement_status", "observed")
      .eq("measurement_source", "self_reported_valence")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (trajectoryError) throw trajectoryError;
    const trajectory = observedTrajectory(storedTrajectory);
    if (!trajectory) {
      return new Response(JSON.stringify({
        status: "unavailable",
        reason: "No supported emotional measurements were recorded for this session.",
      }), { headers: { "Content-Type": "application/json" } });
    }

    // Calculate efficacy
    logger.debug("Starting efficacy calculation");
    const efficacy = await logger.measure("calculateEfficacy", async () =>
      calculateEfficacy(trajectory),
    );
    logger.info("Efficacy calculated", {
      efficacyScore: efficacy.efficacyScore,
      trajectoryShape: efficacy.trajectoryShape,
      breakthroughDetected: efficacy.breakthroughDetected,
    });

    // Determine time of day
    const completedAt = new Date();
    const hour = completedAt.getHours();
    const timeOfDay =
      hour >= 5 && hour < 12
        ? "morning"
        : hour >= 12 && hour < 17
          ? "afternoon"
          : hour >= 17 && hour < 21
            ? "evening"
            : "night";

    // Self-reports establish emotional valence, not a physiological or stress reading.
    const firstPoint = trajectory[0];
    const startingState = {
      primaryEmotion: firstPoint.emotionClassification!.primary,
    };

    // Insert efficacy record using service role client
    logger.debug("Inserting efficacy record to database");
    const { data: efficacyRecord, error: insertError } = await supabaseAdmin
      .from("intervention_efficacy")
      .insert({
        user_id: user.id,
        measurement_status: "observed",
        measurement_source: "self_reported_valence",
        exercise_id: body.exerciseId,
        session_id: body.sessionId,
        completed_at: completedAt.toISOString(),
        efficacy_score: efficacy.efficacyScore,
        net_emotional_change: efficacy.netEmotionalChange,
        trajectory_shape: efficacy.trajectoryShape,
        breakthrough_detected: efficacy.breakthroughDetected,
        breakthrough_second: efficacy.breakthroughSecond,
        starting_state: startingState,
        time_of_day: timeOfDay,
        day_of_week: completedAt.getDay() + 1, // 1-7 (Sunday = 1)
      })
      .select()
      .single();

    if (insertError) {
      logger.error(
        "Failed to insert efficacy record",
        insertError instanceof Error
          ? insertError
          : new Error(String(insertError)),
      );
      return new Response(
        JSON.stringify({
          error: "DATABASE_ERROR",
          message: "Failed to save efficacy record",
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    logger.info("Efficacy record saved", { efficacyId: efficacyRecord.id });

    const duration = performance.now() - startTime;
    logger.logResponse("POST", "/calculate-efficacy", 200, duration);

    return new Response(
      JSON.stringify({
        status: "observed",
        efficacy_id: efficacyRecord.id,
        efficacy_score: efficacy.efficacyScore,
        net_emotional_change: efficacy.netEmotionalChange,
        trajectory_shape: efficacy.trajectoryShape,
        breakthrough_detected: efficacy.breakthroughDetected,
        breakthrough_second: efficacy.breakthroughSecond,
        insights: {
          message: generateInsightMessage(efficacy),
          should_celebrate: efficacy.breakthroughDetected,
        },
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const duration = performance.now() - startTime;
    const errorObj = error instanceof Error ? error : new Error(String(error));

    logger.error("Unhandled error in calculate-efficacy", errorObj);

    // Record error for monitoring
    try {
      const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      );
      const errorMonitor = createErrorMonitor(
        "calculate-efficacy",
        supabaseAdmin,
        logger,
      );
      await errorMonitor.recordError(errorObj, {
        requestId,
        duration,
        path: "/calculate-efficacy",
      });

      // Check error rate and trigger alerts if needed
      await errorMonitor.checkErrorRate(ERROR_RATE_THRESHOLDS.CRITICAL);
    } catch (monitorError) {
      // Don't fail the response if monitoring fails
      logger.warn("Error monitoring failed", { error: monitorError });
    }
    logger.logResponse("POST", "/calculate-efficacy", 500, duration);

    return new Response(
      JSON.stringify({
        error: "CALCULATION_FAILED",
        message: (error as Error).message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});

function generateInsightMessage(efficacy: EfficacyResult): string {
  if (efficacy.breakthroughDetected) {
    return "Breakthrough moment detected! You experienced a rapid positive shift during this session.";
  } else if (efficacy.efficacyScore >= 80) {
    return "Excellent session! This exercise was highly effective for you.";
  } else if (efficacy.efficacyScore >= 60) {
    return "Good session! You showed positive improvement.";
  } else if (efficacy.efficacyScore >= 40) {
    return "Moderate session. Some improvement detected.";
  } else {
    return "This exercise may not be optimal for your current state. Try a different approach.";
  }
}
