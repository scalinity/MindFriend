// MindFriend Live Session Manager Edge Function
// Handles join/leave/react/complete actions for live sessions
// See: docs/specs/03-live-experiences.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Security constants
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ALLOWED_EMOJIS = ["🙏", "💙", "✨", "🌟", "❤️", "👏"];

interface SessionRequest {
  action: "join" | "leave" | "react" | "complete" | "heartbeat";
  session_id: string;
  emoji?: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client with service role for admin operations
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body: SessionRequest = await req.json();

    // Validate session_id
    if (!body.session_id || !UUID_REGEX.test(body.session_id)) {
      return new Response(JSON.stringify({ error: "Invalid session_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    switch (body.action) {
      case "join": {
        // Verify session is active and within time window
        const { data: session, error: sessionError } = await supabaseAdmin
          .from("live_sessions")
          .select()
          .eq("id", body.session_id)
          .eq("is_active", true)
          .gte("scheduled_end", new Date().toISOString())
          .single();

        if (sessionError || !session) {
          return new Response(
            JSON.stringify({ error: "Session not available" }),
            {
              status: 404,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        // Join session (upsert to handle rejoins)
        await supabaseAdmin.from("live_session_participants").upsert(
          {
            session_id: body.session_id,
            user_id: user.id,
            joined_at: new Date().toISOString(),
            left_at: null,
            completed: false,
          },
          { onConflict: "session_id,user_id" },
        );

        // Get current participant count
        const { count } = await supabaseAdmin
          .from("live_session_participants")
          .select("id", { count: "exact", head: true })
          .eq("session_id", body.session_id)
          .is("left_at", null);

        // Broadcast participant update via Realtime
        const channel = supabaseAdmin.channel(
          `live:session:${body.session_id}`,
        );
        await channel.send({
          type: "broadcast",
          event: "participant_update",
          payload: { type: "participant_joined", count },
        });

        // Update user presence
        await supabaseAdmin.rpc("update_presence", {
          p_activity: "live_session",
        });

        return new Response(
          JSON.stringify({
            session: {
              id: session.id,
              title: session.title,
              description: session.description,
              session_type: session.session_type,
              scheduled_start: session.scheduled_start,
              scheduled_end: session.scheduled_end,
              audio_url: session.audio_url,
            },
            participant_count: count || 0,
            audio_url: session.audio_url,
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      case "leave": {
        // Mark user as left
        await supabaseAdmin
          .from("live_session_participants")
          .update({ left_at: new Date().toISOString() })
          .eq("session_id", body.session_id)
          .eq("user_id", user.id);

        // Get updated participant count
        const { count } = await supabaseAdmin
          .from("live_session_participants")
          .select("id", { count: "exact", head: true })
          .eq("session_id", body.session_id)
          .is("left_at", null);

        // Broadcast participant update
        const channel = supabaseAdmin.channel(
          `live:session:${body.session_id}`,
        );
        await channel.send({
          type: "broadcast",
          event: "participant_update",
          payload: { type: "participant_left", count },
        });

        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      case "react": {
        // Validate emoji
        if (!body.emoji || !ALLOWED_EMOJIS.includes(body.emoji)) {
          return new Response(JSON.stringify({ error: "Invalid emoji" }), {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        // Increment user's reaction count
        await supabaseAdmin.rpc("update_live_session_reactions", {
          p_session_id: body.session_id,
          p_user_id: user.id,
        });

        // Broadcast reaction to all participants (anonymous)
        const channel = supabaseAdmin.channel(
          `live:session:${body.session_id}`,
        );
        await channel.send({
          type: "broadcast",
          event: "reaction",
          payload: { type: "reaction", emoji: body.emoji },
        });

        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      case "complete": {
        // Mark session as completed for user
        await supabaseAdmin
          .from("live_session_participants")
          .update({
            completed: true,
            left_at: new Date().toISOString(),
          })
          .eq("session_id", body.session_id)
          .eq("user_id", user.id);

        // Award XP for live session completion (bonus XP)
        const XP_AWARD = 40;
        await supabaseAdmin.rpc("award_xp", {
          p_amount: XP_AWARD,
          p_activity_type: "live_session",
        });

        // Get updated participant count
        const { count } = await supabaseAdmin
          .from("live_session_participants")
          .select("id", { count: "exact", head: true })
          .eq("session_id", body.session_id)
          .is("left_at", null);

        // Broadcast participant left
        const channel = supabaseAdmin.channel(
          `live:session:${body.session_id}`,
        );
        await channel.send({
          type: "broadcast",
          event: "participant_update",
          payload: { type: "participant_left", count },
        });

        return new Response(
          JSON.stringify({ success: true, xp_awarded: XP_AWARD }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      case "heartbeat": {
        // Update presence to keep connection alive
        await supabaseAdmin.rpc("update_presence", {
          p_activity: "live_session",
        });

        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      default:
        return new Response(JSON.stringify({ error: "Invalid action" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }
  } catch (error) {
    console.error("Live session manager error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
