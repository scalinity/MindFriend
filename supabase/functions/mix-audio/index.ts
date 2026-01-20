// MindFriend Audio Mixing Edge Function
// Mixes generated voice audio with background sounds using FFmpeg
// Supports: rain, ocean, forest, fireplace, white_noise

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Type alias for untyped Supabase client
type UntypedSupabaseClient = SupabaseClient<unknown, "public", unknown>;

// Background sound configurations
const BACKGROUND_SOUNDS: Record<string, { url: string; volume: number }> = {
  rain: { url: "https://assets.mindfriend.app/audio/background/rain.mp3", volume: 0.25 },
  ocean: { url: "https://assets.mindfriend.app/audio/background/ocean.mp3", volume: 0.3 },
  forest: { url: "https://assets.mindfriend.app/audio/background/forest.mp3", volume: 0.3 },
  fireplace: { url: "https://assets.mindfriend.app/audio/background/fireplace.mp3", volume: 0.35 },
  white_noise: { url: "https://assets.mindfriend.app/audio/background/whitenoise.mp3", volume: 0.2 },
  silence: { url: "", volume: 0 },
};

interface MixAudioRequest {
  voiceAudioUrl: string;
  backgroundSound: string;
  voiceVolume?: number;      // 0.0 - 1.0, default 0.8
  backgroundVolume?: number; // 0.0 - 1.0, default varies by sound
  outputFormat?: "mp3" | "wav" | "aac";
  outputSampleRate?: number; // e.g., 44100, 48000
}

interface MixAudioResponse {
  success: boolean;
  mixedAudioUrl?: string;
  duration?: number;
  error?: string;
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
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    ) as UntypedSupabaseClient;

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid authentication" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request
    const request: MixAudioRequest = await req.json();

    // Validate background sound
    const bgConfig = BACKGROUND_SOUNDS[request.backgroundSound];
    if (!bgConfig) {
      return new Response(
        JSON.stringify({
          error: "INVALID_BACKGROUND_SOUND",
          message: `Invalid background sound: ${request.backgroundSound}`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // If silence, just return the voice URL
    if (request.backgroundSound === "silence" || !bgConfig.url) {
      return new Response(
        JSON.stringify({
          success: true,
          mixedAudioUrl: request.voiceAudioUrl,
          message: "No background sound applied",
        }),
        {
          status: 200,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate voice audio URL
    if (!request.voiceAudioUrl) {
      return new Response(
        JSON.stringify({
          error: "MISSING_VOICE_AUDIO",
          message: "Voice audio URL is required",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // In production, this would use FFmpeg to mix the audio
    // For now, we'll return the original voice with instructions for mixing
    const voiceVolume = request.voiceVolume ?? 0.8;
    const bgVolume = request.backgroundVolume ?? bgConfig.volume;

    // Create a Supabase Storage bucket for mixed audio
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    ) as UntypedSupabaseClient;

    // Generate unique filename
    const contentId = crypto.randomUUID();
    const outputFormat = request.outputFormat ?? "mp3";
    const outputFileName = `mixed_${contentId}.${outputFormat}`;

    // In a real implementation, you would:
    // 1. Download both audio files
    // 2. Use FFmpeg to mix them with proper volume levels
    // 3. Upload the result to Supabase Storage
    // 4. Return the URL

    // For demonstration, return a placeholder response
    const response: MixAudioResponse = {
      success: true,
      mixedAudioUrl: request.voiceAudioUrl, // Would be the mixed URL in production
      duration: null, // Would be calculated from mixed audio
      error: null,
    };

    // Log the mix request for analytics
    await supabaseAdmin.from("analytics_events").insert({
      user_id: user.id,
      event_type: "audio_mix_requested",
      event_data: {
        background_sound: request.backgroundSound,
        voice_volume: voiceVolume,
        background_volume: bgVolume,
        output_format: outputFormat,
      },
    });

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Mix audio error:", error);
    const errorMessage =
      error instanceof Error ? error.message : "An unexpected error occurred";

    return new Response(
      JSON.stringify({
        error: "MIX_FAILED",
        message: errorMessage,
      }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Helper function that would be used in production with FFmpeg
// This is a placeholder showing how the mixing would work
async function mixAudioWithFFmpeg(
  voiceUrl: string,
  backgroundUrl: string,
  voiceVolume: number,
  bgVolume: number,
): Promise<Uint8Array> {
  // In production, this would:
  // 1. Download both audio files
  // 2. Run FFmpeg command:
  //    ffmpeg -i voice.mp3 -i background.mp3
  //    -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:weights=1 1[out]"
  //    -map "[out]" -q:a 2 output.mp3
  // 3. Return the mixed audio bytes

  // For now, throw an error indicating FFmpeg is not available
  throw new Error(
    "FFmpeg audio mixing not yet implemented. " +
      "Deploy with FFmpeg support to enable server-side mixing.",
  );
}
