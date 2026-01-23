/**
 * calculate-social-vitality Edge Function
 *
 * Scheduled: Daily at 00:05 UTC (cron job)
 * Purpose: Calculate Social Vitality Index (0-100) for all active users
 *
 * Algorithm:
 * 1. Fetch interaction metrics from past 24 hours
 * 2. Calculate 4 components (0-25 each):
 *    - Interaction Frequency (message count)
 *    - Interaction Depth (length + response time)
 *    - Reciprocity (give/receive balance)
 *    - Diversity (unique people + circles)
 * 3. Calculate trend from past 7 days
 * 4. Upsert to social_vitality_scores table
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// Type definitions
interface InteractionMetric {
  messages_sent: number;
  messages_received: number;
  avg_response_time_minutes: number | null;
  avg_message_length: number | null;
  other_user_id: string;
  circle_id: string;
}

interface ScoreComponents {
  frequency: number;
  depth: number;
  reciprocity: number;
  diversity: number;
}

interface CalculationResult {
  success: boolean;
  userId: string;
  score?: number;
  error?: string;
}

serve(async (req) => {
  try {
    // Initialize Supabase client with service role key (bypasses RLS)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    console.log("[calculate-social-vitality] Starting daily calculation...");

    // Fetch all active users
    const { data: users, error: usersError } = await supabase
      .from("profiles")
      .select("id, created_at")
      .eq("active", true);

    if (usersError) {
      console.error(
        "[calculate-social-vitality] Error fetching users:",
        usersError,
      );
      return new Response(
        JSON.stringify({ success: false, error: usersError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(
      `[calculate-social-vitality] Processing ${users?.length || 0} users...`,
    );

    // Process each user
    const results: CalculationResult[] = [];
    for (const user of users || []) {
      const result = await calculateScoreForUser(
        supabase,
        user.id,
        user.created_at,
      );
      results.push(result);

      if (!result.success) {
        console.error(
          `[calculate-social-vitality] Failed for user ${user.id}:`,
          result.error,
        );
      }
    }

    const successCount = results.filter((r) => r.success).length;
    const failCount = results.filter((r) => !r.success).length;

    console.log(
      `[calculate-social-vitality] Completed: ${successCount} success, ${failCount} failed`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        processed: results.length,
        succeeded: successCount,
        failed: failCount,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("[calculate-social-vitality] Fatal error:", error);
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

/**
 * Calculate social vitality score for a single user
 */
async function calculateScoreForUser(
  supabase: any,
  userId: string,
  userCreatedAt: string,
): Promise<CalculationResult> {
  try {
    // Check if user has been active for 7+ days (minimum for scoring)
    const daysSinceSignup = Math.floor(
      (Date.now() - new Date(userCreatedAt).getTime()) / (1000 * 60 * 60 * 24),
    );

    if (daysSinceSignup < 7) {
      console.log(
        `[calculate-social-vitality] User ${userId}: Collecting baseline (day ${daysSinceSignup}/7)`,
      );
      return { success: true, userId, score: undefined }; // Skip, still in baseline period
    }

    // Fetch interaction metrics from past 24 hours (yesterday)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split("T")[0];

    const { data: metrics, error: metricsError } = await supabase
      .from("interaction_metrics")
      .select("*")
      .eq("user_id", userId)
      .eq("date", yesterdayStr);

    if (metricsError) {
      throw new Error(`Failed to fetch metrics: ${metricsError.message}`);
    }

    // Calculate 4 components
    const components = calculateComponents(metrics || []);
    const overallScore =
      components.frequency +
      components.depth +
      components.reciprocity +
      components.diversity;

    // Calculate trend from past 7 days
    const trend = await calculateTrend(supabase, userId);

    // Upsert score to database
    const { error: upsertError } = await supabase
      .from("social_vitality_scores")
      .upsert(
        {
          user_id: userId,
          date: yesterdayStr,
          overall_score: overallScore,
          trend,
          interaction_frequency: components.frequency,
          interaction_depth: components.depth,
          reciprocity: components.reciprocity,
          diversity: components.diversity,
        },
        {
          onConflict: "user_id,date",
        },
      );

    if (upsertError) {
      throw new Error(`Failed to upsert score: ${upsertError.message}`);
    }

    console.log(
      `[calculate-social-vitality] User ${userId}: Score ${overallScore}, Trend ${trend}`,
    );

    return { success: true, userId, score: overallScore };
  } catch (error) {
    return { success: false, userId, error: String(error) };
  }
}

/**
 * Calculate all 4 scoring components
 */
function calculateComponents(metrics: InteractionMetric[]): ScoreComponents {
  return {
    frequency: calculateFrequencyScore(metrics),
    depth: calculateDepthScore(metrics),
    reciprocity: calculateReciprocityScore(metrics),
    diversity: calculateDiversityScore(metrics),
  };
}

/**
 * Component 1: Interaction Frequency (0-25 points)
 * Based on total message count
 */
function calculateFrequencyScore(metrics: InteractionMetric[]): number {
  const totalMessages = metrics.reduce(
    (sum, m) => sum + m.messages_sent + m.messages_received,
    0,
  );

  // Cap at 50 messages to prevent manic episode false positives
  const cappedMessages = Math.min(totalMessages, 50);

  // Scoring rubric
  if (cappedMessages === 0) return 0;
  if (cappedMessages <= 5) return 10;
  if (cappedMessages <= 15) return 17;
  return 25; // 16+ messages
}

/**
 * Component 2: Interaction Depth (0-25 points)
 * Based on message length and response time
 */
function calculateDepthScore(metrics: InteractionMetric[]): number {
  if (metrics.length === 0) return 0;

  // Calculate average message length
  const lengths = metrics
    .map((m) => m.avg_message_length)
    .filter((l) => l !== null && l !== undefined) as number[];
  const avgLength =
    lengths.length > 0
      ? lengths.reduce((sum, l) => sum + l, 0) / lengths.length
      : 0;

  // Calculate average response time
  const responseTimes = metrics
    .map((m) => m.avg_response_time_minutes)
    .filter((rt) => rt !== null && rt !== undefined) as number[];
  const avgResponseTime =
    responseTimes.length > 0
      ? responseTimes.reduce((sum, rt) => sum + rt, 0) / responseTimes.length
      : Infinity;

  // Length contribution (0-12 points)
  let lengthScore = 0;
  if (avgLength < 20) lengthScore = 3;
  else if (avgLength < 50) lengthScore = 7;
  else if (avgLength < 100) lengthScore = 10;
  else lengthScore = 12;

  // Response time contribution (0-13 points)
  let responseScore = 0;
  if (avgResponseTime < 30)
    responseScore = 13; // Under 30 min
  else if (avgResponseTime < 120)
    responseScore = 9; // Under 2 hours
  else if (avgResponseTime < 480)
    responseScore = 5; // Under 8 hours
  else responseScore = 2;

  return Math.min(lengthScore + responseScore, 25);
}

/**
 * Component 3: Reciprocity (0-25 points)
 * Based on give/receive balance
 */
function calculateReciprocityScore(metrics: InteractionMetric[]): number {
  const totalSent = metrics.reduce((sum, m) => sum + m.messages_sent, 0);
  const totalReceived = metrics.reduce(
    (sum, m) => sum + m.messages_received,
    0,
  );

  if (totalSent + totalReceived === 0) return 0;

  // Calculate ratio (sent / received)
  const ratio = totalSent / Math.max(totalReceived, 1);

  // Deviation from perfect balance (1.0)
  const deviation = Math.abs(ratio - 1.0);

  // Scoring rubric
  if (deviation < 0.3) return 25; // Very balanced
  if (deviation < 0.6) return 18; // Slightly imbalanced
  if (deviation < 1.0) return 10; // Notably imbalanced
  return 5; // Severely imbalanced
}

/**
 * Component 4: Diversity of Connections (0-25 points)
 * Based on unique people and circles
 */
function calculateDiversityScore(metrics: InteractionMetric[]): number {
  const uniquePeople = new Set(metrics.map((m) => m.other_user_id)).size;
  const uniqueCircles = new Set(metrics.map((m) => m.circle_id)).size;

  // People diversity (0-15 points)
  let peopleScore = 0;
  if (uniquePeople === 0) peopleScore = 0;
  else if (uniquePeople === 1) peopleScore = 5;
  else if (uniquePeople === 2) peopleScore = 10;
  else peopleScore = 15; // 3+ people

  // Circle diversity (0-10 points)
  let circleScore = 0;
  if (uniqueCircles === 0) circleScore = 0;
  else if (uniqueCircles === 1) circleScore = 4;
  else circleScore = 10; // 2+ circles

  return Math.min(peopleScore + circleScore, 25);
}

/**
 * Calculate trend from past 7 days
 * Returns: 'improving' | 'stable' | 'declining' | 'plummeting'
 */
async function calculateTrend(supabase: any, userId: string): Promise<string> {
  // Fetch past 7 days of scores
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const { data: scores, error } = await supabase
    .from("social_vitality_scores")
    .select("overall_score, date")
    .eq("user_id", userId)
    .gte("date", sevenDaysAgo.toISOString().split("T")[0])
    .order("date", { ascending: true });

  if (error || !scores || scores.length < 7) {
    return "stable"; // Default if insufficient data
  }

  // Split into recent (D-1 to D-3) and older (D-5 to D-7)
  const recentScores = scores.slice(-3).map((s: any) => s.overall_score);
  const olderScores = scores.slice(0, 3).map((s: any) => s.overall_score);

  const recentAvg =
    recentScores.reduce((sum: number, s: number) => sum + s, 0) /
    recentScores.length;
  const olderAvg =
    olderScores.reduce((sum: number, s: number) => sum + s, 0) /
    olderScores.length;

  const delta = recentAvg - olderAvg;

  // Check if consistently improving or declining
  const isConsistentlyImproving = recentScores.every(
    (score: number, i: number) => i === 0 || score >= recentScores[i - 1],
  );
  const isConsistentlyDeclining = recentScores.every(
    (score: number, i: number) => i === 0 || score <= recentScores[i - 1],
  );

  // Classify trend
  if (delta >= 10 && isConsistentlyImproving) return "improving";
  if (delta <= -25 && isConsistentlyDeclining) return "plummeting";
  if (delta <= -10 && isConsistentlyDeclining) return "declining";
  return "stable";
}
