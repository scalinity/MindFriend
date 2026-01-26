// MindFriend Voice Synthesis Edge Function
// Synthesize audio from existing generated_content using Google Cloud TTS
// Supports re-synthesis with different voice settings

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  createGoogleTTSClient,
  estimateDuration,
  DEFAULT_VOICE_ID,
  GoogleTTSError,
  GOOGLE_VOICE_PRESETS,
} from "../_shared/google-tts.ts";
import { checkRateLimit } from "../_shared/ratelimit.ts";

// deno-lint-ignore no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;

interface SynthesizeVoiceRequest {
  contentId: string;
  voiceId?: string; // Content-type preset key (e.g., "meditation", "breathing")
  voiceSettings?: {
    speakingRate?: number; // 0.25-4.0 (Google TTS range)
    pitch?: number; // -20.0 to 20.0 semitones
    // Legacy ElevenLabs params (ignored, kept for backward compat)
    stability?: number;
    similarityBoost?: number;
    style?: number;
    speed?: number;
  };
}

interface SynthesizeVoiceResponse {
  success: boolean;
  audioUrl?: string;
  durationSeconds?: number;
  voiceSettingsUsed?: {
    voiceId: string;
    voiceName: string;
    speakingRate: number;
    pitch: number;
    provider: string;
  };
  error?: string;
  code?: string;
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
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing authorization",
          code: "UNAUTHORIZED",
        }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");

    // Create Supabase clients
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
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
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid authentication",
          code: "UNAUTHORIZED",
        }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting (pass supabaseAdmin as first arg per checkRateLimit signature)
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "voice_synthesis",
    );
    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Too many requests. Please wait a moment.",
          code: "RATE_LIMIT_EXCEEDED",
        }),
        {
          status: 429,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check premium status - ElevenLabs voice synthesis is PREMIUM ONLY
    // Free tier users use native iOS AVSpeechSynthesizer instead (zero cost)
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("subscription_tier")
      .eq("id", user.id)
      .single();

    const isPremium =
      profile?.subscription_tier === "premium" ||
      profile?.subscription_tier === "family";

    // PREMIUM GATE: Block free tier users from ElevenLabs synthesis
    if (!isPremium) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "Professional voice synthesis is a Premium feature. Upgrade to unlock studio-quality voices!",
          code: "PREMIUM_REQUIRED",
          upgradeRequired: true,
        }),
        {
          status: 403,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Premium users: Check daily quota to prevent runaway costs (20/day cap)
    const { data: quotaResult, error: quotaError } = await supabaseAdmin.rpc(
      "check_and_increment_synthesis_quota",
      {
        p_user_id: user.id,
        p_is_premium: isPremium,
      },
    );

    if (quotaError) {
      console.error("Synthesis quota check error:", quotaError);
      // Fail closed on quota check errors to prevent abuse
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to check synthesis quota",
          code: "QUOTA_CHECK_ERROR",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const quota = quotaResult?.[0] || {
      allowed: false,
      quota_used: 0,
      quota_limit: 20,
    };

    if (!quota.allowed) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "Daily voice synthesis limit reached (20/day). Your limit resets tomorrow.",
          code: "SYNTHESIS_QUOTA_EXCEEDED",
          quotaUsed: quota.quota_used,
          quotaLimit: quota.quota_limit,
        }),
        {
          status: 429,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request
    const request: SynthesizeVoiceRequest = await req.json();

    // Validate contentId format (must be valid UUID)
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!request.contentId || !uuidRegex.test(request.contentId)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Valid contentId is required",
          code: "INVALID_REQUEST",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate voiceId format if provided (alphanumeric only to prevent injection)
    if (request.voiceId && !/^[a-zA-Z0-9_-]+$/.test(request.voiceId)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid voice ID format",
          code: "INVALID_REQUEST",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch content from database
    const { data: content, error: fetchError } = await supabaseAdmin
      .from("generated_content")
      .select("id, user_id, text_content, content_type, voice_id")
      .eq("id", request.contentId)
      .single();

    if (fetchError || !content) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Content not found",
          code: "NOT_FOUND",
        }),
        {
          status: 404,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify ownership
    if (content.user_id !== user.id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Access denied",
          code: "FORBIDDEN",
        }),
        {
          status: 403,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate text content
    const textContent = content.text_content;
    if (!textContent || textContent.trim().length < 10) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Content text too short for synthesis",
          code: "INVALID_CONTENT",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Determine voice settings
    const contentType = content.content_type || "default";
    const preset =
      GOOGLE_VOICE_PRESETS[contentType] || GOOGLE_VOICE_PRESETS.default;
    const voiceId = request.voiceId || content.voice_id || DEFAULT_VOICE_ID;

    // Resolve speaking rate: prefer explicit request > legacy speed param > preset default
    const speakingRate =
      request.voiceSettings?.speakingRate ??
      request.voiceSettings?.speed ??
      preset.speakingRate;
    const pitch = request.voiceSettings?.pitch ?? preset.pitch;

    // Validate settings ranges (Google TTS limits)
    if (speakingRate < 0.25 || speakingRate > 4.0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "speakingRate must be between 0.25 and 4.0",
          code: "INVALID_REQUEST",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    if (pitch < -20.0 || pitch > 20.0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "pitch must be between -20.0 and 20.0",
          code: "INVALID_REQUEST",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Synthesize voice
    let audioUrl: string;
    let durationSeconds: number;

    try {
      const googleTTS = createGoogleTTSClient();

      // Handle long text by truncating if needed (Google limit: 5000 bytes)
      const maxBytes = 4500; // Safe margin under 5000 byte limit
      let processedText = textContent;
      const textBytes = new TextEncoder().encode(textContent);

      if (textBytes.length > maxBytes) {
        // Truncate by decoding back from byte limit
        const truncatedBytes = textBytes.slice(0, maxBytes);
        processedText =
          new TextDecoder().decode(truncatedBytes).slice(0, -10) +
          "... (content truncated for synthesis)";
        console.warn(
          `Text truncated from ${textBytes.length} to ~${maxBytes} bytes for synthesis`,
        );
      }

      // Use the content-type preset key as voiceId for Google TTS
      // Google TTS client resolves preset key → voice name internally
      const resolvedVoiceId =
        GOOGLE_VOICE_PRESETS[voiceId] ? voiceId : contentType;

      const ttsResult = await googleTTS.textToSpeech({
        text: processedText,
        voiceId: resolvedVoiceId,
      });

      // Upload to Supabase Storage
      const fileName = `${user.id}/${content.id}.mp3`;
      const { error: uploadError } = await supabaseAdmin.storage
        .from("generated-audio")
        .upload(fileName, ttsResult.audioData, {
          contentType: ttsResult.contentType,
          upsert: true, // Allow re-synthesis to overwrite
        });

      if (uploadError) {
        console.error("Audio upload error:", uploadError);
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to save audio file",
            code: "STORAGE_ERROR",
          }),
          {
            status: 500,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Get public URL
      const { data: urlData } = supabaseAdmin.storage
        .from("generated-audio")
        .getPublicUrl(fileName);

      audioUrl = urlData?.publicUrl || "";
      durationSeconds = estimateDuration(processedText);
    } catch (ttsError) {
      console.error("TTS error:", ttsError);

      if (ttsError instanceof GoogleTTSError) {
        if (ttsError.code === "RATE_LIMIT_EXCEEDED") {
          return new Response(
            JSON.stringify({
              success: false,
              error: "Voice synthesis rate limit reached",
              code: "RATE_LIMIT_EXCEEDED",
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
        if (ttsError.code === "UNAUTHORIZED") {
          return new Response(
            JSON.stringify({
              success: false,
              error: "Voice synthesis service unavailable",
              code: "SERVICE_ERROR",
            }),
            {
              status: 503,
              headers: {
                ...baseCorsHeaders,
                "Content-Type": "application/json",
              },
            },
          );
        }
      }

      return new Response(
        JSON.stringify({
          success: false,
          error: "Voice synthesis failed",
          code: "SYNTHESIS_ERROR",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build voice settings used record
    const resolvedPreset =
      GOOGLE_VOICE_PRESETS[voiceId] ||
      GOOGLE_VOICE_PRESETS[contentType] ||
      GOOGLE_VOICE_PRESETS.default;
    const voiceSettingsUsed = {
      voiceId,
      voiceName: resolvedPreset.voiceName,
      speakingRate,
      pitch,
      provider: "google-cloud-tts-standard",
    };

    // Update database with new audio URL and settings
    const { error: updateError } = await supabaseAdmin
      .from("generated_content")
      .update({
        audio_url: audioUrl,
        voice_id: voiceId,
        voice_settings_used: voiceSettingsUsed,
        duration: durationSeconds,
        updated_at: new Date().toISOString(),
      })
      .eq("id", content.id);

    if (updateError) {
      console.error("Database update error:", updateError);
      // Non-fatal - audio was synthesized and uploaded successfully
    }

    // Return success
    const response: SynthesizeVoiceResponse = {
      success: true,
      audioUrl,
      durationSeconds,
      voiceSettingsUsed,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    // Log full error details server-side only
    console.error("synthesize-voice error:", error);

    // Return generic message to client to avoid leaking internal details
    return new Response(
      JSON.stringify({
        success: false,
        error: "An unexpected error occurred. Please try again.",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
