// Signal Detection Algorithms for Autonomous Wellness Agent
// Detects patterns: mood_decline, activity_drop, streak_risk, inactivity, positive_momentum

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface SignalDetectionResult {
  type: SignalType;
  severity: "low" | "medium" | "high" | "critical";
  confidence: number;
  evidence: SignalEvidence;
}

export type SignalType =
  | "mood_decline"
  | "mood_improvement"
  | "activity_drop"
  | "streak_risk"
  | "inactivity"
  | "stress_spike"
  | "positive_momentum";

export interface SignalEvidence {
  dataPoints: EvidencePoint[];
  trend: TrendInfo | null;
  comparison: ComparisonInfo | null;
}

export interface EvidencePoint {
  metric: string;
  value: number;
  timestamp: string;
  context?: string;
}

export interface TrendInfo {
  direction: "up" | "down" | "stable";
  magnitude: number;
  durationDays: number;
}

export interface ComparisonInfo {
  baseline: number;
  current: number;
  percentChange: number;
}

/**
 * Run all signal detectors for a user
 */
export async function detectSignals(
  supabase: SupabaseClient,
  userId: string,
  enabledSignals: string[],
): Promise<SignalDetectionResult[]> {
  const signals: SignalDetectionResult[] = [];

  const detectors = [
    { type: "mood_decline" as SignalType, fn: detectMoodTrend },
    { type: "activity_drop" as SignalType, fn: detectActivityDrop },
    { type: "streak_risk" as SignalType, fn: detectStreakRisk },
    { type: "inactivity" as SignalType, fn: detectInactivity },
    { type: "positive_momentum" as SignalType, fn: detectPositiveMomentum },
  ];

  const results = await Promise.all(
    detectors
      .filter((d) => enabledSignals.includes(d.type))
      .map((d) => d.fn(supabase, userId)),
  );

  for (const result of results) {
    if (result) {
      signals.push(result);
    }
  }

  return signals;
}

/**
 * Detect declining mood trend over 3+ days
 */
async function detectMoodTrend(
  supabase: SupabaseClient,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const { data: moods, error } = await supabase
    .from("moods")
    .select("score, notes, created_at")
    .eq("user_id", userId)
    .gte("created_at", sevenDaysAgo.toISOString())
    .order("created_at", { ascending: true });

  if (error || !moods || moods.length < 3) return null;

  // Calculate linear regression slope
  const n = moods.length;
  const xSum = moods.reduce((sum, _, i) => sum + i, 0);
  const ySum = moods.reduce((sum, m) => sum + m.score, 0);
  const xySum = moods.reduce((sum, m, i) => sum + i * m.score, 0);
  const x2Sum = moods.reduce((sum, _, i) => sum + i * i, 0);

  // Prevent division by zero
  const denominator = n * x2Sum - xSum * xSum;
  if (denominator === 0) return null;

  const slope = (n * xySum - xSum * ySum) / denominator;

  // Detect significant decline (slope < -0.3 points per entry)
  if (slope < -0.3) {
    const recentAvg = moods.slice(-3).reduce((sum, m) => sum + m.score, 0) / 3;
    const olderAvg =
      moods
        .slice(0, Math.min(3, moods.length))
        .reduce((sum, m) => sum + m.score, 0) / Math.min(3, moods.length);
    const percentDrop = ((olderAvg - recentAvg) / olderAvg) * 100;

    return {
      type: "mood_decline",
      severity: percentDrop > 30 ? "high" : percentDrop > 15 ? "medium" : "low",
      confidence: Math.min(0.95, 0.5 + n * 0.06),
      evidence: {
        dataPoints: moods.map((m) => ({
          metric: "mood_score",
          value: m.score,
          timestamp: m.created_at,
          context: m.notes?.substring(0, 50),
        })),
        trend: {
          direction: "down",
          magnitude: Math.abs(slope),
          durationDays: Math.ceil(n / 2),
        },
        comparison: {
          baseline: olderAvg,
          current: recentAvg,
          percentChange: -percentDrop,
        },
      },
    };
  }

  // Detect mood improvement
  if (slope > 0.3) {
    const recentAvg = moods.slice(-3).reduce((sum, m) => sum + m.score, 0) / 3;
    const olderAvg =
      moods
        .slice(0, Math.min(3, moods.length))
        .reduce((sum, m) => sum + m.score, 0) / Math.min(3, moods.length);
    const percentIncrease = ((recentAvg - olderAvg) / olderAvg) * 100;

    return {
      type: "mood_improvement",
      severity: "low",
      confidence: Math.min(0.9, 0.5 + n * 0.05),
      evidence: {
        dataPoints: moods.map((m) => ({
          metric: "mood_score",
          value: m.score,
          timestamp: m.created_at,
        })),
        trend: {
          direction: "up",
          magnitude: slope,
          durationDays: Math.ceil(n / 2),
        },
        comparison: {
          baseline: olderAvg,
          current: recentAvg,
          percentChange: percentIncrease,
        },
      },
    };
  }

  return null;
}

/**
 * Detect significant drop in exercise activity
 */
async function detectActivityDrop(
  supabase: SupabaseClient,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const fourteenDaysAgo = new Date();
  fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);

  const { data: activities, error } = await supabase
    .from("exercise_sessions")
    .select("duration_seconds, created_at")
    .eq("user_id", userId)
    .gte("created_at", fourteenDaysAgo.toISOString());

  if (error || !activities) return null;

  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const thisWeek = activities.filter(
    (a) => new Date(a.created_at) >= sevenDaysAgo,
  );
  const lastWeek = activities.filter(
    (a) => new Date(a.created_at) < sevenDaysAgo,
  );

  const thisWeekTotal = thisWeek.reduce(
    (sum, a) => sum + (a.duration_seconds || 0),
    0,
  );
  const lastWeekTotal = lastWeek.reduce(
    (sum, a) => sum + (a.duration_seconds || 0),
    0,
  );

  if (lastWeekTotal > 300) {
    // At least 5 min last week
    const dropPercent = ((lastWeekTotal - thisWeekTotal) / lastWeekTotal) * 100;

    if (dropPercent > 40) {
      return {
        type: "activity_drop",
        severity: dropPercent > 70 ? "high" : "medium",
        confidence: 0.75,
        evidence: {
          dataPoints: [
            {
              metric: "last_week_minutes",
              value: Math.round(lastWeekTotal / 60),
              timestamp: fourteenDaysAgo.toISOString(),
            },
            {
              metric: "this_week_minutes",
              value: Math.round(thisWeekTotal / 60),
              timestamp: new Date().toISOString(),
            },
          ],
          trend: {
            direction: "down",
            magnitude: dropPercent / 100,
            durationDays: 7,
          },
          comparison: {
            baseline: Math.round(lastWeekTotal / 60),
            current: Math.round(thisWeekTotal / 60),
            percentChange: -dropPercent,
          },
        },
      };
    }
  }

  return null;
}

/**
 * Detect streak at risk (significant streak, late in day, quest incomplete)
 */
async function detectStreakRisk(
  supabase: SupabaseClient,
  userId: string,
): Promise<SignalDetectionResult | null> {
  // Get user's current streak
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("current_streak, timezone")
    .eq("id", userId)
    .single();

  if (profileError || !profile || profile.current_streak < 3) return null;

  // Check today's quest status
  const today = new Date().toISOString().split("T")[0];
  const { data: todayQuest, error: questError } = await supabase
    .from("quests")
    .select("*")
    .eq("user_id", userId)
    .eq("assigned_date", today)
    .single();

  if (questError || !todayQuest || todayQuest.status === "completed")
    return null;

  // Check if it's getting late (after 18:00 user's local time)
  const now = new Date();
  const userTz = profile.timezone || "UTC";
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTz,
    hour: "numeric",
    hour12: false,
  });
  const hourOfDay = parseInt(formatter.format(now));

  if (hourOfDay >= 18) {
    return {
      type: "streak_risk",
      severity: profile.current_streak > 14 ? "high" : "medium",
      confidence: hourOfDay >= 20 ? 0.9 : 0.75,
      evidence: {
        dataPoints: [
          {
            metric: "current_streak",
            value: profile.current_streak,
            timestamp: now.toISOString(),
          },
          {
            metric: "hour_of_day",
            value: hourOfDay,
            timestamp: now.toISOString(),
            context: `Quest incomplete in ${userTz}`,
          },
        ],
        trend: null,
        comparison: null,
      },
    };
  }

  return null;
}

/**
 * Detect extended inactivity (3+ days no mood logs)
 */
async function detectInactivity(
  supabase: SupabaseClient,
  userId: string,
): Promise<SignalDetectionResult | null> {
  // Get last mood entry
  const { data: lastMood, error: moodError } = await supabase
    .from("moods")
    .select("created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  // Get last exercise session
  const { data: lastExercise, error: exerciseError } = await supabase
    .from("exercise_sessions")
    .select("created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  // Find most recent activity
  let lastActivity: Date | null = null;
  if (lastMood?.created_at) {
    lastActivity = new Date(lastMood.created_at);
  }
  if (lastExercise?.created_at) {
    const exerciseDate = new Date(lastExercise.created_at);
    if (!lastActivity || exerciseDate > lastActivity) {
      lastActivity = exerciseDate;
    }
  }

  if (!lastActivity) return null;

  const daysSinceActivity = Math.floor(
    (Date.now() - lastActivity.getTime()) / (1000 * 60 * 60 * 24),
  );

  if (daysSinceActivity >= 3) {
    return {
      type: "inactivity",
      severity: daysSinceActivity >= 7 ? "high" : "medium",
      confidence: 0.9,
      evidence: {
        dataPoints: [
          {
            metric: "days_since_activity",
            value: daysSinceActivity,
            timestamp: lastActivity.toISOString(),
          },
        ],
        trend: null,
        comparison: null,
      },
    };
  }

  return null;
}

/**
 * Detect positive momentum (good mood + exercises + streak)
 */
async function detectPositiveMomentum(
  supabase: SupabaseClient,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const [{ data: moods }, { data: exercises }, { data: profile }] =
    await Promise.all([
      supabase
        .from("moods")
        .select("score")
        .eq("user_id", userId)
        .gte("created_at", sevenDaysAgo.toISOString()),
      supabase
        .from("exercise_sessions")
        .select("id")
        .eq("user_id", userId)
        .gte("created_at", sevenDaysAgo.toISOString()),
      supabase
        .from("profiles")
        .select("current_streak")
        .eq("id", userId)
        .single(),
    ]);

  const avgMood = moods?.length
    ? moods.reduce((sum, m) => sum + m.score, 0) / moods.length
    : 0;
  const exerciseCount = exercises?.length || 0;
  const streak = profile?.current_streak || 0;

  // Positive momentum: good mood (>=3.5) + exercises (>=3/week) + streak (>=5)
  if (avgMood >= 3.5 && exerciseCount >= 3 && streak >= 5) {
    return {
      type: "positive_momentum",
      severity: "low",
      confidence: 0.75,
      evidence: {
        dataPoints: [
          {
            metric: "avg_mood",
            value: Math.round(avgMood * 10) / 10,
            timestamp: new Date().toISOString(),
          },
          {
            metric: "exercise_count",
            value: exerciseCount,
            timestamp: new Date().toISOString(),
          },
          {
            metric: "streak",
            value: streak,
            timestamp: new Date().toISOString(),
          },
        ],
        trend: {
          direction: "up",
          magnitude: 0.3,
          durationDays: 7,
        },
        comparison: null,
      },
    };
  }

  return null;
}

/**
 * Check for duplicate recent signals
 */
export async function isDuplicateSignal(
  supabase: SupabaseClient,
  userId: string,
  signalType: SignalType,
  hoursThreshold = 24,
): Promise<boolean> {
  const threshold = new Date();
  threshold.setHours(threshold.getHours() - hoursThreshold);

  const { data, error } = await supabase
    .from("agent_signals")
    .select("id")
    .eq("user_id", userId)
    .eq("signal_type", signalType)
    .eq("is_resolved", false)
    .gte("detected_at", threshold.toISOString())
    .limit(1);

  return !error && data && data.length > 0;
}
