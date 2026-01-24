// Request Mentorship - Create a mentorship request to a mentor
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  getCorsHeaders,
  validateContentType,
  parseJsonBody,
} from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

interface MentorshipRequest {
  mentorId: string;
  introductionMessage: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Validate content type
  const contentTypeError = validateContentType(req, corsHeaders);
  if (contentTypeError) return contentTypeError;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Auth
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Unauthorized", code: "NO_AUTH" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(
      JSON.stringify({ error: "Unauthorized", code: "INVALID_TOKEN" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Rate limiting - 5 mentorship requests per hour
  const rateLimit = await checkRateLimit(
    supabase,
    user.id,
    "request-mentorship",
    {
      windowMs: 60 * 60 * 1000, // 1 hour
      maxRequests: 5,
    },
  );

  if (!rateLimit.allowed) {
    return new Response(
      JSON.stringify({
        error: "Too many mentorship requests. Please wait before trying again.",
        code: "RATE_LIMITED",
        retryAfter: rateLimit.retryAfter,
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          ...getRateLimitHeaders(rateLimit),
          "Content-Type": "application/json",
        },
      },
    );
  }

  // Parse request body
  const body = await parseJsonBody<MentorshipRequest>(req);
  if (!body) {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body", code: "PARSE_ERROR" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Validate required fields
  if (!body.mentorId) {
    return new Response(
      JSON.stringify({
        error: "mentorId is required",
        code: "MISSING_MENTOR_ID",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Validate UUID format
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(body.mentorId)) {
    return new Response(
      JSON.stringify({
        error: "Invalid mentorId format",
        code: "INVALID_MENTOR_ID",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Introduction message validation
  const introMessage = body.introductionMessage?.trim() || "";
  if (introMessage.length < 20) {
    return new Response(
      JSON.stringify({
        error: "Introduction message must be at least 20 characters",
        code: "MESSAGE_TOO_SHORT",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  if (introMessage.length > 1000) {
    return new Response(
      JSON.stringify({
        error: "Introduction message must be less than 1000 characters",
        code: "MESSAGE_TOO_LONG",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    // Check if mentor is trying to mentor themselves
    if (body.mentorId === user.id) {
      return new Response(
        JSON.stringify({
          error: "You cannot mentor yourself",
          code: "SELF_MENTORSHIP",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check mentor availability
    const { data: mentorProfile, error: profileError } = await supabase
      .from("mentorship_profiles")
      .select("*")
      .eq("user_id", body.mentorId)
      .eq("is_mentor_available", true)
      .eq("verified", true)
      .eq("training_completed", true)
      .maybeSingle();

    if (profileError) {
      console.error("Error checking mentor profile:", profileError);
      return new Response(
        JSON.stringify({ error: "Failed to verify mentor", code: "DB_ERROR" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!mentorProfile) {
      return new Response(
        JSON.stringify({
          error: "Mentor is not available or not verified",
          code: "MENTOR_UNAVAILABLE",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for existing active match
    const { data: existingMatch } = await supabase
      .from("mentorship_matches")
      .select("id, status")
      .eq("mentor_id", body.mentorId)
      .eq("mentee_id", user.id)
      .in("status", ["pending", "accepted", "active"])
      .maybeSingle();

    if (existingMatch) {
      return new Response(
        JSON.stringify({
          error: "You already have an active request with this mentor",
          code: "MATCH_EXISTS",
          matchId: existingMatch.id,
          status: existingMatch.status,
        }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check mentor capacity
    const { count: activeMatches } = await supabase
      .from("mentorship_matches")
      .select("id", { count: "exact", head: true })
      .eq("mentor_id", body.mentorId)
      .in("status", ["pending", "accepted", "active"]);

    if ((activeMatches || 0) >= mentorProfile.max_active_mentees) {
      return new Response(
        JSON.stringify({
          error: "This mentor has reached their capacity. Try another mentor.",
          code: "MENTOR_AT_CAPACITY",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create mentorship request using the database function
    const { data: matchId, error: createError } = await supabase.rpc(
      "create_mentorship_request",
      {
        p_mentor_id: body.mentorId,
        p_introduction_message: introMessage,
      },
    );

    if (createError) {
      console.error("Error creating mentorship request:", createError);

      // Handle specific errors
      if (createError.message.includes("Mentor not available")) {
        return new Response(
          JSON.stringify({
            error: "Mentor is not available",
            code: "MENTOR_UNAVAILABLE",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (createError.message.includes("Match already exists")) {
        return new Response(
          JSON.stringify({
            error: "You already have a request with this mentor",
            code: "MATCH_EXISTS",
          }),
          {
            status: 409,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({
          error: "Failed to create mentorship request",
          code: "CREATE_ERROR",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get the created match details
    const { data: match } = await supabase
      .from("mentorship_matches")
      .select(
        `
        id,
        mentor_id,
        mentee_id,
        status,
        compatibility_score,
        match_reason,
        mentor_alias,
        mentee_alias,
        created_at
      `,
      )
      .eq("id", matchId)
      .single();

    // Notify the mentor
    try {
      await supabase.functions.invoke("send-notification", {
        body: {
          userId: body.mentorId,
          title: "New Mentorship Request",
          body: "Someone would like you to be their mentor!",
          data: {
            type: "mentorship_request",
            matchId,
          },
        },
      });
    } catch (notifyError) {
      // Log but don't fail the request
      console.error("Failed to send notification:", notifyError);
    }

    return new Response(
      JSON.stringify({
        success: true,
        matchId,
        match: match
          ? {
              id: match.id,
              mentorId: match.mentor_id,
              menteeId: match.mentee_id,
              status: match.status,
              compatibilityScore: match.compatibility_score,
              matchReason: match.match_reason,
              mentorAlias: match.mentor_alias,
              menteeAlias: match.mentee_alias,
              createdAt: match.created_at,
            }
          : null,
        message:
          "Your mentorship request has been sent. The mentor will respond soon.",
      }),
      {
        status: 201,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
