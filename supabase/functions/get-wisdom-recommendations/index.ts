/**
 * get-wisdom-recommendations Edge Function
 * Fetches personalized insights based on user context
 *
 * Security:
 * - Rate limited: 20 requests per hour per user
 * - Context tags sanitized
 * - No user data exposed in logs
 *
 * Returns:
 * - "Not alone" insights matching user's current state
 * - Top strategies for their category
 * - Trend insights
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Rate limiting configuration
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_MAX_REQUESTS = 20;
const rateLimitCache = new Map<string, { count: number; resetAt: number }>();

const corsHeaders = {
  "Access-Control-Allow-Origin":
    Deno.env.get("ALLOWED_ORIGIN") || "https://getmindfriend.app",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Allowed context tag prefixes (whitelist)
const ALLOWED_TAG_PREFIXES = [
  "mood:",
  "time:",
  "day:",
  "emotion:",
  "exercise:",
  "pathway:",
  "phase:",
  "category:",
  "type:",
  "effectiveness:",
  "goal:",
  "challenge:",
];

interface RecommendationRequest {
  contextTags: string[];
  moodScore?: number;
  emotion?: string;
  goals?: string[];
  challenges?: string[];
  limit?: number;
}

interface InsightResponse {
  id: string;
  insightType: string;
  content: string;
  contextTags: string[];
  confidenceScore: number;
  sampleSize: number;
  relevanceScore: number;
}

interface StrategyResponse {
  id: string;
  category: string;
  strategyText: string;
  context: string | null;
  helpfulPercentage: number;
  helpfulCount: number;
}

/**
 * Checks rate limit for a user
 */
function checkRateLimit(userId: string): {
  allowed: boolean;
  remaining: number;
} {
  const now = Date.now();
  const key = `recs:${userId}`;

  let entry = rateLimitCache.get(key);

  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };
    rateLimitCache.set(key, entry);
  }

  if (entry.count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false, remaining: 0 };
  }

  entry.count++;
  return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - entry.count };
}

/**
 * Sanitizes context tags to prevent injection
 */
function sanitizeContextTags(tags: string[]): string[] {
  if (!Array.isArray(tags)) return [];
  return tags
    .filter((tag) => {
      if (typeof tag !== "string") return false;
      if (tag.length === 0 || tag.length > 50) return false;
      if (!ALLOWED_TAG_PREFIXES.some((prefix) => tag.startsWith(prefix)))
        return false;
      if (/[<>"'\\;]/.test(tag)) return false;
      const value = tag.split(":")[1] || "";
      if (!/^[a-z0-9_]+$/.test(value)) return false;
      return true;
    })
    .slice(0, 20);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "UNAUTHORIZED", message: "Invalid token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check rate limit
    const rateLimit = checkRateLimit(user.id);
    if (!rateLimit.allowed) {
      return new Response(
        JSON.stringify({
          error: "RATE_LIMITED",
          message: "Too many requests. Please try again later.",
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if user has opted in to receive recommendations
    const { data: consent } = await supabase
      .from("wisdom_consent")
      .select("receive_recommendations")
      .eq("user_id", user.id)
      .single();

    if (!consent || !consent.receive_recommendations) {
      // Silent opt-out: return empty response
      return new Response(
        JSON.stringify({
          insights: [],
          strategies: [],
          message:
            "Recommendations disabled. Enable in Settings > Community Wisdom Privacy",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: RecommendationRequest = await req.json();
    const {
      contextTags = [],
      moodScore,
      emotion,
      goals = [],
      challenges = [],
      limit = 5,
    } = body;

    // Validate and sanitize inputs
    const sanitizedTags = sanitizeContextTags(contextTags);
    const sanitizedGoals = (goals || [])
      .filter((g) => typeof g === "string" && g.length <= 50)
      .slice(0, 5);
    const sanitizedChallenges = (challenges || [])
      .filter((c) => typeof c === "string" && c.length <= 50)
      .slice(0, 5);
    const sanitizedLimit = Math.min(Math.max(1, limit || 5), 20);
    const sanitizedEmotion =
      emotion && typeof emotion === "string" && emotion.length <= 30
        ? emotion.replace(/[^a-zA-Z]/g, "").toLowerCase()
        : undefined;
    const sanitizedMoodScore =
      typeof moodScore === "number" && moodScore >= 1 && moodScore <= 5
        ? moodScore
        : undefined;

    // Build enriched context tags
    const enrichedTags = buildEnrichedTags(
      sanitizedTags,
      sanitizedMoodScore,
      sanitizedEmotion,
      sanitizedGoals,
      sanitizedChallenges,
    );

    // Fetch matching insights
    const insights = await fetchMatchingInsights(
      supabase,
      enrichedTags,
      sanitizedLimit,
    );

    // Calculate relevance scores and filter low-relevance insights
    const scoredInsights = insights
      .map((insight) => ({
        ...insight,
        relevanceScore: calculateRelevance(insight, enrichedTags),
      }))
      .filter((i) => i.relevanceScore >= 0.3)
      .sort((a, b) => b.relevanceScore - a.relevanceScore)
      .slice(0, sanitizedLimit);

    // Fetch top strategies for the user's category
    const categoryTag = enrichedTags.find((t) => t.startsWith("category:"));
    const category = categoryTag ? categoryTag.split(":")[1] : null;
    const strategies = await fetchTopStrategies(supabase, category, 3);

    // Record recommendations shown (for feedback tracking)
    await recordRecommendations(supabase, user.id, scoredInsights);

    // Format response
    const response = {
      notAloneInsight:
        scoredInsights.find((i) => i.insightType === "not_alone") || null,
      insights: scoredInsights.map((i) => ({
        id: i.id,
        insightType: i.insightType,
        content: i.insightContent,
        contextTags: i.contextTags,
        confidenceScore: i.confidenceScore,
        sampleSize: i.sampleSize,
        relevanceScore: i.relevanceScore,
      })),
      strategies: strategies.map((s) => ({
        id: s.id,
        category: s.category,
        strategyText: s.strategy_text,
        context: s.context,
        helpfulPercentage: calculateHelpfulPercentage(
          s.helpful_count,
          s.not_helpful_count,
        ),
        helpfulCount: s.helpful_count,
      })),
      trendInsight:
        scoredInsights.find((i) => i.insightType === "trend") || null,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Get recommendations error:", error);
    return new Response(
      JSON.stringify({
        error: "INTERNAL_ERROR",
        message: "Failed to fetch recommendations",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Builds enriched context tags from user request
 */
function buildEnrichedTags(
  contextTags: string[],
  moodScore?: number,
  emotion?: string,
  goals?: string[],
  challenges?: string[],
): string[] {
  const tags = new Set<string>(contextTags);

  // Add mood-based tags
  if (moodScore !== undefined) {
    if (moodScore <= 2) {
      tags.add("mood:low");
    } else if (moodScore === 3) {
      tags.add("mood:medium");
    } else {
      tags.add("mood:high");
    }
  }

  if (emotion) {
    tags.add(`emotion:${emotion}`);

    // Map emotions to categories
    const emotionCategoryMap: Record<string, string> = {
      anxious: "anxiety",
      worried: "anxiety",
      nervous: "anxiety",
      sad: "depression",
      depressed: "depression",
      hopeless: "depression",
      stressed: "stress",
      overwhelmed: "overwhelm",
      angry: "anger",
      frustrated: "anger",
      lonely: "loneliness",
      isolated: "loneliness",
      grieving: "grief",
      tired: "sleep",
      exhausted: "sleep",
    };

    const category = emotionCategoryMap[emotion.toLowerCase()];
    if (category) {
      tags.add(`category:${category}`);
    }
  }

  // Add goal and challenge tags
  for (const goal of goals) {
    tags.add(`goal:${goal}`);
  }
  for (const challenge of challenges) {
    tags.add(`challenge:${challenge}`);
  }

  // Add time-based tags
  const hour = new Date().getUTCHours();
  if (hour >= 5 && hour < 12) {
    tags.add("time:morning");
  } else if (hour >= 12 && hour < 17) {
    tags.add("time:afternoon");
  } else if (hour >= 17 && hour < 21) {
    tags.add("time:evening");
  } else {
    tags.add("time:night");
  }

  return Array.from(tags);
}

/**
 * Fetches insights matching the user's context tags
 */
async function fetchMatchingInsights(
  supabase: ReturnType<typeof createClient>,
  contextTags: string[],
  limit: number,
): Promise<
  Array<{
    id: string;
    insightType: string;
    insightContent: string;
    contextTags: string[];
    confidenceScore: number;
    sampleSize: number;
    validFrom: string;
  }>
> {
  // Fetch insights that overlap with user's context tags
  const { data: insights, error } = await supabase
    .from("wisdom_insights")
    .select(
      "id, insight_type, insight_content, context_tags, confidence_score, sample_size, valid_from",
    )
    .or(`valid_until.is.null,valid_until.gt.${new Date().toISOString()}`)
    .order("confidence_score", { ascending: false })
    .limit(50); // Fetch more, then filter by relevance

  if (error || !insights) {
    console.error("Error fetching insights:", error);
    return [];
  }

  // Filter to insights with at least one matching tag
  return insights
    .filter((insight) => {
      const overlap = insight.context_tags.some((tag: string) =>
        contextTags.includes(tag),
      );
      return overlap;
    })
    .map((i) => ({
      id: i.id,
      insightType: i.insight_type,
      insightContent: i.insight_content,
      contextTags: i.context_tags,
      confidenceScore: i.confidence_score,
      sampleSize: i.sample_size,
      validFrom: i.valid_from,
    }));
}

/**
 * Calculates relevance score for an insight
 */
function calculateRelevance(
  insight: {
    contextTags: string[];
    confidenceScore: number;
    validFrom: string;
  },
  userContextTags: string[],
): number {
  // Tag overlap score
  const matchingTags = insight.contextTags.filter((tag) =>
    userContextTags.includes(tag),
  );
  const tagScore = matchingTags.length / Math.max(userContextTags.length, 1);

  // Recency score (decay over days)
  const daysSinceValid = Math.floor(
    (Date.now() - new Date(insight.validFrom).getTime()) /
      (24 * 60 * 60 * 1000),
  );
  const recencyScore = Math.max(0, 1.0 - daysSinceValid * 0.1);

  // Combine with confidence score
  const relevance =
    tagScore * 0.5 + insight.confidenceScore * 0.3 + recencyScore * 0.2;

  return Math.round(relevance * 100) / 100;
}

/**
 * Fetches top strategies for a category
 */
async function fetchTopStrategies(
  supabase: ReturnType<typeof createClient>,
  category: string | null,
  limit: number,
): Promise<
  Array<{
    id: string;
    category: string;
    strategy_text: string;
    context: string | null;
    helpful_count: number;
    not_helpful_count: number;
  }>
> {
  let query = supabase
    .from("community_strategies")
    .select(
      "id, category, strategy_text, context, helpful_count, not_helpful_count",
    )
    .eq("status", "approved")
    .order("helpful_count", { ascending: false })
    .limit(limit);

  if (category) {
    query = query.eq("category", category);
  }

  const { data: strategies, error } = await query;

  if (error || !strategies) {
    console.error("Error fetching strategies:", error);
    return [];
  }

  return strategies;
}

/**
 * Records which recommendations were shown (for feedback loop)
 */
async function recordRecommendations(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  insights: Array<{
    id: string;
    insightContent: string;
    relevanceScore: number;
    contextTags: string[];
  }>,
): Promise<void> {
  if (insights.length === 0) return;

  const records = insights.map((insight) => ({
    user_id: userId,
    insight_id: insight.id,
    content: insight.insightContent,
    relevance_score: insight.relevanceScore,
    context_tags: insight.contextTags,
    shown_at: new Date().toISOString(),
  }));

  const { error } = await supabase
    .from("wisdom_recommendations")
    .insert(records);

  if (error) {
    console.error("Error recording recommendations:", error);
  }
}

/**
 * Calculates helpful percentage
 */
function calculateHelpfulPercentage(
  helpful: number,
  notHelpful: number,
): number {
  const total = helpful + notHelpful;
  if (total === 0) return 0;
  return Math.round((helpful / total) * 100);
}
