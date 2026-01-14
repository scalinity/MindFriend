import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
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

    const {
      session_id,
      duration_seconds,
      messages_count,
      was_quota_limited,
    } = await req.json();

    if (!session_id) {
      return new Response(JSON.stringify({ error: "Missing session_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
