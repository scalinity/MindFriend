import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";


interface CompleteSessionRequest {
  sessionId: string;
  duration: number;
  interrupted: boolean;
}

interface CompleteSessionResponse {
  achievementsUnlocked: Array<{
    id: string;
    badge_id: string;
    unlocked_at: string;
  }>;
  stats: {
    totalSessions: number;
    totalMinutes: number;
    currentStreak: number;
  };
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate JWT and get user
    const authHeader = req.headers.get("Authorization")!;
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

    // Parse request body
    const { sessionId, duration, interrupted }: CompleteSessionRequest =
      await req.json();

    // Validate request
    if (!sessionId || duration === undefined) {
      return new Response(
        JSON.stringify({ error: "Missing sessionId or duration" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update sensory_sessions record
    const { error: updateError } = await supabase
      .from("sensory_sessions")
      .update({
        status: "completed",
        completed_at: new Date().toISOString(),
        duration_seconds: duration,
        interrupted: interrupted || false,
      })
      .eq("id", sessionId)
      .eq("user_id", user.id);

    if (updateError) {
      console.error("Failed to update session:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to update session" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Query session stats
    const { data: allSessions } = await supabase
      .from("sensory_sessions")
      .select("duration_seconds")
      .eq("user_id", user.id)
      .eq("status", "completed");

    const totalSessions = allSessions?.length || 0;
    const totalMinutes = Math.floor(
      (allSessions?.reduce((sum, s) => sum + (s.duration_seconds || 0), 0) ||
        0) / 60,
    );

    const response: CompleteSessionResponse = {
      achievementsUnlocked: [],
      stats: {
        totalSessions,
        totalMinutes,
        currentStreak: 0,
      },
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in complete-sensory-session:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
