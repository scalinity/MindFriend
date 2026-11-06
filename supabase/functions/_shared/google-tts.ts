// Google Cloud Text-to-Speech API Integration
// Standard voices: $4 per 1M characters
// Chirp 3 HD voices: $30 per 1M characters (higher quality, more natural)
// Docs: https://cloud.google.com/text-to-speech/docs/chirp3-hd

import {
  type MonthlyAIBudgetAdmin,
  MonthlyAIBudgetUnavailableError,
  reserveMonthlyAIBudget,
} from "./monthly-ai-budget.ts";

const GOOGLE_TTS_API_URL =
  "https://texttospeech.googleapis.com/v1/text:synthesize";

// Chirp 3 HD uses v1beta1 endpoint for some features
const GOOGLE_TTS_V1BETA1_URL =
  "https://texttospeech.googleapis.com/v1beta1/text:synthesize";

// Max input size: 5000 bytes UTF-8
const MAX_TEXT_BYTES = 5000;

// ─── Interfaces ──────────────────────────────────────────────

export interface GoogleTTSConfig {
  apiKey: string;
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
  ssml?: string; // SSML input (takes priority over text when provided)
  voiceId: string;
  useChirp3HD?: boolean; // Use premium Chirp 3 HD voices
  voiceSettings?: {
    stability?: number;
    similarityBoost?: number;
    style?: number;
    useSpeakerBoost?: boolean;
  };
}

export interface TTSResponse {
  audioData: Uint8Array;
  contentType: string;
  durationMs?: number;
  characterCount: number;
}

export interface GoogleTTSOptions {
  budget: {
    admin: MonthlyAIBudgetAdmin;
    userId: string;
    feature: "voice.tts" | "meditation.tts" | "content.tts" | "sleep.tts";
  };
  signal?: AbortSignal;
  beforeProvider?: (signal: AbortSignal) => Promise<void>;
}

// ─── Voice Presets ───────────────────────────────────────────

interface GoogleVoiceConfig {
  voiceName: string;
  languageCode: string;
  ssmlGender: "FEMALE" | "MALE" | "NEUTRAL";
  speakingRate: number;
  pitch: number;
}

// ─── Chirp 3 HD Voice Presets (Premium) ─────────────────────
// Available voices: Aoede, Kore, Leda, Zephyr (female), Puck, Charon, Fenrir, Orus (male)
// Format: en-US-Chirp3-HD-<VoiceName>

export const CHIRP3_HD_PRESETS: Record<string, GoogleVoiceConfig> = {
  meditation: {
    voiceName: "en-US-Chirp3-HD-Leda",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 1.0,
    pitch: 0.0, // Chirp 3 HD handles pitch naturally
  },
  meditation_male: {
    voiceName: "en-US-Chirp3-HD-Orus",
    languageCode: "en-US",
    ssmlGender: "MALE",
    speakingRate: 1.0,
    pitch: 0.0,
  },
  sleep_story: {
    voiceName: "en-US-Chirp3-HD-Aoede",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.95,
    pitch: 0.0,
  },
  breathing: {
    voiceName: "en-US-Chirp3-HD-Kore",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.9,
    pitch: 0.0,
  },
  grounding: {
    voiceName: "en-US-Chirp3-HD-Zephyr",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 1.0,
    pitch: 0.0,
  },
  affirmation: {
    voiceName: "en-US-Chirp3-HD-Charon",
    languageCode: "en-US",
    ssmlGender: "MALE",
    speakingRate: 1.05,
    pitch: 0.0,
  },
  default: {
    voiceName: "en-US-Chirp3-HD-Leda",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 1.0,
    pitch: 0.0,
  },
};

// ─── Standard Voice Presets (Budget) ────────────────────────

export const GOOGLE_VOICE_PRESETS: Record<string, GoogleVoiceConfig> = {
  meditation: {
    voiceName: "en-US-Standard-C",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.85,
    pitch: -2.0,
  },
  sleep_story: {
    voiceName: "en-US-Standard-C",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.8,
    pitch: -3.0,
  },
  sleep_story_kids: {
    voiceName: "en-US-Standard-E",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.85,
    pitch: 1.0,
  },
  breathing: {
    voiceName: "en-US-Standard-E",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.75,
    pitch: -1.0,
  },
  affirmation: {
    voiceName: "en-US-Standard-D",
    languageCode: "en-US",
    ssmlGender: "MALE",
    speakingRate: 0.95,
    pitch: 0.0,
  },
  grounding: {
    voiceName: "en-US-Standard-F",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.9,
    pitch: -1.0,
  },
  mindfulness: {
    voiceName: "en-US-Standard-C",
    languageCode: "en-US",
    ssmlGender: "FEMALE",
    speakingRate: 0.85,
    pitch: -2.0,
  },
  cbt: {
    voiceName: "en-US-Standard-A",
    languageCode: "en-US",
    ssmlGender: "MALE",
    speakingRate: 1.0,
    pitch: 0.0,
  },
  journaling: {
    voiceName: "en-US-Standard-A",
    languageCode: "en-US",
    ssmlGender: "MALE",
    speakingRate: 1.0,
    pitch: 0.0,
  },
  default: {
    voiceName: "en-US-Standard-A",
    languageCode: "en-US",
    ssmlGender: "MALE",
    speakingRate: 1.0,
    pitch: 0.0,
  },
};

// Default voice preset key used when no voice is specified
export const DEFAULT_VOICE_ID = "meditation";

// ─── Client ──────────────────────────────────────────────────

export class GoogleTTSClient {
  private apiKey: string;

  constructor(config: GoogleTTSConfig) {
    if (!config.apiKey) {
      throw new GoogleTTSError(
        "Google Cloud TTS API key is required",
        "UNAUTHORIZED",
      );
    }
    this.apiKey = config.apiKey;
  }

  async textToSpeech(
    request: TTSRequest,
    options: GoogleTTSOptions,
  ): Promise<TTSResponse> {
    const { text, ssml, voiceId, useChirp3HD = false } = request;

    const inputContent = ssml || text;

    // Validate text is non-empty before computing byte length
    if (!inputContent || inputContent.trim().length === 0) {
      throw new GoogleTTSError(
        "Text content is required",
        "INVALID_REQUEST",
        "Empty text provided",
      );
    }

    // Validate text byte length (Google limit: 5000 bytes UTF-8)
    const textBytes = new TextEncoder().encode(inputContent);
    if (textBytes.length > MAX_TEXT_BYTES) {
      throw new GoogleTTSError(
        "Text too long",
        "TEXT_TOO_LONG",
        `Text byte length ${textBytes.length} exceeds maximum of ${MAX_TEXT_BYTES} bytes`,
      );
    }

    // Resolve voice preset - use Chirp 3 HD if requested
    const presets = useChirp3HD ? CHIRP3_HD_PRESETS : GOOGLE_VOICE_PRESETS;
    const preset = presets[voiceId] || presets.default;

    // Price the resolved voice, never a caller-supplied estimate. Reject other
    // voice families before reserving or contacting the paid endpoint.
    const standard = /^en-US-Standard-[A-J]$/.test(preset?.voiceName);
    const chirp =
      /^en-US-Chirp3-HD-(Aoede|Kore|Leda|Zephyr|Puck|Charon|Fenrir|Orus)$/
        .test(preset?.voiceName);
    if (
      preset?.languageCode !== "en-US" ||
      (useChirp3HD ? !chirp : !standard)
    ) {
      throw new GoogleTTSError(
        "Unsupported voice configuration",
        "INVALID_REQUEST",
      );
    }
    if (
      !options?.budget ||
      !["voice.tts", "meditation.tts", "content.tts", "sleep.tts"].includes(
        options.budget.feature,
      )
    ) throw new MonthlyAIBudgetUnavailableError("invalid_request");

    // Build Google API request body
    const body = {
      input: ssml ? { ssml } : { text },
      voice: {
        languageCode: preset.languageCode,
        name: preset.voiceName,
        ssmlGender: preset.ssmlGender,
      },
      audioConfig: {
        audioEncoding: "MP3" as const,
        speakingRate: preset.speakingRate,
        pitch: preset.pitch,
        sampleRateHertz: 24000,
      },
    };

    // Use v1beta1 for Chirp 3 HD voices
    const apiUrl = useChirp3HD ? GOOGLE_TTS_V1BETA1_URL : GOOGLE_TTS_API_URL;

    // UTF-8 bytes bound billed characters, including all SSML markup. Do not
    // assume any free tier, cached speech, or a cheaper voice than the resolved one.
    const signal = AbortSignal.any([
      ...(options.signal ? [options.signal] : []),
      AbortSignal.timeout(45_000),
    ]);
    await reserveMonthlyAIBudget(options.budget.admin, {
      requestId: crypto.randomUUID(),
      userId: options.budget.userId,
      feature: options.budget.feature,
      reserveMicrodollars: Math.ceil(textBytes.length * (chirp ? 30 : 4)),
    }, signal);
    signal.throwIfAborted();
    await options.beforeProvider?.(signal);
    signal.throwIfAborted();

    const response = await fetch(apiUrl, {
      method: "POST",
      signal,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": this.apiKey,
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      await response.body?.cancel();
      const errorCode = response.status === 403
        ? "UNAUTHORIZED"
        : response.status === 429
        ? "RATE_LIMIT_EXCEEDED"
        : response.status === 400
        ? "INVALID_REQUEST"
        : "API_ERROR";
      throw new GoogleTTSError("Voice synthesis service failed", errorCode);
    }

    // Parse response — Google returns { audioContent: base64string }
    let data;
    try {
      data = await response.json();
    } catch {
      signal.throwIfAborted();
      throw new GoogleTTSError("Invalid voice synthesis response", "API_ERROR");
    }
    const audioBase64 = data?.audioContent;

    if (typeof audioBase64 !== "string" || !audioBase64) {
      throw new GoogleTTSError(
        "No audio content in response",
        "API_ERROR",
        "Response missing audioContent field",
      );
    }

    // Decode base64 to Uint8Array
    const binaryString = atob(audioBase64);
    const audioData = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      audioData[i] = binaryString.charCodeAt(i);
    }

    return {
      audioData,
      contentType: "audio/mpeg",
      characterCount: inputContent.length,
    };
  }
}

// ─── Error Class ─────────────────────────────────────────────

export class GoogleTTSError extends Error {
  code: string;
  /** Server-side only diagnostic info — never serialize to client responses */
  details?: string;

  constructor(message: string, code: string, details?: string) {
    super(message);
    this.name = "GoogleTTSError";
    this.code = code;
    this.details = details;
  }

  /** Omit internal details when serialized to JSON (e.g., in API responses) */
  toJSON() {
    return {
      name: this.name,
      message: this.message,
      code: this.code,
    };
  }
}

// ─── Factory ─────────────────────────────────────────────────

export function createGoogleTTSClient(): GoogleTTSClient {
  const apiKey = Deno.env.get("GOOGLE_CLOUD_TTS_KEY");

  if (!apiKey) {
    throw new Error("GOOGLE_CLOUD_TTS_KEY environment variable is not set");
  }

  return new GoogleTTSClient({ apiKey });
}

// ─── Cost Utilities ──────────────────────────────────────────

/**
 * Estimate cost for Google Cloud TTS Standard voices
 * Pricing: $4.00 per 1,000,000 characters = $0.000004 per character
 */
export function estimateTTSCost(characterCount: number): number {
  const costPerChar = 0.000004; // $4 / 1M chars
  return characterCount * costPerChar;
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
