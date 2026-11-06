// MindFriend Flag Content Edge Function
// Handles user reports of inappropriate or problematic AI-generated content

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/ratelimit.ts";

// Type alias for untyped Supabase client
type UntypedSupabaseClient = SupabaseClient;

interface FlagContentRequest {
  contentId: string;
  reason:
    | "inappropriate"
    | "inaccurate"
    | "offensive"
    | "safety_concern"
    | "harmful"
    | "triggering"
    | "misleading"
    | "other";
  details?: string;
}

interface FlagContentResponse {
  success: boolean;
  flagId: string;
  message: string;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    ) as UntypedSupabaseClient;
    // Generated content is private to its owner, including reports about it.
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
        const rateLimitResult = await checkRateLimit(
          supabaseAdmin,
          user.id,
          "content_flags",
        );
        if (!rateLimitResult.allowed) {
          return new Response(
            JSON.stringify({
              error: "RATE_LIMIT_EXCEEDED",
              message: "Too many content flags. Please wait a moment.",
            }),
            {
              status: 429,
              headers: {
                ...baseCorsHeaders,
                "Content-Type": "application/json",
              },
            },
          );
        }
      }
    }

    if (!userId) {
      return new Response(JSON.stringify({ error: "UNAUTHORIZED" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request
    const request: FlagContentRequest = await req.json();

    // Released clients use these labels; persist the existing review categories.
    if (request.reason === "harmful" || request.reason === "triggering") {
      request.reason = "safety_concern";
    } else if (request.reason === "misleading") {
      request.reason = "inaccurate";
    }

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

    const { data: content, error: contentError } = await supabaseAdmin
      .from("generated_content")
      .select("id, user_id, content_type, safety_flags")
      .eq("id", request.contentId)
      .eq("user_id", userId)
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

    // Reuse a pending safety report so a retry can finish a failed escalation.
    let flagId: string | undefined;
    if (userId) {
      const { data: existingFlag, error: duplicateError } = await supabaseAdmin
        .from("gen_content_flags")
        .select("id, reason, status")
        .eq("generated_content_id", request.contentId)
        .eq("user_id", userId)
        .maybeSingle();

      if (duplicateError) {
        console.error("Flag lookup error", { code: duplicateError.code });
        return new Response(
          JSON.stringify({
            success: false,
            error: "FLAG_FAILED",
            message: "Failed to check existing flags",
          }),
          {
            status: 500,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (existingFlag) {
        if (
          request.reason === "safety_concern" &&
          existingFlag.reason === "safety_concern" &&
          existingFlag.status === "pending"
        ) {
          flagId = existingFlag.id;
        } else {
          return new Response(
            JSON.stringify({
              error: "ALREADY_FLAGGED",
              message: "You have already flagged this content",
            }),
            {
              status: 409,
              headers: {
                ...baseCorsHeaders,
                "Content-Type": "application/json",
              },
            },
          );
        }
      }
    }

    // This existing table is the clinical review queue; no separate alert is needed.
    if (!flagId) {
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

      if (flagError || !flag?.id) {
        console.error("Flag insert error", {
          code: flagError?.code ?? "MISSING_ROW",
        });
        return new Response(
          JSON.stringify({
            success: false,
            error: "FLAG_FAILED",
            message: "Failed to submit flag",
          }),
          {
            status: 500,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      flagId = flag.id;
    }

    // Keep generation status separate from the persisted safety review markers.
    if (request.reason === "safety_concern") {
      const { data: escalatedContent, error: escalationError } =
        await supabaseAdmin
          .from("generated_content")
          .update({
            safety_flags: [
              ...new Set([
                ...(content.safety_flags || []),
                "user_reported_safety_concern",
              ]),
            ],
          })
          .eq("id", request.contentId)
          .eq("user_id", userId)
          .select("id")
          .single();

      if (escalationError || !escalatedContent) {
        console.error("Safety escalation error", {
          code: escalationError?.code ?? "MISSING_ROW",
        });
        return new Response(
          JSON.stringify({
            success: false,
            error: "ESCALATION_FAILED",
            message:
              "Your report was saved, but safety escalation failed. Please retry.",
            flagId,
          }),
          {
            status: 503,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    const response: FlagContentResponse = {
      success: true,
      flagId: flagId!,
      message: request.reason === "safety_concern"
        ? "Thank you. Your safety concern has been saved for clinical review."
        : "Thank you. Your report has been saved for review.",
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Flag content error", {
      type: error instanceof Error ? error.name : "UnknownError",
    });

    return new Response(
      JSON.stringify({
        error: "FLAG_FAILED",
        message: "Unable to save your report. Please try again.",
      }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
