/**
 * aggregate-wisdom Edge Function
 * Daily cron job to aggregate contributions into privacy-safe insights
 *
 * Security:
 * - Internal only (requires service role key in header)
 * - Batch processing to prevent OOM
 * - Memory limits enforced
 *
 * Schedule: 03:00 UTC daily
 * Minimum sample size: 10 users (MVP), 100 for production
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MIN_SAMPLE_SIZE = 10; // Set to 100 for production
const INSIGHT_TTL_HOURS = 24;
const BATCH_SIZE = 1000; // Process in batches to limit memory
const MAX_CONTRIBUTIONS_PER_RUN = 50000; // Safety limit

interface AggregationResult {
  insightsCreated: number;
  insightsUpdated: number;
  contributionsProcessed: number;
  errors: string[];
  batches: number;
}

serve(async (req) => {
  // Verify this is an internal call (cron or admin)
  const serviceKey = req.headers.get("X-Service-Key");
  const expectedKey = Deno.env.get("AGGREGATION_SERVICE_KEY");
  
  if (!expectedKey || serviceKey !== expectedKey) {
    // Also allow if called with service role directly
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.includes(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "")) {
      return new Response(
        JSON.stringify({ error: "UNAUTHORIZED", message: "Internal endpoint" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  const startTime = Date.now();
  const result: AggregationResult = {
    insightsCreated: 0,
    insightsUpdated: 0,
    contributionsProcessed: 0,
    errors: [],
    batches: 0,
  };

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Calculate date range (last 24 hours UTC)
    const now = new Date();
    const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const yesterdayStr = yesterday.toISOString();
    const nowStr = now.toISOString();

    console.log(`Aggregating contributions from ${yesterdayStr} to ${nowStr}`);

    // Get total count first
    const { count: totalCount } = await supabase
      .from("wisdom_contributions")
      .select("*", { count: "exact", head: true })
      .gte("contributed_at", yesterdayStr)
      .lt("contributed_at", nowStr);

    if (!totalCount || totalCount === 0) {
      console.log("No contributions to aggregate");
      return new Response(
        JSON.stringify({ ...result, message: "No contributions to aggregate" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // Safety check
    if (totalCount > MAX_CONTRIBUTIONS_PER_RUN) {
      console.warn(`Too many contributions (${totalCount}), limiting to ${MAX_CONTRIBUTIONS_PER_RUN}`);
    }

    const totalToProcess = Math.min(totalCount, MAX_CONTRIBUTIONS_PER_RUN);
    const numBatches = Math.ceil(totalToProcess / BATCH_SIZE);

    console.log(`Processing ${totalToProcess} contributions in ${numBatches} batches`);

    // Process in batches
    const allGroups: Record<string, Contribution[]> = {};
    
    for (let batch = 0; batch < numBatches; batch++) {
      const offset = batch * BATCH_SIZE;
      
      const { data: contributions, error: fetchError } = await supabase
        .from("wisdom_contributions")
        .select("*")
        .gte("contributed_at", yesterdayStr)
        .lt("contributed_at", nowStr)
        .range(offset, offset + BATCH_SIZE - 1)
        .order("contributed_at", { ascending: true });

      if (fetchError) {
        result.errors.push(`Batch ${batch} fetch error: ${fetchError.message}`);
        continue;
      }

      if (!contributions || contributions.length === 0) {
        continue;
      }

      result.contributionsProcessed += contributions.length;
      result.batches++;

      // Group contributions from this batch
      for (const contribution of contributions) {
        const relevantTags = (contribution.context_tags || [])
          .filter((t: string) =>
            t.startsWith("mood:") ||
            t.startsWith("exercise:") ||
            t.startsWith("pathway:") ||
            t.startsWith("category:") ||
            t.startsWith("time:")
          )
          .sort()
          .join(",");

        const key = `${contribution.contribution_type}:${relevantTags}`;

        if (!allGroups[key]) {
          allGroups[key] = [];
        }
        
        // Only keep essential data to limit memory
        allGroups[key].push({
          user_hash: contribution.user_hash,
          contribution_type: contribution.contribution_type,
          context_tags: contribution.context_tags,
          data_json: contribution.data_json,
        });
      }

      // Clear batch from memory
      contributions.length = 0;
    }

    console.log(`Grouped into ${Object.keys(allGroups).length} categories`);

    // Generate insights for each group with sufficient samples
    for (const [key, group] of Object.entries(allGroups)) {
      // Count unique user hashes
      const uniqueUsers = new Set(group.map((c) => c.user_hash));
      const sampleSize = uniqueUsers.size;

      if (sampleSize < MIN_SAMPLE_SIZE) {
        continue;
      }

      try {
        const insight = generateInsight(key, group, sampleSize);
        if (insight) {
          const { error: upsertError } = await supabase
            .from("wisdom_insights")
            .upsert(insight, {
              onConflict: "insight_type,context_tags,valid_from",
            });

          if (upsertError) {
            result.errors.push(`Insight upsert for ${key}: ${upsertError.code}`);
          } else {
            result.insightsCreated++;
          }
        }
      } catch (e) {
        result.errors.push(`Insight generation for ${key}: ${(e as Error).message}`);
      }
    }

    // Generate "not alone" insights for mood patterns
    await generateNotAloneInsights(supabase, contributions, result);

    // Update aggregate stats
    await updateAggregateStats(supabase, contributions, result);

    // Cleanup old contributions (older than 90 days)
    const ninetyDaysAgo = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
    const { error: cleanupError } = await supabase
      .from("wisdom_contributions")
      .delete()
      .lt("contributed_at", ninetyDaysAgo.toISOString());

    if (cleanupError) {
      result.errors.push(`Cleanup: ${cleanupError.code}`);
    }

    const duration = Date.now() - startTime;
    console.log(`Aggregation complete in ${duration}ms:`, result);

    return new Response(JSON.stringify({ ...result, durationMs: duration }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Aggregation error:", (error as Error).message);
    return new Response(
      JSON.stringify({ error: "AGGREGATION_FAILED", message: "Internal error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

interface Contribution {
  user_hash: string;
  contribution_type: string;
  context_tags: string[];
  data_json: Record<string, unknown>;
}

/**
 * Groups contributions by type and common context tags
 */
function groupContributions(
  contributions: Contribution[],
): Record<string, Contribution[]> {
  const groups: Record<string, Contribution[]> = {};

  for (const contribution of contributions) {
    // Create group key from type + mood/exercise/pathway tags
    const relevantTags = contribution.context_tags
      .filter(
        (t) =>
          t.startsWith("mood:") ||
          t.startsWith("exercise:") ||
          t.startsWith("pathway:") ||
          t.startsWith("category:") ||
          t.startsWith("time:"),
      )
      .sort()
      .join(",");

    const key = `${contribution.contribution_type}:${relevantTags}`;

    if (!groups[key]) {
      groups[key] = [];
    }
    groups[key].push(contribution);
  }

  return groups;
}

/**
 * Generates an insight from a group of contributions
 */
function generateInsight(
  key: string,
  contributions: Contribution[],
  sampleSize: number,
): Record<string, unknown> | null {
  const parts = key.split(":");
  const type = parts[0];
  const tags = parts.slice(1).join(":").split(",").filter(Boolean);

  const now = new Date();
  const validUntil = new Date(
    now.getTime() + INSIGHT_TTL_HOURS * 60 * 60 * 1000,
  );

  // Calculate aggregate data and confidence
  let aggregateData: Record<string, unknown> = {};
  let insightContent = "";
  let confidenceScore = 0.5;

  if (type === "mood_pattern") {
    const moodScores = contributions
      .map((c) => c.data_json.moodScore as number)
      .filter((s) => typeof s === "number");

    const avgMood = moodScores.reduce((a, b) => a + b, 0) / moodScores.length;
    const variance = calculateVariance(moodScores);

    aggregateData = {
      averageMood: Math.round(avgMood * 100) / 100,
      variance: Math.round(variance * 100) / 100,
      count: moodScores.length,
    };

    confidenceScore = calculateConfidence(sampleSize, variance);

    const moodLevel =
      avgMood <= 2 ? "challenging" : avgMood <= 3 ? "moderate" : "positive";
    insightContent = `${sampleSize.toLocaleString()}+ users are having a ${moodLevel} day`;
  } else if (type === "exercise_effectiveness") {
    const ratings = contributions
      .map((c) => c.data_json.effectivenessRating as number)
      .filter((r) => typeof r === "number");

    const avgRating = ratings.reduce((a, b) => a + b, 0) / ratings.length;
    const highRatingPct = Math.round(
      (ratings.filter((r) => r >= 4).length / ratings.length) * 100,
    );
    const variance = calculateVariance(ratings);

    const exerciseTag = tags.find((t) => t.startsWith("exercise:"));
    const exerciseType = exerciseTag
      ? exerciseTag.split(":")[1]
      : "this exercise";

    aggregateData = {
      averageRating: Math.round(avgRating * 100) / 100,
      highRatingPercentage: highRatingPct,
      count: ratings.length,
    };

    confidenceScore = calculateConfidence(sampleSize, variance);
    insightContent = `${highRatingPct}% of users found ${exerciseType} helpful`;
  } else if (type === "pathway_progress") {
    const phases = contributions.map((c) => c.data_json.phaseNumber as number);
    const avgPhase = phases.reduce((a, b) => a + b, 0) / phases.length;

    const pathwayTag = tags.find((t) => t.startsWith("pathway:"));
    const pathwayType = pathwayTag ? pathwayTag.split(":")[1] : "this pathway";

    aggregateData = {
      averagePhase: Math.round(avgPhase * 10) / 10,
      count: phases.length,
    };

    confidenceScore = calculateConfidence(sampleSize, 1.0);
    insightContent = `${sampleSize.toLocaleString()}+ users are progressing through ${pathwayType}`;
  } else {
    // Generic insight
    aggregateData = { count: contributions.length };
    confidenceScore = calculateConfidence(sampleSize, 1.0);
    insightContent = `${sampleSize.toLocaleString()}+ users contributed to community wisdom`;
  }

  return {
    insight_type:
      type === "mood_pattern"
        ? "not_alone"
        : type === "exercise_effectiveness"
          ? "exercise_effectiveness"
          : type === "pathway_progress"
            ? "milestone"
            : "trend",
    context_tags: tags,
    insight_content: insightContent,
    confidence_score: Math.round(confidenceScore * 100) / 100,
    sample_size: sampleSize,
    aggregate_data: aggregateData,
    valid_from: now.toISOString().split("T")[0], // Date only for uniqueness
    valid_until: validUntil.toISOString(),
  };
}

/**
 * Generates "not alone" insights for low mood patterns
 */
async function generateNotAloneInsights(
  supabase: ReturnType<typeof createClient>,
  contributions: Contribution[],
  result: AggregationResult,
): Promise<void> {
  const moodContributions = contributions.filter(
    (c) =>
      c.contribution_type === "mood_pattern" &&
      c.context_tags.includes("mood:low"),
  );

  const uniqueLowMoodUsers = new Set(moodContributions.map((c) => c.user_hash));
  const sampleSize = uniqueLowMoodUsers.size;

  if (sampleSize >= MIN_SAMPLE_SIZE) {
    const now = new Date();
    const validUntil = new Date(
      now.getTime() + INSIGHT_TTL_HOURS * 60 * 60 * 1000,
    );

    // Group by time of day
    const timeGroups: Record<string, Set<string>> = {
      morning: new Set(),
      afternoon: new Set(),
      evening: new Set(),
      night: new Set(),
    };

    for (const c of moodContributions) {
      const timeTag = c.context_tags.find((t) => t.startsWith("time:"));
      if (timeTag) {
        const time = timeTag.split(":")[1];
        if (timeGroups[time]) {
          timeGroups[time].add(c.user_hash);
        }
      }
    }

    // Create time-specific "not alone" insights
    for (const [time, users] of Object.entries(timeGroups)) {
      if (users.size >= MIN_SAMPLE_SIZE) {
        const { error } = await supabase.from("wisdom_insights").upsert(
          {
            insight_type: "not_alone",
            context_tags: ["mood:low", `time:${time}`],
            insight_content: `${users.size.toLocaleString()}+ others are feeling this way this ${time} too`,
            confidence_score: 0.9,
            sample_size: users.size,
            aggregate_data: { timeOfDay: time, count: users.size },
            valid_from: now.toISOString().split("T")[0],
            valid_until: validUntil.toISOString(),
          },
          { onConflict: "insight_type,context_tags,valid_from" },
        );

        if (!error) {
          result.insightsCreated++;
        }
      }
    }
  }
}

/**
 * Updates community aggregate stats
 */
async function updateAggregateStats(
  supabase: ReturnType<typeof createClient>,
  contributions: Contribution[],
  result: AggregationResult,
): Promise<void> {
  const today = new Date().toISOString().split("T")[0];

  // Calculate daily mood stats
  const moodContributions = contributions.filter(
    (c) => c.contribution_type === "mood_pattern",
  );
  const uniqueMoodUsers = new Set(moodContributions.map((c) => c.user_hash));

  if (uniqueMoodUsers.size >= MIN_SAMPLE_SIZE) {
    const moodScores = moodContributions
      .map((c) => c.data_json.moodScore as number)
      .filter((s) => typeof s === "number");

    const distribution = {
      low: moodScores.filter((s) => s <= 2).length,
      medium: moodScores.filter((s) => s === 3).length,
      high: moodScores.filter((s) => s >= 4).length,
    };

    const avgMood = moodScores.reduce((a, b) => a + b, 0) / moodScores.length;

    const { error } = await supabase.from("community_aggregate_stats").upsert(
      {
        stat_date: today,
        stat_type: "daily_mood",
        category: null,
        stat_data: {
          averageMood: Math.round(avgMood * 100) / 100,
          distribution,
          count: moodScores.length,
        },
        sample_size: uniqueMoodUsers.size,
      },
      { onConflict: "stat_date,stat_type,category" },
    );

    if (error) {
      result.errors.push(`Failed to update daily_mood stats: ${error.message}`);
    }
  }

  // Calculate exercise effectiveness stats
  const exerciseContributions = contributions.filter(
    (c) => c.contribution_type === "exercise_effectiveness",
  );

  // Group by exercise type
  const exerciseGroups: Record<
    string,
    { ratings: number[]; users: Set<string> }
  > = {};
  for (const c of exerciseContributions) {
    const exerciseType = c.data_json.exerciseType as string;
    if (!exerciseGroups[exerciseType]) {
      exerciseGroups[exerciseType] = { ratings: [], users: new Set() };
    }
    exerciseGroups[exerciseType].ratings.push(
      c.data_json.effectivenessRating as number,
    );
    exerciseGroups[exerciseType].users.add(c.user_hash);
  }

  for (const [exerciseType, data] of Object.entries(exerciseGroups)) {
    if (data.users.size >= MIN_SAMPLE_SIZE) {
      const avgRating =
        data.ratings.reduce((a, b) => a + b, 0) / data.ratings.length;
      const helpfulPct = Math.round(
        (data.ratings.filter((r) => r >= 4).length / data.ratings.length) * 100,
      );

      const { error } = await supabase.from("community_aggregate_stats").upsert(
        {
          stat_date: today,
          stat_type: "exercise_effectiveness",
          category: exerciseType,
          stat_data: {
            averageRating: Math.round(avgRating * 100) / 100,
            helpfulPercentage: helpfulPct,
            count: data.ratings.length,
          },
          sample_size: data.users.size,
        },
        { onConflict: "stat_date,stat_type,category" },
      );

      if (error) {
        result.errors.push(
          `Failed to update exercise stats for ${exerciseType}: ${error.message}`,
        );
      }
    }
  }
}

/**
 * Calculates variance of a number array
 */
function calculateVariance(values: number[]): number {
  if (values.length === 0) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const squaredDiffs = values.map((v) => Math.pow(v - mean, 2));
  return squaredDiffs.reduce((a, b) => a + b, 0) / values.length;
}

/**
 * Calculates confidence score based on sample size and variance
 */
function calculateConfidence(sampleSize: number, variance: number): number {
  // Size score: caps at 1.0 for 1000+ samples
  const sizeScore = Math.min(sampleSize / 1000, 1.0);
  // Variance score: lower variance = higher confidence
  const varianceScore = 1.0 - Math.min(variance / 10, 1.0);
  // Weighted average (size is more important)
  return sizeScore * 0.6 + varianceScore * 0.4;
}
