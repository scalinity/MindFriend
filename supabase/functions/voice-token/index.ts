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

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");

    if (!authHeader) {
      return errorResponse(
        corsHeaders,
        "Missing authorization header",
        "UNAUTHORIZED",
        401,
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return errorResponse(
        corsHeaders,
        "Invalid or expired token",
        "UNAUTHORIZED",
        401,
      );
    }

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

    // Check voice quota
    const { data: minutesRemaining, error: quotaError } = await supabase.rpc(
      "get_voice_minutes_remaining",
      { p_user_id: user.id },
    );

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
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status, expires_at")
      .eq("user_id", user.id)
      .eq("status", "active")
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();

    const isPremium = !!subscription;

    // Get user's voice preference
    const { data: settings } = await supabase
      .from("voice_settings")
      .select("preferred_voice")
      .eq("user_id", user.id)
      .maybeSingle();

    // Determine voice (non-premium users locked to 'ara')
    const preferredVoice = settings?.preferred_voice || "ara";
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

    const xaiResponse = await fetch(
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
      },
    );

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
      log.error("Session creation error", { error: sessionError.message });
    }

    const response: VoiceTokenResponse = {
      token: voiceToken,
      expires_at: String(expiresAt),
      minutes_remaining: minutesRemaining,
      voice,
      is_premium: isPremium,
      available_voices: availableVoices,
      session_id: sessionId || "",
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
