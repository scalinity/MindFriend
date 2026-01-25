// MindFriend Voice Synthesis Edge Function
// Synthesize audio from existing generated_content using ElevenLabs TTS
// Supports re-synthesis with different voice settings

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  createElevenLabsClient,
  estimateDuration,
  DEFAULT_VOICE_ID,
  ElevenLabsError,
} from "../_shared/elevenlabs.ts";
import { checkRateLimit } from "../_shared/ratelimit.ts";

// deno-lint-ignore no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;

// Voice styling presets per content type
const VOICE_STYLE_PRESETS: Record<string, VoiceSettings> = {
  meditation: {
    stability: 0.75,
    similarityBoost: 0.75,
    style: 0.3,
    speed: 0.9,
  },
  sleep_story: {
    stability: 0.8,
    similarityBoost: 0.75,
    style: 0.2,
    speed: 0.85,
  },
  breathing: { stability: 0.7, similarityBoost: 0.75, style: 0.3, speed: 0.85 },
  affirmation: {
    stability: 0.6,
    similarityBoost: 0.75,
    style: 0.4,
    speed: 1.0,
  },
  grounding: { stability: 0.7, similarityBoost: 0.75, style: 0.3, speed: 0.9 },
  mindfulness: {
    stability: 0.75,
    similarityBoost: 0.75,
    style: 0.3,
    speed: 0.9,
  },
  cbt: { stability: 0.5, similarityBoost: 0.75, style: 0.3, speed: 1.0 },
  journaling: { stability: 0.5, similarityBoost: 0.75, style: 0.3, speed: 1.0 },
  default: { stability: 0.5, similarityBoost: 0.75, style: 0.3, speed: 1.0 },
};

interface VoiceSettings {
  stability: number;
  similarityBoost: number;
  style: number;
  speed: number;
}

interface SynthesizeVoiceRequest {
  contentId: string;
  voiceId?: string;
  voiceSettings?: Partial<VoiceSettings>;
}

interface SynthesizeVoiceResponse {
  success: boolean;
  audioUrl?: string;
  durationSeconds?: number;
  voiceSettingsUsed?: {
    voiceId: string;
    stability: number;
    similarityBoost: number;
    style: number;
    speed: number;
    modelId: string;
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
    const presetSettings =
      VOICE_STYLE_PRESETS[contentType] || VOICE_STYLE_PRESETS.default;
    const voiceId = request.voiceId || content.voice_id || DEFAULT_VOICE_ID;

    const finalSettings: VoiceSettings = {
      stability: request.voiceSettings?.stability ?? presetSettings.stability,
      similarityBoost:
        request.voiceSettings?.similarityBoost ??
        presetSettings.similarityBoost,
      style: request.voiceSettings?.style ?? presetSettings.style,
      speed: request.voiceSettings?.speed ?? presetSettings.speed,
    };

    // Validate settings ranges
    if (finalSettings.stability < 0 || finalSettings.stability > 1) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "stability must be between 0 and 1",
          code: "INVALID_REQUEST",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    if (finalSettings.speed < 0.5 || finalSettings.speed > 2.0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "speed must be between 0.5 and 2.0",
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
      const elevenLabs = createElevenLabsClient();

      // Handle long text by chunking if needed
      const maxChars = 5000;
      let processedText = textContent;

      if (textContent.length > maxChars) {
        // For now, truncate to max length with ellipsis warning
        // Future: implement chunking and concatenation
        processedText =
          textContent.substring(0, maxChars - 50) +
          "... (content truncated for synthesis)";
        console.warn(
          `Text truncated from ${textContent.length} to ${maxChars} chars for synthesis`,
        );
      }

      const ttsResult = await elevenLabs.textToSpeech({
        text: processedText,
        voiceId,
        voiceSettings: {
          stability: finalSettings.stability,
          similarityBoost: finalSettings.similarityBoost,
          style: finalSettings.style,
        },
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

      if (ttsError instanceof ElevenLabsError) {
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
    const voiceSettingsUsed = {
      voiceId,
      stability: finalSettings.stability,
      similarityBoost: finalSettings.similarityBoost,
      style: finalSettings.style,
      speed: finalSettings.speed,
      modelId: "eleven_multilingual_v2",
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
