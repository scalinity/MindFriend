// MindFriend Accept Family Invite Edge Function
// Handles family/couples plan invitation acceptance

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";
import {
  isValidInviteCode,
  validateFamilyInviteCode,
} from "../_shared/validation.ts";

interface AcceptInviteRequest {
  invite_code: string;
}

interface AcceptInviteResponse {
  success: boolean;
  familyId?: string;
  circleId?: string;
  message: string;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only allow POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseAdmin = createClient(
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
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Rate limit: 10 requests per minute per user
    // Prevents brute-force enumeration of invite codes
    const rateLimit = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "accept-family-invite",
      {
        windowMs: 60 * 1000, // 1 minute
        maxRequests: 10,
      },
    );

    if (!rateLimit.allowed) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Too many requests. Please try again later.",
          retryAfter: rateLimit.retryAfter,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimit),
          },
        },
      );
    }

    const { invite_code }: AcceptInviteRequest = await req.json();

    if (typeof invite_code !== "string" || !invite_code) {
      return new Response(JSON.stringify({ error: "Missing invite_code" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate invite code format before any database queries
    const validationResult = validateFamilyInviteCode(invite_code);
    if (!isValidInviteCode(validationResult)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid invite code format",
          details: { reason: validationResult.error },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: result, error } = await supabaseAdmin.rpc(
      "join_family_atomic",
      {
        p_user_id: user.id,
        p_invite_code: validationResult.normalized,
        p_require_invitation: true,
      },
    );
    if (error || !result?.success) {
      const status = error?.code === "42501"
        ? 403
        : error?.code === "22023"
        ? 400
        : 500;
      return new Response(
        JSON.stringify({
          success: false,
          error: status < 500 ? error?.message : "Failed to accept invitation",
        }),
        {
          status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const response: AcceptInviteResponse = {
      success: true,
      familyId: result.family_id,
      circleId: result.circle_id ?? undefined,
      message: `Welcome to ${result.family_name || "the family plan"}!`,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Accept invite error:", error);
    // Don't expose raw error messages to client
    return new Response(
      JSON.stringify({
        success: false,
        error: "Failed to accept invitation",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
