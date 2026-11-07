import { refreshPremiumAccess } from "../_shared/entitlement.ts";
// MindFriend Voice Synthesis Edge Function
// Synthesize audio from existing generated_content using Google Cloud TTS
// Supports re-synthesis with different voice settings

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  createGoogleTTSClient,
  DEFAULT_VOICE_ID,
  estimateDuration,
  GOOGLE_VOICE_PRESETS,
  GoogleTTSError,
} from "../_shared/google-tts.ts";
import { checkRateLimit } from "../_shared/ratelimit.ts";
import {
  MonthlyAIBudgetExhaustedError,
  MonthlyAIBudgetUnavailableError,
} from "../_shared/monthly-ai-budget.ts";

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

Deno.serve(async (req) => {
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

    // Check premium status - Google Cloud TTS voice synthesis is PREMIUM ONLY
    // Free tier users use native iOS AVSpeechSynthesizer instead (zero cost)
    const isPremium = await refreshPremiumAccess(supabaseAdmin, user.id);

    // PREMIUM GATE: Block free tier users from server-side TTS synthesis
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

    // ── Monthly TTS Budget Check ($5/month cap = 1,250,000 chars) ──
    const charCount = textContent.length;
    const { data: budgetResult, error: budgetError } = await supabaseAdmin.rpc(
      "check_tts_monthly_budget",
      {
        p_user_id: user.id,
        p_character_count: charCount,
      },
    );

    if (budgetError) {
      console.error("[synthesize-voice] Operation failed");
      // Fail closed on budget check errors to prevent overrun
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to check synthesis budget",
          code: "BUDGET_CHECK_ERROR",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const budget = budgetResult?.[0];
    if (!budget?.allowed) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "Monthly voice synthesis budget reached. Your budget resets next month. Content is still available as text.",
          code: "MONTHLY_BUDGET_EXCEEDED",
          charsUsed: budget?.chars_used ?? 0,
          charsLimit: budget?.chars_limit ?? 0,
          charsRemaining: budget?.chars_remaining ?? 0,
        }),
        {
          status: 429,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Debit the daily allowance only after global monthly admission. Keep this
    // callback once-only if a synthesis attempt is retried in this invocation.
    let synthesisQuotaReserved = false;
    const reserveSynthesisQuota = async (signal: AbortSignal) => {
      if (synthesisQuotaReserved) return;
      const { data: quotaResult, error: quotaError } = await supabaseAdmin.rpc(
        "check_and_increment_synthesis_quota",
        {
          p_user_id: user.id,
          p_is_premium: isPremium,
          p_character_count: charCount,
        },
      ).abortSignal(signal);

      if (quotaError) {
        console.error("[synthesize-voice] Operation failed");
        // Fail closed on quota check errors to prevent abuse
        throw new Response(
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
        quota_limit: 10,
      };

      if (!quota.allowed) {
        throw new Response(
          JSON.stringify({
            success: false,
            error:
              "Daily voice synthesis limit reached (10/day). Your limit resets tomorrow.",
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

      synthesisQuotaReserved = true;
    };

    // Determine voice settings
    const contentType = content.content_type || "default";
    const preset = GOOGLE_VOICE_PRESETS[contentType] ||
      GOOGLE_VOICE_PRESETS.default;
    const voiceId = request.voiceId || content.voice_id || DEFAULT_VOICE_ID;

    // Resolve speaking rate: prefer explicit request > legacy speed param > preset default
    const speakingRate = request.voiceSettings?.speakingRate ??
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
    let audioObjectURL: string;
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
        processedText = new TextDecoder().decode(truncatedBytes).slice(0, -10) +
          "... (content truncated for synthesis)";
        console.warn(
          `Text truncated from ${textBytes.length} to ~${maxBytes} bytes for synthesis`,
        );
      }

      // Use the content-type preset key as voiceId for Google TTS
      // Google TTS client resolves preset key → voice name internally
      const resolvedVoiceId = GOOGLE_VOICE_PRESETS[voiceId]
        ? voiceId
        : contentType;

      const ttsResult = await googleTTS.textToSpeech({
        text: processedText,
        voiceId: resolvedVoiceId,
      }, {
        budget: {
          admin: supabaseAdmin,
          userId: user.id,
          feature: "voice.tts",
        },
        signal: req.signal,
        beforeProvider: reserveSynthesisQuota,
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
        console.error("[synthesize-voice] Operation failed");
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

      const { data: urlData, error: signingError } = await supabaseAdmin.storage
        .from("generated-audio").createSignedUrl(fileName, 3600);
      if (signingError || !urlData?.signedUrl) {
        throw new Error("Unable to authorize audio access");
      }
      audioUrl = urlData.signedUrl;
      audioObjectURL = `${
        Deno.env.get("SUPABASE_URL")
      }/storage/v1/object/public/generated-audio/${fileName}`;
      durationSeconds = estimateDuration(processedText);
    } catch (ttsError) {
      if (ttsError instanceof Response) return ttsError;
      console.error("[synthesize-voice] Synthesis failed");

      if (
        ttsError instanceof MonthlyAIBudgetExhaustedError ||
        ttsError instanceof MonthlyAIBudgetUnavailableError
      ) {
        const exhausted = ttsError instanceof MonthlyAIBudgetExhaustedError;
        return new Response(
          JSON.stringify({
            success: false,
            error: exhausted
              ? "Monthly AI budget reached"
              : "AI budget unavailable",
            code: ttsError.code,
          }),
          {
            status: exhausted ? 429 : 503,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }

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
    const resolvedPreset = GOOGLE_VOICE_PRESETS[voiceId] ||
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
    const { data: savedContent, error: updateError } = await supabaseAdmin
      .from("generated_content")
      .update({
        audio_url: audioObjectURL,
        voice_id: voiceId,
        voice_settings_used: voiceSettingsUsed,
        duration_seconds: durationSeconds,
        updated_at: new Date().toISOString(),
      })
      .eq("id", content.id)
      .eq("user_id", user.id)
      .select("id")
      .single();

    if (updateError || !savedContent) {
      console.error("[synthesize-voice] Operation failed");
      return new Response(
        JSON.stringify({
          success: false,
          error: "Unable to save audio history",
          code: "DATABASE_ERROR",
        }),
        {
          status: 503,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
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
  } catch {
    // Log full error details server-side only
    console.error("[synthesize-voice] Operation failed");

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
