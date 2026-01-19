// Risk Scoring Algorithm for Predictive Intervention
// Calculates risk scores based on mood, engagement, sleep, biometrics, and social signals

export interface DailySignals {
  id: string;
  user_id: string;
  signal_date: string;
  biometric_summary_id: string | null;
  mood_average: number | null;
  mood_min: number | null;
  mood_max: number | null;
  mood_variance: number | null;
  mood_trend: number | null;
  mood_entry_count: number;
  app_sessions: number;
  total_active_minutes: number;
  features_used: string[];
  quests_completed: number;
  exercises_completed: number;
  chat_messages_sent: number;
  circle_posts: number;
  circle_reactions_received: number;
  circle_comments_made: number;
  engagement_score: number | null;
  social_score: number | null;
  biometric_score: number | null;
  current_streak: number;
  streak_broken_today: boolean;
}

export interface BiometricSummary {
  sleep_duration_minutes: number | null;
  sleep_quality_score: number | null;
  hrv_average_ms: number | null;
  resting_heart_rate: number | null;
  steps_count: number | null;
  exercise_minutes: number | null;
  overall_wellness_score: number | null;
}

export interface UserBaseline {
  avg_mood: number;
  avg_hrv: number;
  avg_app_sessions: number;
  avg_sleep_hours: number;
  avg_steps: number;
  avg_engagement_score: number;
  avg_social_score: number;
}

export interface RiskFactors {
  mood_trend?: number;
  mood_volatility?: number;
  app_engagement?: number;
  sleep_quality?: number;
  hrv_drop?: number;
  streak_broken?: boolean;
  days_since_chat?: number;
  social_engagement?: number;
}

export interface RiskScoreResult {
  score: number;
  factors: RiskFactors;
  topFactors: string[];
  confidence: number;
}

// Weights for different signal categories (must sum to 100)
const WEIGHTS = {
  moodTrend: 25, // Most important predictor
  moodVolatility: 15,
  engagement: 15,
  sleep: 15,
  biometrics: 15,
  social: 10,
  streak: 5,
};

/**
 * Calculate user's baseline from historical signals
 */
export function calculateBaseline(signals: DailySignals[]): UserBaseline {
  if (signals.length === 0) {
    return {
      avg_mood: 5,
      avg_hrv: 50,
      avg_app_sessions: 1,
      avg_sleep_hours: 7,
      avg_steps: 5000,
      avg_engagement_score: 50,
      avg_social_score: 25,
    };
  }

  const sum = signals.reduce(
    (acc, s) => ({
      mood: acc.mood + (s.mood_average || 5),
      sessions: acc.sessions + s.app_sessions,
      engagement: acc.engagement + (s.engagement_score || 50),
      social: acc.social + (s.social_score || 25),
    }),
    { mood: 0, sessions: 0, engagement: 0, social: 0 },
  );

  return {
    avg_mood: sum.mood / signals.length,
    avg_hrv: 50, // Will be populated from biometric data if available
    avg_app_sessions: sum.sessions / signals.length,
    avg_sleep_hours: 7, // Will be populated from biometric data if available
    avg_steps: 5000, // Will be populated from biometric data if available
    avg_engagement_score: sum.engagement / signals.length,
    avg_social_score: sum.social / signals.length,
  };
}

/**
 * Calculate risk score based on recent signals and baseline
 */
export function calculateRiskScore(
  signals: DailySignals[],
  baseline: UserBaseline,
  biometrics: BiometricSummary | null,
): RiskScoreResult {
  if (signals.length === 0) {
    return {
      score: 0,
      factors: {},
      topFactors: [],
      confidence: 0,
    };
  }

  let totalScore = 0;
  const factors: RiskFactors = {};
  const factorContributions: { label: string; value: number }[] = [];

  // Get most recent signals (last 7 days)
  const recent = signals.slice(-7);
  const today = signals[signals.length - 1];

  // 1. Mood Trend Score (0-25)
  if (today?.mood_trend !== null && today.mood_trend !== undefined) {
    // Negative trend = higher risk (mood_trend is slope, negative means declining)
    // A trend of -0.5 per day is concerning
    const trendScore = Math.min(
      WEIGHTS.moodTrend,
      Math.max(
        0,
        (-today.mood_trend / 0.5) * (WEIGHTS.moodTrend / 2) +
          WEIGHTS.moodTrend / 2,
      ),
    );
    totalScore += trendScore;
    factors.mood_trend = today.mood_trend;
    if (today.mood_trend < -0.2) {
      factorContributions.push({
        label: "Mood has been declining",
        value: Math.abs(today.mood_trend) * 10,
      });
    }
  }

  // 2. Mood Volatility Score (0-15)
  if (today?.mood_variance !== null && today.mood_variance !== undefined) {
    // High variance = higher risk (variance > 2 is concerning)
    const volatilityScore = Math.min(
      WEIGHTS.moodVolatility,
      (today.mood_variance / 4) * WEIGHTS.moodVolatility,
    );
    totalScore += volatilityScore;
    factors.mood_volatility = today.mood_variance;
    if (today.mood_variance > 2) {
      factorContributions.push({
        label: "Mood has been variable",
        value: today.mood_variance * 3,
      });
    }
  }

  // 3. Engagement Score (0-15)
  const avgRecentSessions =
    recent.reduce((sum, s) => sum + s.app_sessions, 0) / recent.length;
  if (baseline.avg_app_sessions > 0) {
    const engagementDrop =
      (baseline.avg_app_sessions - avgRecentSessions) /
      baseline.avg_app_sessions;
    if (engagementDrop > 0.2) {
      const engagementScore = Math.min(WEIGHTS.engagement, engagementDrop * 30);
      totalScore += engagementScore;
      factors.app_engagement = -engagementDrop * 10;
      factorContributions.push({
        label: "Less active in the app lately",
        value: engagementDrop * 15,
      });
    }
  }

  // 4. Sleep Score (0-15) - from biometric data if available
  if (
    biometrics?.sleep_quality_score !== null &&
    biometrics?.sleep_quality_score !== undefined
  ) {
    // sleep_quality_score is 0-1, lower is worse
    const sleepScore = Math.min(
      WEIGHTS.sleep,
      (1 - biometrics.sleep_quality_score) * WEIGHTS.sleep,
    );
    totalScore += sleepScore;
    factors.sleep_quality = (biometrics.sleep_quality_score - 0.5) * 10; // Relative to neutral
    if (biometrics.sleep_quality_score < 0.5) {
      factorContributions.push({
        label: "Sleep quality has dropped",
        value: (1 - biometrics.sleep_quality_score) * 10,
      });
    }
  }

  // 5. Biometric Score - HRV (0-15)
  if (
    biometrics?.hrv_average_ms !== null &&
    biometrics?.hrv_average_ms !== undefined &&
    baseline.avg_hrv > 0
  ) {
    const hrvDropPercent =
      (baseline.avg_hrv - biometrics.hrv_average_ms) / baseline.avg_hrv;
    if (hrvDropPercent > 0.1) {
      const hrvScore = Math.min(WEIGHTS.biometrics, hrvDropPercent * 50);
      totalScore += hrvScore;
      factors.hrv_drop = -hrvDropPercent * 10;
      factorContributions.push({
        label: "HRV has decreased",
        value: hrvDropPercent * 20,
      });
    }
  }

  // 6. Social Score (0-10)
  const avgRecentPosts =
    recent.reduce((sum, s) => sum + s.circle_posts, 0) / recent.length;
  if (avgRecentPosts < 0.2 && baseline.avg_social_score > 10) {
    // Social withdrawal when user was previously active
    const socialScore = Math.min(WEIGHTS.social, 5);
    totalScore += socialScore;
    factors.social_engagement = -5;
    factorContributions.push({
      label: "Social activity has dropped",
      value: 5,
    });
  }

  // 7. Streak Status (0-5)
  if (today?.streak_broken_today) {
    totalScore += WEIGHTS.streak;
    factors.streak_broken = true;
    factorContributions.push({
      label: "Quest streak was broken",
      value: WEIGHTS.streak,
    });
  }

  // 8. Days since chat (consecutive days from today with no chat)
  let daysSinceChat = 0;
  // Count from most recent (end) backwards
  for (let i = recent.length - 1; i >= 0; i--) {
    if (recent[i].chat_messages_sent === 0) {
      daysSinceChat++;
    } else {
      break; // Stop at first day with chat activity
    }
  }
  if (daysSinceChat >= 3) {
    factors.days_since_chat = daysSinceChat;
    factorContributions.push({
      label: "Haven't chatted in a while",
      value: daysSinceChat,
    });
  }

  // Normalize to 0-100
  const normalizedScore = Math.min(100, Math.round(totalScore));

  // Get top 3 factors
  const topFactors = factorContributions
    .sort((a, b) => b.value - a.value)
    .slice(0, 3)
    .map((f) => f.label);

  // Calculate confidence based on data availability
  const dataPoints = [
    today?.mood_average !== null,
    today?.mood_trend !== null,
    today?.mood_variance !== null,
    today?.app_sessions > 0,
    biometrics?.sleep_quality_score !== null,
    biometrics?.hrv_average_ms !== null,
    signals.length >= 7,
  ].filter(Boolean).length;
  const confidence = Math.round((dataPoints / 7) * 100) / 100;

  return {
    score: normalizedScore,
    factors,
    topFactors,
    confidence,
  };
}

/**
 * Classify risk level from score
 */
export function classifyRiskLevel(
  score: number,
): "low" | "medium" | "high" | "crisis" {
  if (score >= 76) return "crisis";
  if (score >= 51) return "high";
  if (score >= 26) return "medium";
  return "low";
}

/**
 * Predict 7-day trend direction
 */
export function predictTrend(
  signals: DailySignals[],
): "improving" | "stable" | "declining" {
  if (signals.length < 3) return "stable";

  const recentMoods = signals.slice(-7).map((s) => s.mood_average || 5);
  if (recentMoods.length < 3) return "stable";

  // Simple linear regression slope
  const n = recentMoods.length;
  let sumX = 0,
    sumY = 0,
    sumXY = 0,
    sumX2 = 0;
  for (let i = 0; i < n; i++) {
    sumX += i;
    sumY += recentMoods[i];
    sumXY += i * recentMoods[i];
    sumX2 += i * i;
  }

  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);

  if (slope > 0.1) return "improving";
  if (slope < -0.1) return "declining";
  return "stable";
}

/**
 * Predict 24h mood based on trend
 */
export function predictMood24h(signals: DailySignals[]): number | null {
  if (signals.length < 3) return null;

  const recentMoods = signals
    .slice(-3)
    .map((s) => s.mood_average)
    .filter((m) => m !== null) as number[];
  if (recentMoods.length < 2) return null;

  // Simple extrapolation from trend
  const lastMood = recentMoods[recentMoods.length - 1];
  const trend = recentMoods[recentMoods.length - 1] - recentMoods[0];
  const avgTrendPerDay = trend / (recentMoods.length - 1);

  const predicted = Math.max(1, Math.min(10, lastMood + avgTrendPerDay));
  return Math.round(predicted * 10) / 10;
}

/**
 * Get intervention type based on risk level
 */
export function getInterventionType(
  riskLevel: "low" | "medium" | "high" | "crisis",
): "gentle_nudge" | "active_checkin" | "crisis_protocol" | null {
  switch (riskLevel) {
    case "crisis":
      return "crisis_protocol";
    case "high":
      return "active_checkin";
    case "medium":
      return "gentle_nudge";
    default:
      return null;
  }
}

/**
 * Get intervention message template based on type
 */
export function getInterventionMessage(
  type: "gentle_nudge" | "active_checkin" | "crisis_protocol",
  topFactors: string[],
): string {
  const factorMention =
    topFactors.length > 0 ? ` I noticed ${topFactors[0].toLowerCase()}.` : "";

  switch (type) {
    case "crisis_protocol":
      return `I'm concerned about you and want to make sure you're safe. Would you like to talk or connect with support resources?`;
    case "active_checkin":
      return `Hey, I noticed things have been tough lately.${factorMention} I'm here for you – want to check in together?`;
    case "gentle_nudge":
      return `Hi! Just checking in.${factorMention} Remember, I'm always here if you want to talk or do a quick breathing exercise.`;
  }
}

/**
 * Get suggested actions based on risk level and factors
 */
export function getSuggestedActions(
  riskLevel: "low" | "medium" | "high" | "crisis",
  factors: RiskFactors,
): string[] {
  const actions: string[] = [];

  if (riskLevel === "crisis") {
    actions.push("crisis_line");
    actions.push("chat");
    actions.push("breathing_exercise");
    return actions;
  }

  if (factors.sleep_quality !== undefined && factors.sleep_quality < 0) {
    actions.push("sleep_meditation");
  }

  if (factors.mood_volatility !== undefined && factors.mood_volatility > 2) {
    actions.push("grounding_exercise");
  }

  actions.push("breathing_exercise");
  actions.push("chat");

  if (
    factors.social_engagement !== undefined &&
    factors.social_engagement < 0
  ) {
    actions.push("circle_checkin");
  }

  return actions.slice(0, 3); // Max 3 suggestions
}
