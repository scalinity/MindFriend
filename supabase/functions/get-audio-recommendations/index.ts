import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { errorResponse } from "../_shared/error-handler.ts";

interface RecommendationRequest {
  context?: string; // 'morning', 'evening', 'night', 'focus', 'relax'
  mood?: string; // 'anxious', 'stressed', 'calm', 'tired', 'energetic'
  category?: string;
  maxDuration?: number;
  limit?: number;
}

interface AudioTrackResult {
  id: string;
  title: string;
  slug: string;
  description: string | null;
  category: string;
  audio_duration_seconds: number;
  cover_image_url: string | null;
  is_premium: boolean;
  narrator_id: string | null;
  narrator: { id: string; name: string; avatar_url: string | null } | null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing auth header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const body: RecommendationRequest = await req.json();
    const limit = body.limit || 10;

    // Get user's subscription status
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .single();

    const isPremium = subscription?.status === "active";

    // Get user's recent playback
    const { data: recentPlayback } = await supabase
      .from("playback_sessions")
      .select("track_id, completed")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(20);

    const recentTrackIds = recentPlayback?.map((p) => p.track_id) || [];
    const completedTrackIds =
      recentPlayback?.filter((p) => p.completed).map((p) => p.track_id) || [];

    // Get user's favorites
    const { data: favorites } = await supabase
      .from("user_audio_favorites")
      .select("track_id")
      .eq("user_id", user.id);

    const favoriteTrackIds = favorites?.map((f) => f.track_id) || [];

    // Build recommendation query
    let query = supabase
      .from("audio_tracks")
      .select(
        `
          id,
          title,
          slug,
          description,
          category,
          audio_duration_seconds,
          cover_image_url,
          is_premium,
          narrator_id,
          average_rating,
          play_count,
          tags,
          mood_tags,
          time_of_day_tags,
          narrator:narrator_id(id, name, avatar_url)
        `,
      )
      .eq("is_active", true);

    // Filter by premium status
    if (!isPremium) {
      query = query.eq("is_premium", false);
    }

    // Filter by category if specified
    if (body.category) {
      query = query.eq("category", body.category);
    }

    // Filter by max duration
    if (body.maxDuration) {
      query = query.lte("audio_duration_seconds", body.maxDuration);
    }

    const { data: tracks, error } = await query
      .order("play_count", { ascending: false })
      .limit(limit * 3);

    if (error) {
      return errorResponse(error, { operation: "getAudioTracks" }, 400);
    }

    // Score and rank tracks
    const scoredTracks =
      (tracks as AudioTrackResult[])?.map((track) => {
        let score = 0;

        // Base score from popularity
        score += Math.min(track.play_count / 100, 10);

        // Boost high-rated content
        if (track.average_rating) {
          score += track.average_rating * 3;
        }

        // Check context tags
        if (body.context) {
          const contextTags = getContextTags(body.context);
          const matchingTags =
            track.time_of_day_tags?.filter((t: string) =>
              contextTags.includes(t),
            ) || [];
          score += matchingTags.length * 5;
        }

        // Check mood tags
        if (body.mood) {
          const moodConfig = getMoodConfig(body.mood);
          const matchingMoodTags =
            track.mood_tags?.filter((t: string) =>
              moodConfig.tags?.includes(t),
            ) || [];
          score += matchingMoodTags.length * 5;

          // Bonus for energy level match
          if (
            moodConfig.energyLevel &&
            track.category === moodConfig.energyLevel
          ) {
            score += 10;
          }
        }

        // Penalize recently played but not completed
        if (
          recentTrackIds.includes(track.id) &&
          !completedTrackIds.includes(track.id)
        ) {
          score -= 15;
        }

        // Slight penalty for already completed
        if (completedTrackIds.includes(track.id)) {
          score -= 5;
        }

        // Boost if similar to favorites
        if (
          favoriteTrackIds.length > 0 &&
          favoriteTrackIds.includes(track.id)
        ) {
          score += 15;
        }

        return { ...track, _score: score };
      }) || [];

    // Sort by score and take top results
    const recommendations = scoredTracks
      .sort((a, b) => b._score - a._score)
      .slice(0, limit)
      .map(({ _score, ...track }) => track);

    return new Response(
      JSON.stringify({
        recommendations,
        context: body.context,
        mood: body.mood,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error in get-audio-recommendations:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

function getContextTags(context: string): string[] {
  const contextMap: Record<string, string[]> = {
    morning: ["morning", "energizing", "intention", "wake"],
    evening: ["evening", "wind_down", "relaxing"],
    night: ["sleep", "night", "bedtime", "deep_sleep"],
    focus: ["focus", "concentration", "work", "study"],
    relax: ["relaxing", "calm", "peaceful", "gentle"],
  };
  return contextMap[context] || [];
}

function getMoodConfig(mood: string): {
  energyLevel?: string;
  tags?: string[];
} {
  const moodMap: Record<string, { energyLevel?: string; tags?: string[] }> = {
    anxious: { energyLevel: "calming", tags: ["anxiety", "calm", "grounding"] },
    stressed: {
      energyLevel: "calming",
      tags: ["stress", "relief", "peaceful"],
    },
    calm: { energyLevel: "neutral", tags: ["mindfulness", "awareness"] },
    tired: { energyLevel: "calming", tags: ["rest", "sleep", "recovery"] },
    energetic: {
      energyLevel: "energizing",
      tags: ["motivation", "energy", "uplifting"],
    },
  };
  return moodMap[mood] || {};
}
