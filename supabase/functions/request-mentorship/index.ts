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

  // Auth with timeout
  const authTimeoutPromise = new Promise((_resolve, reject) =>
    setTimeout(
      () => reject(new Error("Auth timeout")),
      5000, // 5 second timeout
    ),
  );

  const authPromise = (async () => {
    return await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  })();

  let user;
  let authError;
  try {
    const authResult = await Promise.race([authPromise, authTimeoutPromise]);
    user = authResult.data?.user;
    authError = authResult.error;
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: "Authentication failed",
        code: "AUTH_FAILED",
      }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

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

  // Sanitize introduction message - remove HTML tags and JavaScript
  const sanitizedIntro = introMessage
    .replace(/<[^>]*>/g, "") // Remove HTML tags
    .replace(/javascript:/gi, "") // Remove javascript: protocol
    .replace(/on\w+\s*=/gi, "") // Remove event handlers
    .replace(/data:text\/html/gi, "") // Remove data URIs
    .trim();

  if (sanitizedIntro.length === 0) {
    return new Response(
      JSON.stringify({
        error: "Introduction message cannot contain only HTML/scripts",
        code: "INVALID_MESSAGE_CONTENT",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    // Create the match via RPC (performs all checks under advisory lock)
    // RPC with timeout
    const rpcTimeoutPromise = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("RPC timeout")),
        8000, // 8 second timeout
      ),
    );

    const rpcPromise = (async () => {
      return await supabase.rpc("create_mentorship_request", {
        p_mentor_id: body.mentorId,
        p_introduction_message: sanitizedIntro,
      });
    })();

    let matchIdResult;
    try {
      matchIdResult = await Promise.race([rpcPromise, rpcTimeoutPromise]);
    } catch (timeoutError) {
      return new Response(
        JSON.stringify({
          error: "Request took too long. Please try again.",
          code: "TIMEOUT",
        }),
        {
          status: 504,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: matchId, error: rpcError } = matchIdResult;

    if (rpcError || !matchId) {
      console.error("RPC error creating mentorship request:", rpcError?.message);
      return new Response(
        JSON.stringify({
          error: "Unable to create mentorship request. Please try again.",
          code: "REQUEST_FAILED",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get the created match details with timeout
    const queryTimeoutPromise = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("Query timeout")),
        5000, // 5 second timeout
      ),
    );

    const queryPromise = (async () => {
      return await supabase
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
        `
        )
        .eq("id", matchId)
        .single();
    })();

    let matchQueryResult;
    try {
      matchQueryResult = await Promise.race([queryPromise, queryTimeoutPromise]);
    } catch (timeoutError) {
      console.error("Query timeout fetching match details");
      // Match was created but we couldn't fetch details - still success
      return new Response(
        JSON.stringify({
          success: true,
          matchId: matchId,
          match: null,
          message:
            "Your mentorship request has been sent. The mentor will respond soon.",
        }),
        {
          status: 201,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: match } = matchQueryResult;

    // Notify the mentor (non-blocking, fire-and-forget with timeout)
    const notificationTimeoutPromise = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("Notification timeout")),
        5000, // 5 second timeout
      ),
    );

    const notificationPromise = (async () => {
      return await supabase.functions.invoke("send-notification", {
        body: {
          userId: body.mentorId,
          title: "New Mentorship Request",
          body: "Someone would like you to be their mentor!",
          data: {
            type: "mentorship_request",
            matchId: matchId,
          },
        },
      });
    })();

    // Fire notification but don't wait for it
    Promise.race([notificationPromise, notificationTimeoutPromise]).catch(
      (error) => {
        console.error("Notification failed:", error.message || error);
      }
    );

    return new Response(
      JSON.stringify({
        success: true,
        matchId: matchId,
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
      }
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
