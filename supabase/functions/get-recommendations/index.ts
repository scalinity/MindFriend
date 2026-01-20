// supabase/functions/get-recommendations/index.ts
// Smart Personalization: Get personalized content recommendations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface RecommendationRequest {
  contentType: string;
  context?: {
    currentMood?: string;
    timeOfDay?: string;
    recentActivity?: string;
  };
  limit?: number;
}

interface ScoredContent {
  contentId: string;
  contentType: string;
  relevanceScore: number;
  factors: Record<string, number>;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const contentType = body.contentType ?? "exercise";
    const context = body.context ?? {};
    const limit = Math.min(body.limit ?? 10, 50);

    // Get user preferences
    const { data: preferences } = await supabase
      .from("user_preference_profiles")
      .select("*")
      .eq("user_id", user.id)
      .single();

    // Get learned preferences
    const { data: learnedPrefs } = await supabase
      .from("learned_preferences")
      .select("*")
      .eq("user_id", user.id);

    // Get usage patterns
    const { data: patterns } = await supabase
      .from("usage_patterns")
      .select("*")
      .eq("user_id", user.id);

    // Get available content based on type
    const contentTable = getContentTable(contentType);
    const { data: content } = await supabase
      .from(contentTable)
      .select("*")
      .eq("is_active", true);

    if (!content || content.length === 0) {
      return new Response(JSON.stringify({ recommendations: [] }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Score and rank content
    const scoredContent = scoreContent(
      content,
      preferences,
      learnedPrefs ?? [],
      patterns ?? [],
      context,
    );

    // Sort by score and take top results
    const recommendations = scoredContent
      .sort((a, b) => b.relevanceScore - a.relevanceScore)
      .slice(0, limit);

    // Log recommendations (non-blocking)
    const logPromises = recommendations.map((rec, i) =>
      supabase.from("recommendation_logs").insert({
        user_id: user.id,
        recommendation_type: "personalized",
        content_type: contentType,
        content_id: rec.contentId,
        position: i + 1,
        relevance_score: rec.relevanceScore,
        personalization_factors: rec.factors,
        current_mood: context.currentMood ?? null,
        time_of_day: context.timeOfDay ?? null,
      }),
    );

    // Don't await - fire and forget
    Promise.all(logPromises).catch(console.error);

    return new Response(
      JSON.stringify({
        recommendations: recommendations.map((r) => ({
          contentId: r.contentId,
          score: r.relevanceScore,
          reasons: formatReasons(r.factors),
        })),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error getting recommendations:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function getContentTable(contentType: string): string {
  const tables: Record<string, string> = {
    exercise: "exercises",
    audio: "audio_tracks",
    micro_moment: "micro_moment_templates",
    quest: "quest_templates",
  };
  return tables[contentType] || "exercises";
}

function scoreContent(
  content: Array<Record<string, unknown>>,
  preferences: Record<string, unknown> | null,
  learnedPrefs: Array<Record<string, unknown>>,
  patterns: Array<Record<string, unknown>>,
  context?: Record<string, unknown>,
): ScoredContent[] {
  return content.map((item) => {
    const factors: Record<string, number> = {};
    let totalScore = 0.5; // Base score

    // Factor 1: Category preference
    const categoryPref = learnedPrefs.find(
      (p) =>
        p.preference_type === "category" && p.preference_key === item.category,
    );
    if (categoryPref && typeof categoryPref.preference_score === "number") {
      factors.category = categoryPref.preference_score;
      totalScore += (categoryPref.preference_score - 0.5) * 0.3;
    }

    // Factor 2: Length preference
    const itemDuration = item.duration_minutes as number | undefined;
    if (itemDuration) {
      const lengthBucket = getLengthBucket(itemDuration);
      const lengthPref = learnedPrefs.find(
        (p) =>
          p.preference_type === "content_length" &&
          p.preference_key === lengthBucket,
      );
      if (lengthPref && typeof lengthPref.preference_score === "number") {
        factors.length = lengthPref.preference_score;
        totalScore += (lengthPref.preference_score - 0.5) * 0.2;
      }
    }

    // Factor 3: Mood match
    const recommendedMoods = item.recommended_moods as string[] | undefined;
    if (
      context?.currentMood &&
      recommendedMoods?.includes(context.currentMood as string)
    ) {
      factors.mood_match = 0.8;
      totalScore += 0.15;
    }

    // Factor 4: Time of day appropriateness
    if (context?.timeOfDay) {
      const timeAppropriate = isTimeAppropriate(
        item,
        context.timeOfDay as string,
      );
      factors.time_appropriate = timeAppropriate ? 0.7 : 0.3;
      totalScore += timeAppropriate ? 0.1 : -0.1;
    }

    // Factor 5: Explicit preferences match
    if (preferences) {
      const prefCategories = preferences.preferred_categories as
        | string[]
        | undefined;
      if (prefCategories?.includes(item.category as string)) {
        factors.explicit_category = 0.9;
        totalScore += 0.1;
      }
    }

    // Factor 6: Time-based patterns
    const timePattern = patterns.find((p) => p.pattern_type === "daily_time");
    if (timePattern && context?.timeOfDay) {
      const patternData = timePattern.pattern_data as {
        slots?: Array<{ hour: number; score: number }>;
      };
      const currentHour = getCurrentHour(context.timeOfDay as string);
      const matchingSlot = patternData.slots?.find(
        (s) => Math.abs(s.hour - currentHour) <= 1,
      );
      if (matchingSlot) {
        factors.time_pattern = matchingSlot.score;
        totalScore += matchingSlot.score * 0.1;
      }
    }

    // Normalize score to 0-1
    totalScore = Math.max(0, Math.min(1, totalScore));

    return {
      contentId: item.id as string,
      contentType: (item.type as string) || "exercise",
      relevanceScore: totalScore,
      factors,
    };
  });
}

function getLengthBucket(minutes: number): string {
  if (minutes <= 3) return "micro";
  if (minutes <= 10) return "short";
  if (minutes <= 20) return "medium";
  return "long";
}

function getCurrentHour(timeOfDay: string): number {
  const hourMapping: Record<string, number> = {
    morning: 8,
    afternoon: 14,
    evening: 19,
    night: 22,
  };
  return hourMapping[timeOfDay] ?? 12;
}

function isTimeAppropriate(
  item: Record<string, unknown>,
  timeOfDay: string,
): boolean {
  const timeMapping: Record<string, string[]> = {
    morning: ["energizing", "focus", "gratitude", "morning"],
    afternoon: ["focus", "stress_relief", "movement"],
    evening: ["relaxation", "reflection", "gratitude"],
    night: ["sleep", "relaxation", "calming"],
  };

  const appropriateCategories = timeMapping[timeOfDay] || [];
  const category = item.category as string | undefined;
  const tags = item.tags as string[] | undefined;

  return appropriateCategories.some(
    (cat) =>
      category?.toLowerCase().includes(cat) ||
      tags?.some((t: string) => t.toLowerCase().includes(cat)),
  );
}

function formatReasons(factors: Record<string, number>): string[] {
  const reasons: string[] = [];

  if (factors.category > 0.6) reasons.push("Matches your preferred categories");
  if (factors.length > 0.6) reasons.push("Perfect length for you");
  if (factors.mood_match > 0.6) reasons.push("Great for your current mood");
  if (factors.time_appropriate > 0.6)
    reasons.push("Perfect for this time of day");
  if (factors.explicit_category > 0.6) reasons.push("In your favorites");
  if (factors.time_pattern > 0.5) reasons.push("Matches your usual schedule");

  return reasons.length > 0 ? reasons : ["Recommended for you"];
}
