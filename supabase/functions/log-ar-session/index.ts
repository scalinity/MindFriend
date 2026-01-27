/**
 * Log AR Session Edge Function
 *
 * Records AR exercise session completion with analytics data.
 *
 * Request:
 *   POST /functions/v1/log-ar-session
 *   Headers: Authorization: Bearer <jwt>
 *   Body: {
 *     exerciseTypeId: string,
 *     startedAt: string (ISO 8601),
 *     completedAt?: string (ISO 8601) | null,
 *     effectivenessRating?: number (1-5) | null,
 *     trackingQualityAvg?: number (0-1),
 *     interruptionsCount?: number,
 *     deviceCapability?: string,
 *     usedVoiceGuidance?: boolean,
 *     completedSteps?: number
 *   }
 *
 * Response:
 *   { sessionId: string, message: string }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface LogSessionRequest {
  exerciseTypeId: string;
  startedAt: string;
  completedAt?: string | null;
  effectivenessRating?: number | null;
  trackingQualityAvg?: number | null;
  interruptionsCount?: number;
  deviceCapability?: string;
  usedVoiceGuidance?: boolean;
  completedSteps?: number;
}

// UUID validation regex
const uuidRegex =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only accept POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing Supabase configuration");
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

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

    // Parse request body
    const body: LogSessionRequest = await req.json();

    // Validate required fields
    if (!body.exerciseTypeId) {
      return new Response(
        JSON.stringify({
          error: "Validation error",
          details: "exerciseTypeId is required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!uuidRegex.test(body.exerciseTypeId)) {
      return new Response(
        JSON.stringify({
          error: "Validation error",
          details: "exerciseTypeId must be a valid UUID",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!body.startedAt) {
      return new Response(
        JSON.stringify({
          error: "Validation error",
          details: "startedAt is required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate effectiveness rating if provided
    if (
      body.effectivenessRating !== undefined &&
      body.effectivenessRating !== null
    ) {
      if (body.effectivenessRating < 1 || body.effectivenessRating > 5) {
        return new Response(
          JSON.stringify({
            error: "Validation error",
            details: "effectivenessRating must be between 1 and 5",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Validate tracking quality if provided
    if (
      body.trackingQualityAvg !== undefined &&
      body.trackingQualityAvg !== null
    ) {
      if (body.trackingQualityAvg < 0 || body.trackingQualityAvg > 1) {
        return new Response(
          JSON.stringify({
            error: "Validation error",
            details: "trackingQualityAvg must be between 0 and 1",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Verify exercise type exists
    const { data: exerciseType, error: exerciseError } = await supabase
      .from("ar_exercise_types")
      .select("id, exercise_name")
      .eq("id", body.exerciseTypeId)
      .single();

    if (exerciseError || !exerciseType) {
      return new Response(
        JSON.stringify({ error: "Exercise type not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Insert session record
    const { data: session, error: insertError } = await supabase
      .from("ar_exercise_sessions")
      .insert({
        user_id: user.id,
        exercise_type_id: body.exerciseTypeId,
        started_at: body.startedAt,
        completed_at: body.completedAt || null,
        effectiveness_rating: body.effectivenessRating || null,
        tracking_quality_avg: body.trackingQualityAvg || null,
        interruptions_count: body.interruptionsCount || 0,
        device_capability: body.deviceCapability || null,
        used_voice_guidance: body.usedVoiceGuidance || false,
        completed_steps: body.completedSteps || 0,
      })
      .select("id")
      .single();

    if (insertError) {
      throw insertError;
    }

    // If session was completed, update user stats
    if (body.completedAt) {
      // Increment total exercises completed
      await supabase.rpc("increment_stat", {
        p_user_id: user.id,
        p_stat_name: "total_exercises_completed",
        p_increment: 1,
      });

      // Award XP for completing an AR exercise (10 XP)
      await supabase.rpc("award_xp", {
        p_user_id: user.id,
        p_amount: 10,
        p_reason: `Completed AR exercise: ${exerciseType.exercise_name}`,
      });
    }

    return new Response(
      JSON.stringify({
        sessionId: session.id,
        message: body.completedAt
          ? "Session completed successfully"
          : "Session logged successfully",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error in log-ar-session:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
