// Intervention Efficacy Engine: Calculate Efficacy Edge Function
// Calculates efficacy scores from emotional trajectories

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  userId: string;
  exerciseId: string;
  trajectoryPoints: TrajectoryPoint[];
  sessionDuration: number;
}

interface EfficacyResult {
  efficacyScore: number;
  netEmotionalChange: number;
  trajectoryShape: string;
  breakthroughDetected: boolean;
  breakthroughSecond?: number;
}

serve(async (req) => {
  try {
    // Get user from JWT
    const authHeader = req.headers.get("Authorization")!;
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: { headers: { Authorization: authHeader } },
      },
    );

    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Parse request
    const body: CalculateEfficacyRequest = await req.json();

    // Validate input
    if (body.trajectoryPoints.length < 3) {
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

    // Calculate efficacy
    const efficacy = calculateEfficacy(body.trajectoryPoints);

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
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

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
      console.error("Failed to insert efficacy record:", insertError);
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

    return new Response(
      JSON.stringify({
        efficacyId: efficacyRecord.id,
        efficacyScore: efficacy.efficacyScore,
        netChange: efficacy.netEmotionalChange,
        trajectoryShape: efficacy.trajectoryShape,
        breakthroughDetected: efficacy.breakthroughDetected,
        breakthroughSecond: efficacy.breakthroughSecond,
        insights: {
          message: generateInsightMessage(efficacy),
          shouldCelebrate: efficacy.breakthroughDetected,
        },
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error in calculate-efficacy:", error);
    return new Response(
      JSON.stringify({
        error: "CALCULATION_FAILED",
        message: error.message,
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
  let trajectoryShape = "flat";

  if (netEmotionalChange > 0.3) {
    if (midpoint > startingScore) {
      trajectoryShape = "steadyImprovement";
    } else {
      trajectoryShape = "lateBreakthrough";
    }
  } else if (netEmotionalChange > 0.3 && midpoint > endingScore) {
    trajectoryShape = "earlyPeak";
  } else if (netEmotionalChange < -0.1) {
    trajectoryShape = "deterioration";
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
