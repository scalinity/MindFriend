import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";

// UUID v4 validation regex
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
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
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { session_id, duration_seconds, messages_count, was_quota_limited } =
      await req.json();

    if (!session_id) {
      return new Response(JSON.stringify({ error: "Missing session_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate session_id is a valid UUID to prevent SQL injection
    if (typeof session_id !== "string" || !UUID_REGEX.test(session_id)) {
      return new Response(
        JSON.stringify({ error: "Invalid session_id format" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify session belongs to user
    const { data: session } = await supabase
      .from("voice_sessions")
      .select("user_id")
      .eq("id", session_id)
      .single();

    if (!session || session.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Session not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Relay membership is server-only. Ignore all client-reported relay usage.
    let { data: relay, error: relayError } = await supabase
      .from("voice_relay_reservations")
      .select("claimed_at, finalized_at, duration_seconds")
      .eq("session_id", session_id)
      .maybeSingle();
    if (relayError) throw Error("Unable to inspect relay status");
    if (relay) {
      if (!relay.claimed_at && !relay.finalized_at) {
        const { error } = await supabase.rpc("end_voice_session", {
          p_session_id: session_id,
          p_duration_seconds: 0,
        });
        if (error) throw Error("Unable to close preparation");
        // Claim may have won the row lock while the first status read was in flight.
        const refreshed = await supabase.from("voice_relay_reservations")
          .select("claimed_at, finalized_at, duration_seconds").eq(
            "session_id",
            session_id,
          ).single();
        if (refreshed.error || !refreshed.data) {
          throw Error("Unable to inspect relay status");
        }
        relay = refreshed.data;
      }
      return new Response(
        JSON.stringify({
          success: true,
          transport: "relay",
          status: relay.finalized_at
            ? "finalized"
            : relay.claimed_at
            ? "pending"
            : "ended",
          duration_seconds: relay.finalized_at ? relay.duration_seconds : null,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (
      (duration_seconds !== undefined &&
        (!Number.isInteger(duration_seconds) || duration_seconds < 0 ||
          duration_seconds > 86_400)) ||
      (messages_count !== undefined &&
        (!Number.isInteger(messages_count) || messages_count < 0 ||
          messages_count > 100_000)) ||
      (was_quota_limited !== undefined &&
        typeof was_quota_limited !== "boolean")
    ) {
      return new Response(JSON.stringify({ error: "Invalid session usage" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // End session and update usage
    const { error: endError } = await supabase.rpc("end_voice_session", {
      p_session_id: session_id,
      p_duration_seconds: duration_seconds || 0,
      p_messages_count: messages_count || 0,
      p_was_quota_limited: was_quota_limited || false,
    });

    if (endError) {
      console.error("End session error:", endError);
      return new Response(JSON.stringify({ error: "Failed to end session" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: minutesRemaining } = await supabase.rpc(
      "get_voice_minutes_remaining",
      { p_user_id: user.id },
    );

    return new Response(
      JSON.stringify({
        success: true,
        minutes_remaining: minutesRemaining || 0,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Voice session end error:", error);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
