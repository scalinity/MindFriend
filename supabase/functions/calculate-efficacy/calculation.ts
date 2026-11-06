export interface TrajectoryPoint {
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

type TrajectoryShape =
  | "steadyImprovement"
  | "lateBreakthrough"
  | "earlyPeak"
  | "deterioration"
  | "flat";

export interface EfficacyResult {
  efficacyScore: number;
  netEmotionalChange: number;
  trajectoryShape: TrajectoryShape;
  breakthroughDetected: boolean;
  breakthroughSecond?: number;
}

export function calculateEfficacy(trajectory: TrajectoryPoint[]): EfficacyResult {
  // Extract phases
  const totalPoints = trajectory.length;
  const preEndIndex = Math.max(1, Math.floor(totalPoints * 0.2));
  const midStartIndex = preEndIndex;
  const midEndIndex = Math.floor(totalPoints * 0.8);
  const postStartIndex = Math.floor(totalPoints * 0.8);

  const prePhase = trajectory.slice(0, preEndIndex);
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

