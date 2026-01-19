import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";
import { createLogger } from "../_shared/logger.ts";

const log = createLogger("voice-token");

interface VoiceTokenResponse {
  token: string;
  expires_at: string;
  minutes_remaining: number;
  voice: string;
  is_premium: boolean;
  available_voices: string[];
  session_id: string;
}

interface ErrorResponse {
  error: string;
  code: string;
  minutes_remaining?: number;
  upgrade_required?: boolean;
}

/**
 * Voice Token Edge Function
 * 
 * Generates ephemeral voice tokens for real-time voice conversations.
 * Validates user authentication, checks quota, and creates session records.
 * 
 * Security:
 * - Validates JWT before function invocation (verify_jwt=true in config.toml)
 * - Uses service role key for database operations
 * - Rate limited to 5 requests per minute per user
 * - Tokens expire after 5 minutes
 * 
 * @returns VoiceTokenResponse with ephemeral token and session details
 * @throws ErrorResponse with appropriate error code and HTTP status
 */
serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Create admin client with service role for all operations
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get auth header
    const authHeader = req.headers.get("Authorization");
    log.info("Auth header present", { hasHeader: !!authHeader });

    if (!authHeader) {
      log.warn("Missing authorization header");
      return errorResponse(
        corsHeaders,
        "Missing authorization header",
        "UNAUTHORIZED",
        401,
      );
    }

    const token = authHeader.replace("Bearer ", "");
    log.info("Token extracted", {
      tokenLength: token.length,
    });

    // Validate user token using admin client
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      log.warn("Auth validation failed", {
        hasError: !!authError,
        errorMessage: authError?.message,
        hasUser: !!user,
      });
      return errorResponse(
        corsHeaders,
        authError?.message || "Invalid or expired token",
        "UNAUTHORIZED",
        401,
      );
    }

    log.info("User authenticated", { userId: user.id.slice(0, 8) });

    // Rate limiting check (5 requests per minute to prevent token farming)
    const rateLimitResult = await checkRateLimit(
      supabase,
      user.id,
      "voice-token",
      {
        windowMs: 60 * 1000,
        maxRequests: 5,
      },
    );

    if (!rateLimitResult.allowed) {
      log.warn("Rate limit exceeded for voice-token", {
        userId: user.id.slice(0, 8),
      });
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          code: "RATE_LIMITED",
          retryAfter: rateLimitResult.retryAfter,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    // Run independent database queries in parallel for better performance
    const [quotaResult, subscriptionResult, settingsResult] = await Promise.all([
      supabase.rpc("get_voice_minutes_remaining", { p_user_id: user.id }),
      supabase
        .from("subscriptions")
        .select("status, expires_at")
        .eq("user_id", user.id)
        .eq("status", "active")
        .gt("expires_at", new Date().toISOString())
        .maybeSingle(),
      supabase
        .from("voice_settings")
        .select("preferred_voice")
        .eq("user_id", user.id)
        .maybeSingle(),
    ]);

    // Check quota
    const { data: minutesRemaining, error: quotaError } = quotaResult;
    if (quotaError) {
      log.error("Quota check error", { error: quotaError.message });
      return errorResponse(
        corsHeaders,
        "Failed to check voice quota",
        "QUOTA_ERROR",
        500,
      );
    }

    if (minutesRemaining <= 0) {
      return new Response(
        JSON.stringify({
          error: "Voice quota exceeded",
          code: "QUOTA_EXCEEDED",
          minutes_remaining: 0,
          upgrade_required: true,
        } as ErrorResponse),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check premium status
    const isPremium = !!subscriptionResult.data;

    // Get user's voice preference
    const preferredVoice = settingsResult.data?.preferred_voice || "ara";
    const voice = isPremium ? preferredVoice : "ara";
    const availableVoices = isPremium
      ? ["ara", "rex", "sal", "eve", "leo"]
      : ["ara"];

    // Generate ephemeral token from xAI
    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiApiKey) {
      return errorResponse(
        corsHeaders,
        "Voice service not configured",
        "CONFIG_ERROR",
        500,
      );
    }

    let xaiResponse: Response;
    try {
      xaiResponse = await fetch(
        "https://api.x.ai/v1/realtime/client_secrets",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${xaiApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            expires_after: { seconds: 300 }, // 5 minutes
          }),
          signal: AbortSignal.timeout(10000), // 10-second timeout
        },
      );
    } catch (error) {
      // Handle timeout or network errors
      const errorMessage = error instanceof Error ? error.message : "Unknown error";
      log.error("xAI API request failed", { error: errorMessage });
      
      if (errorMessage.includes("timeout") || errorMessage.includes("abort")) {
        return errorResponse(
          corsHeaders,
          "Voice service timeout - please try again",
          "XAI_TIMEOUT",
          504,
        );
      }
      
      return errorResponse(
        corsHeaders,
        "Failed to initialize voice session",
        "XAI_ERROR",
        502,
      );
    }

    if (!xaiResponse.ok) {
      log.error("xAI token request failed", {
        status: xaiResponse.status,
        statusText: xaiResponse.statusText,
      });
      return errorResponse(
        corsHeaders,
        "Failed to initialize voice session",
        "XAI_ERROR",
        502,
      );
    }

    const xaiData = await xaiResponse.json();

    // Extract token - xAI returns { value: "...", expires_at: ... } directly
    const voiceToken =
      xaiData.value || xaiData.client_secret?.value || xaiData.client_secret;
    const expiresAt = xaiData.expires_at || xaiData.client_secret?.expires_at;

    if (!voiceToken) {
      log.error("No token in xAI response", {
        hasValue: !!xaiData?.value,
        hasClientSecret: !!xaiData?.client_secret,
        keys: Object.keys(xaiData || {}),
      });
      return errorResponse(
        corsHeaders,
        "Invalid response from voice service",
        "XAI_ERROR",
        502,
      );
    }

    // Create voice session record
    const { data: sessionId, error: sessionError } = await supabase.rpc(
      "create_voice_session",
      {
        p_user_id: user.id,
        p_voice: voice,
      },
    );

    if (sessionError) {
      log.error("Session creation failed", { 
        error: sessionError.message,
        userId: user.id.slice(0, 8),
      });
      return errorResponse(
        corsHeaders,
        "Failed to create voice session",
        "SESSION_ERROR",
        500,
      );
    }

    if (!sessionId) {
      log.error("Session creation returned no ID", { 
        userId: user.id.slice(0, 8),
      });
      return errorResponse(
        corsHeaders,
        "Failed to create voice session",
        "SESSION_ERROR",
        500,
      );
    }

    const response: VoiceTokenResponse = {
      token: voiceToken,
      expires_at: String(expiresAt),
      minutes_remaining: minutesRemaining,
      voice,
      is_premium: isPremium,
      available_voices: availableVoices,
      session_id: sessionId,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    log.error("Voice token error", {
      error: error instanceof Error ? error.message : "Unknown error",
    });
    return errorResponse(
      corsHeaders,
      error instanceof Error ? error.message : "Unknown error",
      "INTERNAL_ERROR",
      500,
    );
  }
});

/**
 * Creates a standardized error response with CORS headers
 * 
 * @param corsHeaders - CORS headers for the response
 * @param message - Human-readable error message
 * @param code - Machine-readable error code (e.g., "UNAUTHORIZED", "QUOTA_EXCEEDED")
 * @param status - HTTP status code
 * @returns Response object with error details and appropriate headers
 */
function errorResponse(
  corsHeaders: Record<string, string>,
  message: string,
  code: string,
  status: number,
): Response {
  return new Response(
    JSON.stringify({ error: message, code } as ErrorResponse),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}
