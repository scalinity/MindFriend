// MindFriend Flag Content Edge Function
// Handles user reports of inappropriate or problematic AI-generated content

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

// Type alias for untyped Supabase client
type UntypedSupabaseClient = SupabaseClient<unknown, "public", unknown>;

interface FlagContentRequest {
  contentId: string;
  reason: "inappropriate" | "inaccurate" | "offensive" | "safety_concern" | "other";
  details?: string;
}

interface FlagContentResponse {
  success: boolean;
  flagId: string;
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
    //optional for Auth validation ( anonymous flagging)
    let userId: string | null = null;
    const authHeader = req.headers.get("Authorization");

    if (authHeader && authHeader.startsWith("Bearer ")) {
      const token = authHeader.replace("Bearer ", "");

      const supabaseUser = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        {
          global: {
            headers: { Authorization: `Bearer ${token}` },
          },
        },
      ) as UntypedSupabaseClient;

      const {
        data: { user },
        error: authError,
      } = await supabaseUser.auth.getUser();

      if (!authError && user) {
        userId = user.id;

        // Rate limiting for authenticated users
        const rateLimitResult = await checkRateLimit(user.id, "content_flags");
        if (!rateLimitResult.allowed) {
          return new Response(
            JSON.stringify({
              error: "RATE_LIMIT_EXCEEDED",
              message: "Too many content flags. Please wait a moment.",
            }),
            {
              status: 429,
              headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // Parse request
    const request: FlagContentRequest = await req.json();

    // Validate reason
    const validReasons = [
      "inappropriate",
      "inaccurate",
      "offensive",
      "safety_concern",
      "other",
    ];
    if (!validReasons.includes(request.reason)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_REASON",
          message: "Invalid flag reason",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate content exists
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    ) as UntypedSupabaseClient;

    const { data: content, error: contentError } = await supabaseAdmin
      .from("generated_content")
      .select("id, user_id, content_type, safety_flags")
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

    // Check for duplicate flags from same user
    if (userId) {
      const { data: existingFlag } = await supabaseAdmin
        .from("gen_content_flags")
        .select("id")
        .eq("generated_content_id", request.contentId)
        .eq("user_id", userId)
        .single();

      if (existingFlag) {
        return new Response(
          JSON.stringify({
            error: "ALREADY_FLAGGED",
            message: "You have already flagged this content",
          }),
          {
            status: 409,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Create flag record
    const { data: flag, error: flagError } = await supabaseAdmin
      .from("gen_content_flags")
      .insert({
        generated_content_id: request.contentId,
        user_id: userId,
        reason: request.reason,
        description: request.details,
        status: "pending",
      })
      .select("id")
      .single();

    if (flagError) {
      console.error("Flag error:", flagError);
      return new Response(
        JSON.stringify({
          error: "FLAG_FAILED",
          message: "Failed to submit flag",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Auto-escalate safety concerns for immediate review
    if (request.reason === "safety_concern") {
      await supabaseAdmin
        .from("generated_content")
        .update({
          status: "flagged",
          safety_flags: [...(content.safety_flags || []), "user_reported_safety_concern"],
        })
        .eq("id", request.contentId);

      // Log critical alert
      await supabaseAdmin.from("critical_alerts").insert({
        alert_type: "safety_content_flagged",
        resource_type: "generated_content",
        resource_id: request.contentId,
        severity: "high",
        message: `Generated content flagged for safety concerns: ${request.reason}`,
        metadata: {
          flag_id: flag.id,
          user_id: userId,
          content_type: content.content_type,
        },
      });
    }

    // Log analytics
    await supabaseAdmin.from("analytics_events").insert({
      user_id: userId,
      event_type: "content_flagged",
      event_data: {
        content_id: request.contentId,
        reason: request.reason,
        has_details: !!request.details,
      },
    });

    const response: FlagContentResponse = {
      success: true,
      flagId: flag.id,
      message:
        request.reason === "safety_concern"
          ? "Thank you. This has been flagged for immediate review by our safety team."
          : "Thank you for helping keep MindFriend safe. Our team will review this content.",
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Flag content error:", error);
    const errorMessage =
      error instanceof Error ? error.message : "An unexpected error occurred";

    return new Response(
      JSON.stringify({
        error: "FLAG_FAILED",
        message: errorMessage,
      }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
