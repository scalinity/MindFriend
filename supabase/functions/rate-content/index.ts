// MindFriend Rate Content Edge Function
// Handles user ratings and feedback for AI-generated content

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

// Type alias for untyped Supabase client
type UntypedSupabaseClient = SupabaseClient<unknown, "public", unknown>;

interface RateContentRequest {
  contentId: string;
  rating: number; // 1-5
  helpful?: boolean;
  feedback?: string;
}

interface RateContentResponse {
  success: boolean;
  ratingId: string;
  message: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    // Auth validation
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    // Create Supabase clients
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    ) as UntypedSupabaseClient;

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    ) as UntypedSupabaseClient;

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid authentication" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Rate limiting
    const rateLimitResult = await checkRateLimit(user.id, "content_ratings");
    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "RATE_LIMIT_EXCEEDED",
          message: "Too many rating requests. Please wait a moment.",
        }),
        {
          status: 429,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request
    const request: RateContentRequest = await req.json();

    // Validate rating
    if (request.rating < 1 || request.rating > 5) {
      return new Response(
        JSON.stringify({
          error: "INVALID_RATING",
          message: "Rating must be between 1 and 5",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate content exists and belongs to user
    const { data: content, error: contentError } = await supabaseAdmin
      .from("generated_content")
      .select("id, user_id")
      .eq("id", request.contentId)
      .single();

    if (contentError || !content) {
      return new Response(
        JSON.stringify({
          error: "CONTENT_NOT_FOUND",
          message: "Content not found",
        }),
        {
          status: 404,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Upsert rating (insert or update)
    const { data: rating, error: ratingError } = await supabaseAdmin
      .from("gen_content_ratings")
      .upsert(
        {
          user_id: user.id,
          generated_content_id: request.contentId,
          rating: request.rating,
          helpful: request.helpful,
          feedback_text: request.feedback,
        },
        {
          onConflict: "user_id,generated_content_id",
        },
      )
      .select("id")
      .single();

    if (ratingError) {
      console.error("Rating error:", ratingError);
      return new Response(
        JSON.stringify({
          error: "RATING_FAILED",
          message: "Failed to save rating",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Log analytics event
    await supabaseAdmin.from("analytics_events").insert({
      user_id: user.id,
      event_type: "content_rated",
      event_data: {
        content_id: request.contentId,
        rating: request.rating,
        helpful: request.helpful,
        has_feedback: !!request.feedback,
      },
    });

    const response: RateContentResponse = {
      success: true,
      ratingId: rating.id,
      message: "Thank you for your feedback!",
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Rate content error:", error);
    const errorMessage =
      error instanceof Error ? error.message : "An unexpected error occurred";

    return new Response(
      JSON.stringify({
        error: "RATING_FAILED",
        message: errorMessage,
      }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
