// Match Support Session - Connects seekers with available peer listeners
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import {
  getCorsHeaders,
  validateContentType,
  parseJsonBody,
  checkRateLimit,
  getRateLimitHeaders,
} from "../_shared/cors.ts";

interface MatchRequest {
  sessionType: string;
  topicTags?: string[];
  isAnonymous?: boolean;
  preferredLanguage?: string;
  preferredGender?: string;
  seekerMood?: number;
  seekerNotes?: string;
}

interface MatchResult {
  matched: boolean;
  listener?: {
    displayName: string | null;
    rating: number | null;
    sessionCount: number;
  };
  estimatedWait?: number;
}

const VALID_SESSION_TYPES = ["quick", "deep", "crisis_bridge"];
const QUEUE_EXPIRY_MINUTES = 30;

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

  // Rate limiting - 5 support requests per minute per user
  const rateLimit = checkRateLimit(`support:${user.id}`, 5, 60000);
  if (!rateLimit.allowed) {
    return new Response(
      JSON.stringify({
        error:
          "Too many requests. Please wait before requesting support again.",
        code: "RATE_LIMITED",
        retryAfter: Math.ceil(rateLimit.resetIn / 1000),
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          ...getRateLimitHeaders(rateLimit.remaining, rateLimit.resetIn),
          "Content-Type": "application/json",
        },
      },
    );
  }

  // Parse request body
  const body = await parseJsonBody<MatchRequest>(req);
  if (!body) {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body", code: "PARSE_ERROR" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Validate session type
  if (!body.sessionType || !VALID_SESSION_TYPES.includes(body.sessionType)) {
    return new Response(
      JSON.stringify({
        error: "Invalid session type",
        code: "INVALID_SESSION_TYPE",
        validTypes: VALID_SESSION_TYPES,
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Validate optional fields
  if (
    body.seekerMood !== undefined &&
    (body.seekerMood < 1 || body.seekerMood > 10)
  ) {
    return new Response(
      JSON.stringify({
        error: "Mood must be between 1 and 10",
        code: "INVALID_MOOD",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  if (body.topicTags && !Array.isArray(body.topicTags)) {
    return new Response(
      JSON.stringify({
        error: "topicTags must be an array",
        code: "INVALID_TAGS",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    // Check if user already has an active session
    const { data: existingSession } = await supabase
      .from("support_sessions")
      .select("id")
      .eq("seeker_id", user.id)
      .in("status", ["pending", "matched", "active"])
      .maybeSingle();

    if (existingSession) {
      return new Response(
        JSON.stringify({
          error: "Active session exists",
          code: "SESSION_EXISTS",
          sessionId: existingSession.id,
        }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create session
    const { data: session, error: sessionError } = await supabase
      .from("support_sessions")
      .insert({
        seeker_id: user.id,
        session_type: body.sessionType,
        topic_tags: body.topicTags || [],
        is_anonymous: body.isAnonymous || false,
        seeker_mood_before: body.seekerMood,
        seeker_notes: body.seekerNotes,
      })
      .select()
      .single();

    if (sessionError) {
      console.error("Failed to create session:", sessionError);
      return new Response(
        JSON.stringify({ error: "Failed to create session", code: "DB_ERROR" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Try immediate matching
    const matchResult = await attemptMatch(supabase, session, body);

    if (matchResult.matched) {
      return new Response(
        JSON.stringify({
          success: true,
          sessionId: session.id,
          status: "matched",
          listener: matchResult.listener,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Add to queue for async matching
    const expiresAt = new Date(Date.now() + QUEUE_EXPIRY_MINUTES * 60 * 1000);
    await supabase.from("support_queue").upsert(
      {
        seeker_id: user.id,
        session_type: body.sessionType,
        topic_tags: body.topicTags || [],
        is_anonymous: body.isAnonymous || false,
        preferred_language: body.preferredLanguage || "en",
        preferred_gender: body.preferredGender,
        expires_at: expiresAt.toISOString(),
      },
      { onConflict: "seeker_id,session_type" },
    );

    return new Response(
      JSON.stringify({
        success: true,
        sessionId: session.id,
        status: "queued",
        estimatedWait: matchResult.estimatedWait,
      }),
      {
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

async function attemptMatch(
  supabase: SupabaseClient,
  session: { id: string; session_type: string },
  request: MatchRequest,
): Promise<MatchResult> {
  // Use the atomic claim_listener_for_session RPC which handles:
  // 1. Row-level locking to prevent race conditions
  // 2. Timezone-aware availability matching
  // 3. Topic and language filtering
  // 4. Active session checks
  const { data: matchedListener, error: matchError } = await supabase.rpc(
    "claim_listener_for_session",
    {
      p_session_id: session.id,
      p_topic_tags: request.topicTags || [],
      p_preferred_language: request.preferredLanguage || "en",
      p_session_type: session.session_type,
      // Use seeker's timezone if available, fallback to UTC
      p_user_timezone:
        Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
    },
  );

  if (matchError) {
    console.error("Error in claim_listener_for_session:", matchError);
    return {
      matched: false,
      estimatedWait: await estimateWaitTime(supabase),
    };
  }

  // Check if we got a match (RPC returns array with 0 or 1 rows)
  if (matchedListener && matchedListener.length > 0) {
    const listener = matchedListener[0];

    // Notify listener via push notification
    await notifyListener(supabase, listener.user_id, session);

    return {
      matched: true,
      listener: {
        displayName: listener.display_name,
        rating: listener.average_rating,
        sessionCount: listener.total_sessions,
      },
    };
  }

  return {
    matched: false,
    estimatedWait: await estimateWaitTime(supabase),
  };
}

async function estimateWaitTime(supabase: SupabaseClient): Promise<number> {
  // Get queue depth
  const { count: queueCount } = await supabase
    .from("support_queue")
    .select("id", { count: "exact", head: true })
    .is("matched_session_id", null);

  // Get available listener count
  const { count: listenerCount } = await supabase
    .from("listeners")
    .select("id", { count: "exact", head: true })
    .eq("status", "active")
    .eq("is_available", true);

  if (!listenerCount || listenerCount === 0) {
    return 30; // 30 minutes if no listeners available
  }

  // Simple estimate: queue depth * 15 minutes / listeners
  const queueDepth = queueCount || 0;
  return Math.min(Math.ceil(((queueDepth + 1) * 15) / listenerCount), 30);
}

async function notifyListener(
  supabase: SupabaseClient,
  userId: string,
  session: { id: string; session_type: string },
) {
  try {
    await supabase.functions.invoke("send-notification", {
      body: {
        userId,
        title: "New Support Request",
        body:
          session.session_type === "crisis_bridge"
            ? "Someone needs urgent support"
            : "Someone would like to talk",
        data: {
          type: "support_session",
          sessionId: session.id,
        },
      },
    });
  } catch (error) {
    // Log but don't fail the match if notification fails
    console.error("Failed to send notification to listener:", error);
  }
}
