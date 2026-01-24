import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

console.log("[voice-token] Module loaded");

interface VoiceTokenResponse {
  token: string;
  expires_at: string;
  minutes_remaining: number;
  voice: string;
  is_premium: boolean;
  available_voices: string[];
  session_id: string;
}

// Simple CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

serve(async (req) => {
  console.log("[voice-token] Request received");

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const xaiApiKey = Deno.env.get("XAI_API_KEY");

    console.log("[voice-token] Env check:", {
      hasUrl: !!supabaseUrl,
      hasKey: !!supabaseKey,
      hasXai: !!xaiApiKey,
    });

    if (!supabaseUrl || !supabaseKey) {
      return new Response(
        JSON.stringify({
          error: "Server configuration error",
          code: "CONFIG_ERROR",
        }),
        { status: 500, headers: corsHeaders },
      );
    }

    // Create Supabase client
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Validate auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: "Missing authorization header",
          code: "UNAUTHORIZED",
        }),
        { status: 401, headers: corsHeaders },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      console.log("[voice-token] Auth failed:", authError?.message);
      return new Response(
        JSON.stringify({
          error: authError?.message || "Invalid token",
          code: "UNAUTHORIZED",
        }),
        { status: 401, headers: corsHeaders },
      );
    }

    console.log("[voice-token] User authenticated:", user.id.slice(0, 8));

    // Check quota
    const { data: minutesRemaining, error: quotaError } = await supabase.rpc(
      "get_voice_minutes_remaining",
      { p_user_id: user.id },
    );

    if (quotaError) {
      console.log("[voice-token] Quota check error:", quotaError.message);
      return new Response(
        JSON.stringify({
          error: `Quota check failed: ${quotaError.message}`,
          code: "QUOTA_ERROR",
        }),
        { status: 500, headers: corsHeaders },
      );
    }

    console.log("[voice-token] Minutes remaining:", minutesRemaining);

    if (minutesRemaining <= 0) {
      return new Response(
        JSON.stringify({
          error: "Voice quota exceeded",
          code: "QUOTA_EXCEEDED",
          minutes_remaining: 0,
          upgrade_required: true,
        }),
        { status: 403, headers: corsHeaders },
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
    const voice = "ara";
    const availableVoices = isPremium
      ? ["ara", "rex", "sal", "eve", "leo"]
      : ["ara"];

    // Get xAI token
    if (!xaiApiKey) {
      return new Response(
        JSON.stringify({
          error: "Voice service not configured",
          code: "CONFIG_ERROR",
        }),
        { status: 500, headers: corsHeaders },
      );
    }

    console.log("[voice-token] Calling xAI API...");

    const xaiResponse = await fetch(
      "https://api.x.ai/v1/realtime/client_secrets",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${xaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ expires_after: { seconds: 300 } }),
      },
    );

    if (!xaiResponse.ok) {
      console.log("[voice-token] xAI error:", xaiResponse.status);
      return new Response(
        JSON.stringify({
          error: "Failed to initialize voice session",
          code: "XAI_ERROR",
        }),
        { status: 502, headers: corsHeaders },
      );
    }

    const xaiData = await xaiResponse.json();
    const voiceToken = xaiData.value || xaiData.client_secret?.value;
    const expiresAt = xaiData.expires_at || xaiData.client_secret?.expires_at;

    if (!voiceToken) {
      console.log(
        "[voice-token] No token in xAI response:",
        Object.keys(xaiData),
      );
      return new Response(
        JSON.stringify({
          error: "Invalid response from voice service",
          code: "XAI_ERROR",
        }),
        { status: 502, headers: corsHeaders },
      );
    }

    console.log("[voice-token] Got xAI token, creating session...");

    // Create session
    const { data: sessionId, error: sessionError } = await supabase.rpc(
      "create_voice_session",
      { p_user_id: user.id, p_voice: voice },
    );

    if (sessionError || !sessionId) {
      console.log("[voice-token] Session error:", sessionError?.message);
      return new Response(
        JSON.stringify({
          error: sessionError?.message || "Failed to create session",
          code: "SESSION_ERROR",
        }),
        { status: 500, headers: corsHeaders },
      );
    }

    console.log("[voice-token] Success!");

    const response: VoiceTokenResponse = {
      token: voiceToken,
      expires_at: String(expiresAt),
      minutes_remaining: minutesRemaining,
      voice,
      is_premium: isPremium,
      available_voices: availableVoices,
      session_id: String(sessionId),
    };

    return new Response(JSON.stringify(response), { headers: corsHeaders });
  } catch (error) {
    console.error("[voice-token] Error:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
        code: "INTERNAL_ERROR",
      }),
      { status: 500, headers: corsHeaders },
    );
  }
});
