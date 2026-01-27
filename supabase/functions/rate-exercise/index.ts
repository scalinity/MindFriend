// Rate Exercise Edge Function
// Purpose: Handle exercise ratings and feedback for personalization
// Author: dev-pipeline
// Date: 2026-01-24

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface RateExerciseRequest {
  contentId: string;
  rating: number; // 1-5
  feedback?: string;
}

interface RateExerciseResponse {
  success: boolean;
  updatedRating: number;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid authentication" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request
    const request: RateExerciseRequest = await req.json();

    // Validate rating
    if (
      !request.rating ||
      request.rating < 1 ||
      request.rating > 5 ||
      !Number.isInteger(request.rating)
    ) {
      return new Response(
        JSON.stringify({
          error: "INVALID_RATING",
          message: "Rating must be an integer between 1 and 5",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate content ID
    if (!request.contentId) {
      return new Response(
        JSON.stringify({
          error: "INVALID_REQUEST",
          message: "contentId is required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Verify ownership
    const { data: content, error: fetchError } = await supabaseAdmin
      .from("generated_content")
      .select("id, user_id, content_type")
      .eq("id", request.contentId)
      .single();

    if (fetchError || !content) {
      return new Response(
        JSON.stringify({
          error: "CONTENT_NOT_FOUND",
          message: "Exercise not found",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (content.user_id !== user.id) {
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "You can only rate your own exercises",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update rating
    const { error: updateError } = await supabaseAdmin
      .from("generated_content")
      .update({
        user_rating: request.rating,
        average_rating: request.rating, // For single-user content, these are the same
        rating_count: 1,
        updated_at: new Date().toISOString(),
      })
      .eq("id", request.contentId);

    if (updateError) {
      console.error("Rating update error:", updateError);
      return new Response(
        JSON.stringify({
          error: "UPDATE_FAILED",
          message: "Failed to save rating",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // TODO: Store detailed feedback in future content_feedback table if needed
    // TODO: Use ratings to adjust user preferences for future generations

    const response: RateExerciseResponse = {
      success: true,
      updatedRating: request.rating,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Rate exercise error:", error);
    return new Response(
      JSON.stringify({
        error: "RATING_FAILED",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
