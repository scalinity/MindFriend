// ElevenLabs Text-to-Speech API Integration
// Docs: https://docs.elevenlabs.io/api-reference/text-to-speech

export interface ElevenLabsConfig {
  apiKey: string;
  baseUrl?: string;
}

export interface Voice {
  id: string;
  name: string;
  gender: "male" | "female" | "neutral";
  style: string;
  language: string;
}

export interface TTSRequest {
  text: string;
  voiceId: string;
  modelId?: string;
  voiceSettings?: {
    stability?: number; // 0-1, default 0.5
    similarityBoost?: number; // 0-1, default 0.75
    style?: number; // 0-1, default 0
    useSpeakerBoost?: boolean;
  };
  outputFormat?: "mp3_44100_128" | "mp3_44100_64" | "pcm_16000";
}

export interface TTSResponse {
  audioData: Uint8Array;
  contentType: string;
  durationMs?: number;
  characterCount: number;
}

// Default voices available in ElevenLabs (free tier has limited access)
export const ELEVENLABS_VOICES: Record<string, Voice> = {
  sarah: {
    id: "EXAVITQu4vr4xnSDxMaL",
    name: "Sarah",
    gender: "female",
    style: "calm",
    language: "en",
  },
  josh: {
    id: "TxGEqnHWrfWFTfGW9XjX",
    name: "Josh",
    gender: "male",
    style: "warm",
    language: "en",
  },
  adam: {
    id: "pNInz6obpgDQGcFmaJgB",
    name: "Adam",
    gender: "male",
    style: "deep",
    language: "en",
  },
  rachel: {
    id: "21m00Tcm4TlvDq8ikWAM",
    name: "Rachel",
    gender: "female",
    style: "soothing",
    language: "en",
  },
  elli: {
    id: "MF3mGyEYCl7XYWbV9V6O",
    name: "Elli",
    gender: "female",
    style: "whisper",
    language: "en",
  },
};

export const DEFAULT_VOICE_ID = ELEVENLABS_VOICES.sarah.id;
export const DEFAULT_MODEL_ID = "eleven_multilingual_v2";

export class ElevenLabsClient {
  private config: ElevenLabsConfig;
  private baseUrl: string;

  constructor(config: ElevenLabsConfig) {
    this.config = config;
    this.baseUrl = config.baseUrl || "https://api.elevenlabs.io/v1";
  }

  /**
   * Convert text to speech using ElevenLabs API
   */
  async textToSpeech(request: TTSRequest): Promise<TTSResponse> {
    const {
      text,
      voiceId,
      modelId = DEFAULT_MODEL_ID,
      voiceSettings = {},
      outputFormat = "mp3_44100_128",
    } = request;

    // Validate text length (ElevenLabs has a limit)
    if (text.length > 5000) {
      throw new ElevenLabsError(
        "Text too long",
        "TEXT_TOO_LONG",
        `Text length ${text.length} exceeds maximum of 5000 characters`,
      );
    }

    const url = `${this.baseUrl}/text-to-speech/${voiceId}?output_format=${outputFormat}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": this.config.apiKey,
      },
      body: JSON.stringify({
        text,
        model_id: modelId,
        voice_settings: {
          stability: voiceSettings.stability ?? 0.5,
          similarity_boost: voiceSettings.similarityBoost ?? 0.75,
          style: voiceSettings.style ?? 0,
          use_speaker_boost: voiceSettings.useSpeakerBoost ?? true,
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      let errorMessage = `ElevenLabs API error: ${response.status}`;
      let errorCode = "API_ERROR";

      try {
        const errorJson = JSON.parse(errorText);
        errorMessage =
          errorJson.detail?.message || errorJson.detail || errorMessage;

        if (response.status === 401) {
          errorCode = "UNAUTHORIZED";
        } else if (response.status === 429) {
          errorCode = "RATE_LIMIT_EXCEEDED";
        } else if (response.status === 400) {
          errorCode = "INVALID_REQUEST";
        }
      } catch {
        // Use default error message
      }

      throw new ElevenLabsError(errorMessage, errorCode, errorText);
    }

    const audioData = new Uint8Array(await response.arrayBuffer());
    const contentType = response.headers.get("content-type") || "audio/mpeg";

    return {
      audioData,
      contentType,
      characterCount: text.length,
    };
  }

  /**
   * Get available voices from ElevenLabs
   */
  async getVoices(): Promise<Voice[]> {
    const url = `${this.baseUrl}/voices`;

    const response = await fetch(url, {
      headers: {
        "xi-api-key": this.config.apiKey,
      },
    });

    if (!response.ok) {
      throw new ElevenLabsError(
        `Failed to fetch voices: ${response.status}`,
        "API_ERROR",
      );
    }

    const data = await response.json();
    return data.voices.map(
      (v: {
        voice_id: string;
        name: string;
        labels?: { gender?: string };
      }) => ({
        id: v.voice_id,
        name: v.name,
        gender: v.labels?.gender || "neutral",
        style: "default",
        language: "en",
      }),
    );
  }

  /**
   * Get user's subscription info and usage
   */
  async getSubscriptionInfo(): Promise<{
    characterCount: number;
    characterLimit: number;
    canUseInstantVoiceCloning: boolean;
    tier: string;
  }> {
    const url = `${this.baseUrl}/user/subscription`;

    const response = await fetch(url, {
      headers: {
        "xi-api-key": this.config.apiKey,
      },
    });

    if (!response.ok) {
      throw new ElevenLabsError(
        `Failed to fetch subscription: ${response.status}`,
        "API_ERROR",
      );
    }

    const data = await response.json();
    return {
      characterCount: data.character_count,
      characterLimit: data.character_limit,
      canUseInstantVoiceCloning: data.can_use_instant_voice_cloning,
      tier: data.tier,
    };
  }
}

export class ElevenLabsError extends Error {
  code: string;
  details?: string;

  constructor(message: string, code: string, details?: string) {
    super(message);
    this.name = "ElevenLabsError";
    this.code = code;
    this.details = details;
  }
}

/**
 * Create an ElevenLabs client using environment variables
 */
export function createElevenLabsClient(): ElevenLabsClient {
  const apiKey = Deno.env.get("ELEVENLABS_API_KEY");

  if (!apiKey) {
    throw new Error("ELEVENLABS_API_KEY environment variable is not set");
  }

  return new ElevenLabsClient({ apiKey });
}

/**
 * Estimate cost for text-to-speech generation
 * ElevenLabs pricing: approximately $0.30 per 1000 characters
 */
export function estimateTTSCost(characterCount: number): number {
  const costPerThousandChars = 0.3;
  return (characterCount / 1000) * costPerThousandChars;
}

/**
 * Calculate approximate duration from text length
 * Average speaking rate: ~150 words per minute, ~5 characters per word
 */
export function estimateDuration(text: string): number {
  const wordsPerMinute = 150;
  const charsPerWord = 5;
  const words = text.length / charsPerWord;
  const minutes = words / wordsPerMinute;
  return Math.ceil(minutes * 60); // Return seconds
}
