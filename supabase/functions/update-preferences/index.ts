// supabase/functions/update-preferences/index.ts
// Smart Personalization: Update learned preferences from engagement events

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface EngagementEvent {
  contentType: string;
  contentId: string;
  eventType: "start" | "complete" | "skip" | "rate";
  durationSeconds?: number;
  completionPercentage?: number;
  rating?: number;
  skipReason?: string;
  contentAttributes: {
    category?: string;
    lengthMinutes?: number;
    difficulty?: string;
  };
}

interface PreferenceUpdate {
  type: string;
  key: string;
  engagement: boolean;
  completed: boolean;
  duration: number;
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
    const event: EngagementEvent = await req.json();

    // Validate event type
    const validEventTypes = ["start", "complete", "skip", "rate"];
    if (!validEventTypes.includes(event.eventType)) {
      return new Response(JSON.stringify({ error: "Invalid event type" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const now = new Date();
    const hour = now.getHours();
    const timeOfDay = getTimeOfDay(hour);
    const dayOfWeek = now.getDay();

    // Record the engagement
    await supabase.from("content_engagements").insert({
      user_id: user.id,
      content_type: event.contentType,
      content_id: event.contentId,
      duration_seconds: event.durationSeconds ?? null,
      completion_percentage: event.completionPercentage ?? null,
      completed: event.eventType === "complete",
      rating: event.rating ?? null,
      skipped: event.eventType === "skip",
      skip_reason: event.skipReason ?? null,
      time_of_day: timeOfDay,
      day_of_week: dayOfWeek,
      content_category: event.contentAttributes?.category ?? null,
      content_length_minutes: event.contentAttributes?.lengthMinutes ?? null,
      content_difficulty: event.contentAttributes?.difficulty ?? null,
    });

    // Update learned preferences based on engagement
    const preferencesToUpdate = extractPreferences(event);

    for (const pref of preferencesToUpdate) {
      await updateLearnedPreference(
        supabase,
        user.id,
        pref.type,
        pref.key,
        pref.engagement,
        pref.completed,
        pref.duration,
        event.rating,
      );
    }

    // Recalculate usage patterns periodically
    await maybeRecalculatePatterns(supabase, user.id);

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error updating preferences:", error);
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

function getTimeOfDay(hour: number): string {
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 21) return "evening";
  return "night";
}

function extractPreferences(event: EngagementEvent): PreferenceUpdate[] {
  const updates: PreferenceUpdate[] = [];
  const completed = event.eventType === "complete";
  const engaged = event.eventType !== "skip";

  // Category preference
  if (event.contentAttributes?.category) {
    updates.push({
      type: "category",
      key: event.contentAttributes.category,
      engagement: engaged,
      completed,
      duration: event.durationSeconds ?? 0,
    });
  }

  // Length preference
  if (event.contentAttributes?.lengthMinutes) {
    const lengthBucket = getLengthBucket(event.contentAttributes.lengthMinutes);
    updates.push({
      type: "content_length",
      key: lengthBucket,
      engagement: engaged,
      completed,
      duration: event.durationSeconds ?? 0,
    });
  }

  // Content type preference
  updates.push({
    type: "content_type",
    key: event.contentType,
    engagement: engaged,
    completed,
    duration: event.durationSeconds ?? 0,
  });

  // Time of day preference
  const now = new Date();
  updates.push({
    type: "time_of_day",
    key: getTimeOfDay(now.getHours()),
    engagement: engaged,
    completed,
    duration: event.durationSeconds ?? 0,
  });

  return updates;
}

function getLengthBucket(minutes: number): string {
  if (minutes <= 3) return "micro";
  if (minutes <= 10) return "short";
  if (minutes <= 20) return "medium";
  return "long";
}

async function updateLearnedPreference(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  prefType: string,
  prefKey: string,
  engaged: boolean,
  completed: boolean,
  duration: number,
  rating?: number,
) {
  // Get existing preference or create new
  const { data: existing } = await supabase
    .from("learned_preferences")
    .select("*")
    .eq("user_id", userId)
    .eq("preference_type", prefType)
    .eq("preference_key", prefKey)
    .single();

  if (existing) {
    // Update existing
    const newEngagementCount = existing.engagement_count + (engaged ? 1 : 0);
    const newCompletionCount = existing.completion_count + (completed ? 1 : 0);
    const newTotalDuration = existing.total_duration_seconds + duration;
    const newPositiveRatings =
      existing.positive_ratings + (rating !== undefined && rating >= 4 ? 1 : 0);
    const newNegativeRatings =
      existing.negative_ratings + (rating !== undefined && rating <= 2 ? 1 : 0);

    const engagementRate =
      newEngagementCount > 0 ? newCompletionCount / newEngagementCount : 0;

    // Calculate preference score using multiple signals
    const ratingSignal =
      newPositiveRatings + newNegativeRatings > 0
        ? newPositiveRatings / (newPositiveRatings + newNegativeRatings)
        : 0.5;

    const preferenceScore = engagementRate * 0.6 + ratingSignal * 0.4;

    // Confidence increases with more data points
    const confidenceScore = Math.min(1, newEngagementCount / 20);

    await supabase
      .from("learned_preferences")
      .update({
        engagement_count: newEngagementCount,
        completion_count: newCompletionCount,
        total_duration_seconds: newTotalDuration,
        positive_ratings: newPositiveRatings,
        negative_ratings: newNegativeRatings,
        engagement_rate: engagementRate,
        preference_score: preferenceScore,
        confidence_score: confidenceScore,
        last_interaction_at: new Date().toISOString(),
      })
      .eq("id", existing.id);
  } else {
    // Create new
    const engagementRate = completed ? 1 : 0;
    const preferenceScore = 0.5 + (completed ? 0.1 : -0.1);

    await supabase.from("learned_preferences").insert({
      user_id: userId,
      preference_type: prefType,
      preference_key: prefKey,
      engagement_count: engaged ? 1 : 0,
      completion_count: completed ? 1 : 0,
      total_duration_seconds: duration,
      positive_ratings: rating !== undefined && rating >= 4 ? 1 : 0,
      negative_ratings: rating !== undefined && rating <= 2 ? 1 : 0,
      engagement_rate: engagementRate,
      preference_score: preferenceScore,
      confidence_score: 0.05, // Low initial confidence
    });
  }
}

async function maybeRecalculatePatterns(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  // Check if patterns need recalculation (e.g., every 10 engagements)
  const { count } = await supabase
    .from("content_engagements")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId);

  if (count && count % 10 === 0) {
    // Trigger pattern recalculation
    await recalculateUsagePatterns(supabase, userId);
  }
}

async function recalculateUsagePatterns(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  // Get recent engagements
  const { data: engagements } = await supabase
    .from("content_engagements")
    .select("*")
    .eq("user_id", userId)
    .eq("completed", true)
    .order("created_at", { ascending: false })
    .limit(100);

  if (!engagements || engagements.length < 5) return;

  // Calculate daily time patterns
  const timeSlots: Record<number, number> = {};
  for (const eng of engagements) {
    const hour = new Date(eng.created_at).getHours();
    timeSlots[hour] = (timeSlots[hour] || 0) + 1;
  }

  const totalSessions = engagements.length;
  const dailyTimePattern = {
    slots: Object.entries(timeSlots)
      .map(([hour, count]) => ({
        hour: parseInt(hour),
        score: count / totalSessions,
        sessions: count,
      }))
      .sort((a, b) => b.score - a.score)
      .slice(0, 5),
  };

  await supabase.from("usage_patterns").upsert(
    {
      user_id: userId,
      pattern_type: "daily_time",
      pattern_data: dailyTimePattern,
      sample_size: totalSessions,
      confidence: Math.min(1, totalSessions / 50),
      valid_until: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    },
    {
      onConflict: "user_id,pattern_type",
    },
  );

  // Calculate weekly day patterns
  const daySlots: Record<number, number> = {};
  for (const eng of engagements) {
    const day = new Date(eng.created_at).getDay();
    daySlots[day] = (daySlots[day] || 0) + 1;
  }

  const weeklyDayPattern = {
    days: [0, 1, 2, 3, 4, 5, 6].map((day) => ({
      day,
      score: (daySlots[day] || 0) / totalSessions,
      sessions: daySlots[day] || 0,
    })),
  };

  await supabase.from("usage_patterns").upsert(
    {
      user_id: userId,
      pattern_type: "weekly_day",
      pattern_data: weeklyDayPattern,
      sample_size: totalSessions,
      confidence: Math.min(1, totalSessions / 50),
      valid_until: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    },
    {
      onConflict: "user_id,pattern_type",
    },
  );
}
