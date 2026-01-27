import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { errorResponse } from "../_shared/error-handler.ts";

interface PlaybackEvent {
  trackId: string;
  eventType: "start" | "progress" | "complete" | "skip";
  positionSeconds: number;
  durationListenedSeconds?: number;
  source?: string;
  contextId?: string;
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

    const body: PlaybackEvent = await req.json();

    if (body.eventType === "start") {
      // Create new playback session
      const { data, error } = await supabase
        .from("playback_sessions")
        .insert({
          user_id: user.id,
          track_id: body.trackId,
          started_at: new Date().toISOString(),
          last_position_seconds: 0,
          source: body.source || "unknown",
          context_id: body.contextId,
        })
        .select()
        .single();

      if (error) {
        return errorResponse(
          error,
          { operation: "createPlaybackSession" },
          400,
        );
      }

      return new Response(JSON.stringify({ playbackSessionId: data.id }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // For progress/complete/skip, find most recent playback for this track
    const { data: recentPlayback, error: findError } = await supabase
      .from("playback_sessions")
      .select("id")
      .eq("user_id", user.id)
      .eq("track_id", body.trackId)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (findError || !recentPlayback) {
      return new Response(
        JSON.stringify({ error: "No active playback found" }),
        {
          status: 404,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const updates: Record<string, unknown> = {
      last_position_seconds: body.positionSeconds,
    };

    if (body.durationListenedSeconds !== undefined) {
      updates.duration_played_seconds = body.durationListenedSeconds;
    }

    if (body.eventType === "complete") {
      updates.completed = true;
      updates.ended_at = new Date().toISOString();

      // Award badge if first meditation completion
      await checkAndAwardBadges(supabase, user.id, body.trackId);
    }

    if (body.eventType === "skip") {
      updates.skipped = true;
      updates.skip_position_seconds = body.positionSeconds;
      updates.ended_at = new Date().toISOString();
    }

    const { error: updateError } = await supabase
      .from("playback_sessions")
      .update(updates)
      .eq("id", recentPlayback.id);

    if (updateError) {
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in record-playback:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function checkAndAwardBadges(
  supabase: any,
  userId: string,
  trackId: string,
) {
  try {
    // Get track category for audio-specific badges
    const { data: track } = await supabase
      .from("audio_tracks")
      .select("category")
      .eq("id", trackId)
      .single();

    if (!track) return;

    // Count completions for this user
    const { count } = await supabase
      .from("playback_sessions")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("completed", true);

    // Check for audio-specific badges
    const badgesToCheck = [
      { count: 1, badge_code: "first_audio_play" },
      { count: 5, badge_code: "audio_enthusiast_5" },
      { count: 10, badge_code: "audio_enthusiast_10" },
      { count: 25, badge_code: "audio_enthusiast_25" },
    ];

    for (const check of badgesToCheck) {
      if (count && count >= check.count) {
        // Look up badge by code
        const { data: badge } = await supabase
          .from("badges")
          .select("id")
          .eq("code", check.badge_code)
          .single();

        if (!badge) continue;

        // Check if badge already awarded
        const { data: existing } = await supabase
          .from("user_badges")
          .select("id")
          .eq("user_id", userId)
          .eq("badge_id", badge.id)
          .single();

        if (!existing) {
          await supabase.from("user_badges").insert({
            user_id: userId,
            badge_id: badge.id,
          });
        }
      }
    }
  } catch (error) {
    // Silently fail - badge awarding is non-critical
    console.error("Error awarding badge:", error);
  }
}
