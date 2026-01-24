// Intervention Efficacy Engine: Calculate Efficacy Edge Function
// Calculates efficacy scores from emotional trajectories

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createLogger,
  generateRequestId,
  getUserIdFromRequest,
} from "../_shared/logger.ts";
import {
  createErrorMonitor,
  ERROR_RATE_THRESHOLDS,
} from "../_shared/errorMonitor.ts";

interface TrajectoryPoint {
  timestamp: string;
  secondsFromStart: number;
  nervousSystemState?: string;
  emotionClassification?: {
    primary: string;
    valence: number;
  };
  hrvReading?: number;
  compositeScore: number;
}

interface CalculateEfficacyRequest {
  sessionId: string;
  exerciseId: string;
  trajectoryPoints: TrajectoryPoint[];
  sessionDuration: number;
  // Note: userId is derived from JWT auth token, not request body
}

type TrajectoryShape =
  | "steadyImprovement"
  | "lateBreakthrough"
  | "earlyPeak"
  | "deterioration"
  | "flat";

interface EfficacyResult {
  efficacyScore: number;
  netEmotionalChange: number;
  trajectoryShape: TrajectoryShape;
  breakthroughDetected: boolean;
  breakthroughSecond?: number;
}

serve(async (req) => {
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
      trajectoryPointsCount: body.trajectoryPoints.length,
    });
    logger.info("Request parsed");

    // Validate input
    if (body.trajectoryPoints.length < 3) {
      logger.warn("Insufficient trajectory data", {
        pointCount: body.trajectoryPoints.length,
      });

      return new Response(
        JSON.stringify({
          error: "INSUFFICIENT_DATA",
          message: "Trajectory must have at least 3 data points",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Verify session ownership (prevent unauthorized efficacy submission)
    const { data: session, error: sessionError } = await supabaseAdmin
      .from("exercise_sessions")
      .select("user_id")
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

    // Calculate efficacy
    logger.debug("Starting efficacy calculation");
    const efficacy = await logger.measure("calculateEfficacy", async () =>
      calculateEfficacy(body.trajectoryPoints),
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

    // Extract starting state
    const firstPoint = body.trajectoryPoints[0];
    const startingState = {
      nervousSystemState: firstPoint.nervousSystemState || "unknown",
      primaryEmotion: firstPoint.emotionClassification?.primary || "neutral",
      stressLevel:
        firstPoint.compositeScore < -0.5
          ? 0.8
          : firstPoint.compositeScore < 0
            ? 0.5
            : 0.2,
    };

    // Insert efficacy record using service role client
    logger.debug("Inserting efficacy record to database");
    const { data: efficacyRecord, error: insertError } = await supabaseAdmin
      .from("intervention_efficacy")
      .insert({
        user_id: user.id,
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

function calculateEfficacy(trajectory: TrajectoryPoint[]): EfficacyResult {
  // Extract phases
  const totalPoints = trajectory.length;
  const preEndIndex = Math.floor(totalPoints * 0.2);
  const midStartIndex = Math.floor(totalPoints * 0.2);
  const midEndIndex = Math.floor(totalPoints * 0.8);
  const postStartIndex = Math.floor(totalPoints * 0.8);

  const prePhase = trajectory.slice(0, preEndIndex || 1);
  const midPhase = trajectory.slice(midStartIndex, midEndIndex);
  const postPhase = trajectory.slice(postStartIndex);

  // Calculate metrics
  const startingScore = prePhase[0].compositeScore;
  const endingScore = postPhase[postPhase.length - 1].compositeScore;
  const netEmotionalChange = Math.max(
    -1,
    Math.min(1, endingScore - startingScore),
  );

  // Regulation quality: 1 - std_dev of middle 60%
  const midScores = midPhase.map((p) => p.compositeScore);

  // Guard against empty midPhase (shouldn't happen with >= 3 points, but defensive)
  if (midScores.length === 0) {
    return {
      efficacyScore: 50, // Neutral baseline
      netEmotionalChange: endingScore - startingScore,
      trajectoryShape: "flat",
      breakthroughDetected: false,
      breakthroughSecond: undefined,
    };
  }

  const midMean = midScores.reduce((a, b) => a + b, 0) / midScores.length;
  const midVariance =
    midScores.reduce((sum, score) => sum + Math.pow(score - midMean, 2), 0) /
    midScores.length;
  const midStdDev = Math.sqrt(midVariance);
  const regulationQuality = Math.max(0, Math.min(1, 1 - midStdDev));

  // Sustained improvement: compare post-60% avg to pre-20% avg
  const preAvg =
    prePhase.reduce((sum, p) => sum + p.compositeScore, 0) / prePhase.length;
  const postAvg =
    postPhase.reduce((sum, p) => sum + p.compositeScore, 0) / postPhase.length;
  const sustainedImprovement = Math.max(-1, Math.min(1, postAvg - preAvg));

  // Composite score using CORRECTED FORMULA: 2 * (weighted_sum) - 1
  const weights = [0.4, 0.35, 0.25];
  const weightedSum =
    (weights[0] * (netEmotionalChange + 1)) / 2 +
    weights[1] * regulationQuality +
    (weights[2] * (sustainedImprovement + 1)) / 2;
  const compositeScore = Math.max(-1, Math.min(1, 2 * weightedSum - 1));

  // Convert to 0-100 efficacy score
  let efficacyScore = 50 + compositeScore * 40;

  // Sustained improvement bonus
  if (sustainedImprovement > 0 && postAvg >= endingScore - 0.1) {
    efficacyScore += 10;
  }

  // Breakthrough detection
  const breakthrough = detectBreakthrough(trajectory);
  if (breakthrough.detected) {
    efficacyScore += 10;
  }

  // Starting state penalty (if already in good state)
  if (startingScore > 0.5) {
    efficacyScore *= 0.9;
  }

  efficacyScore = Math.max(0, Math.min(100, efficacyScore));

  // Determine trajectory shape
  const midpoint = trajectory[Math.floor(totalPoints / 2)].compositeScore;
  let trajectoryShape: TrajectoryShape;

  if (netEmotionalChange > 0.3) {
    // Check earlyPeak first (peak in middle but decline at end)
    if (midpoint > endingScore && midpoint > startingScore) {
      trajectoryShape = "earlyPeak";
    } else if (midpoint > startingScore) {
      trajectoryShape = "steadyImprovement";
    } else {
      trajectoryShape = "lateBreakthrough";
    }
  } else if (netEmotionalChange < -0.2) {
    trajectoryShape = "deterioration";
  } else {
    trajectoryShape = "flat";
  }

  return {
    efficacyScore,
    netEmotionalChange,
    trajectoryShape,
    breakthroughDetected: breakthrough.detected,
    breakthroughSecond: breakthrough.second,
  };
}

function detectBreakthrough(trajectory: TrajectoryPoint[]): {
  detected: boolean;
  second?: number;
} {
  for (let i = 0; i < trajectory.length - 1; i++) {
    const current = trajectory[i];
    const next = trajectory[i + 1];
    const change = next.compositeScore - current.compositeScore;
    const duration = next.secondsFromStart - current.secondsFromStart;

    if (change > 0.4 && duration <= 60) {
      return { detected: true, second: next.secondsFromStart };
    }
  }

  return { detected: false };
}

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
