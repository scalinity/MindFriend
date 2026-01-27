// =====================================================
// Cognitive Distortion Detection Edge Function
// =====================================================
// Description: Detects cognitive distortions in user transcript text
// Security: Uses encryption for sensitive data, RLS for access control
// Author: MindFriend Dev Team
// Date: 2026-01-23
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type {
  DetectDistortionRequest,
  DetectDistortionResponse,
  DetectedDistortion,
  DistortionType,
  ErrorResponse,
} from "./types.ts";

// =====================================================
// Environment Variable Validation (P0 Security Fix)
// =====================================================

/**
 * Validates encryption key format and length
 * SECURITY: Ensures key meets minimum requirements before use
 */
function validateEncryptionKey(key: string | undefined): string {
  if (!key) {
    throw new Error(
      "DISTORTION_ENCRYPTION_KEY environment variable not set - deployment configuration error",
    );
  }

  // AES-256 requires minimum 32 bytes (256 bits)
  if (key.length < 32) {
    throw new Error(
      `Encryption key too short (${key.length} chars) - minimum 32 characters required for AES-256`,
    );
  }

  return key;
}

// Environment variables with validation
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DISTORTION_ENCRYPTION_KEY = validateEncryptionKey(
  Deno.env.get("DISTORTION_ENCRYPTION_KEY"),
); // P0 FIX: Validate at startup
const XAI_API_KEY = Deno.env.get("XAI_API_KEY"); // Optional: for LLM enhancement

// Confidence threshold for displaying prompts
const CONFIDENCE_THRESHOLD = 0.7;

// Pattern matching keywords for each distortion type
const DISTORTION_PATTERNS: Record<DistortionType, string[]> = {
  all_or_nothing: [
    "always",
    "never",
    "every time",
    "completely",
    "totally",
    "perfect",
    "failure",
    "either.*or",
    "all.*nothing",
  ],
  overgeneralization: [
    "always happens",
    "never works",
    "everyone",
    "nobody",
    "typical",
    "same.*always",
  ],
  mental_filter: [
    "only.*negative",
    "just.*bad",
    "nothing good",
    "everything.*wrong",
  ],
  disqualifying_positive: [
    "doesn't count",
    "doesn't matter",
    "just luck",
    "anyone could",
    "not a big deal",
  ],
  jumping_to_conclusions: [
    "probably thinks",
    "must think",
    "going to.*fail",
    "will never",
    "they.*hate",
  ],
  magnification_minimization: [
    "catastrophic",
    "disaster",
    "terrible",
    "awful",
    "not that good",
    "just.*small",
  ],
  emotional_reasoning: [
    "feel.*therefore",
    "feel like.*so I am",
    "feeling.*means",
  ],
  should_statements: ["should", "must", "have to", "ought to", "need to"],
  labeling: ["I am.*loser", "I am.*failure", "such a", "total.*idiot"],
  personalization: ["my fault", "because of me", "I caused", "I'm responsible"],
};

serve(async (req) => {
  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse("UNAUTHORIZED", "Missing authorization header", 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return errorResponse("UNAUTHORIZED", "Invalid or expired token", 401);
    }

    // Parse request body
    const body: DetectDistortionRequest = await req.json();
    const { text, sessionId } = body;

    if (!text || !sessionId) {
      return errorResponse(
        "INVALID_REQUEST",
        "Missing required fields: text, sessionId",
        400,
      );
    }

    // Run pattern matching detection
    const patternResult = detectPatterns(text);

    let detectedDistortion: DetectedDistortion | undefined;
    let detectionMethod: "llm" | "pattern" = "pattern";

    if (patternResult && patternResult.confidence >= CONFIDENCE_THRESHOLD) {
      // High confidence pattern match
      detectedDistortion = patternResult;
      detectionMethod = "pattern";
    } else if (
      patternResult &&
      patternResult.confidence >= 0.5 &&
      patternResult.confidence < CONFIDENCE_THRESHOLD &&
      XAI_API_KEY
    ) {
      // Medium confidence: enhance with LLM
      const llmResult = await enhanceWithLLM(text, XAI_API_KEY);
      if (llmResult && llmResult.confidence >= CONFIDENCE_THRESHOLD) {
        detectedDistortion = llmResult;
        detectionMethod = "llm";
      }
    }

    // Store detection event if distortion detected
    if (detectedDistortion) {
      await storeDistortionEvent(supabase, {
        sessionId,
        distortionType: detectedDistortion.type,
        transcriptText: text,
        confidence: detectedDistortion.confidence,
        detectionMethod,
      });
    }

    // Return response
    const response: DetectDistortionResponse = {
      detected: !!detectedDistortion,
      distortion: detectedDistortion,
      detectionMethod,
    };

    return new Response(JSON.stringify(response), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    // P0 FIX: Sanitize error logging to prevent sensitive data leakage
    // NEVER log full error objects as they may contain transcript_text
    console.error({
      context: "Error in detect-distortion function",
      errorType: error instanceof Error ? error.name : "Unknown",
      errorMessage: error instanceof Error ? error.message : "Unknown error",
      timestamp: new Date().toISOString(),
      // DO NOT include error.stack, full error object, or request body
    });

    return errorResponse("LLM_FAILURE", "Internal server error", 500);
  }
});

// =====================================================
// Helper Functions
// =====================================================

/**
 * Detects cognitive distortions using pattern matching
 */
function detectPatterns(text: string): DetectedDistortion | null {
  const lowerText = text.toLowerCase();
  const results: Array<{ type: DistortionType; score: number }> = [];

  // Check each distortion type
  for (const [type, patterns] of Object.entries(DISTORTION_PATTERNS)) {
    let matchCount = 0;
    for (const pattern of patterns) {
      const regex = new RegExp(pattern, "i");
      if (regex.test(lowerText)) {
        matchCount++;
      }
    }

    if (matchCount > 0) {
      // Calculate confidence based on match count and pattern specificity
      const confidence = Math.min(0.95, 0.5 + matchCount * 0.15); // Cap at 0.95
      results.push({ type: type as DistortionType, score: confidence });
    }
  }

  // Return highest confidence match
  if (results.length === 0) return null;

  results.sort((a, b) => b.score - a.score);
  const topMatch = results[0];

  return {
    type: topMatch.type,
    confidence: topMatch.score,
  };
}

/**
 * Enhances detection using LLM (Grok API)
 * Only called when pattern confidence is 0.5-0.75
 */
async function enhanceWithLLM(
  text: string,
  apiKey: string,
): Promise<DetectedDistortion | null> {
  try {
    const response = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "grok-beta",
        messages: [
          {
            role: "system",
            content: `You are a CBT expert analyzing text for cognitive distortions.

Identify ONE primary cognitive distortion from these 10 types:
1. all_or_nothing - Thinking in extremes (always/never, perfect/failure)
2. overgeneralization - One event means it always happens
3. mental_filter - Focusing only on negatives
4. disqualifying_positive - Dismissing good things ("doesn't count")
5. jumping_to_conclusions - Assuming what others think or predicting negatively
6. magnification_minimization - Exaggerating negatives or minimizing positives
7. emotional_reasoning - "I feel X, so it must be true"
8. should_statements - Rigid rules with "should", "must", "have to"
9. labeling - Attaching fixed negative labels
10. personalization - Blaming yourself for things outside your control

Respond ONLY with JSON in this format:
{"type": "distortion_type", "confidence": 0.0-1.0, "reasoning": "brief explanation"}

If no distortion detected, respond: {"type": null, "confidence": 0, "reasoning": "no distortion"}`,
          },
          {
            role: "user",
            content: `Analyze this text for cognitive distortions:\n\n"${text}"`,
          },
        ],
        temperature: 0.3,
        max_tokens: 150,
      }),
    });

    if (!response.ok) {
      // P0 FIX: Sanitize error logging
      console.error({
        context: "LLM API error",
        status: response.status,
        statusText: response.statusText,
        // DO NOT log request body (contains sensitive transcript)
      });
      return null;
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) return null;

    // Parse LLM response
    const parsed = JSON.parse(content);
    if (!parsed.type || parsed.confidence < 0.5) return null;

    return {
      type: parsed.type as DistortionType,
      confidence: parsed.confidence,
      reasoning: parsed.reasoning,
    };
  } catch (error) {
    // P0 FIX: Sanitize error logging
    console.error({
      context: "LLM enhancement error",
      errorType: error instanceof Error ? error.name : "Unknown",
      errorMessage: error instanceof Error ? error.message : "Unknown error",
      // DO NOT log full error object or transcript text
    });
    return null;
  }
}

/**
 * Stores distortion event in database with encryption
 * SECURITY: user_id derived from auth.uid() server-side
 */
async function storeDistortionEvent(
  supabase: any, // Type: SupabaseClient (using any for compatibility)
  event: {
    sessionId: string;
    distortionType: DistortionType;
    transcriptText: string;
    confidence: number;
    detectionMethod: "llm" | "pattern";
  },
) {
  // SECURITY FIX: Removed p_user_id parameter
  // Function uses auth.uid() to prevent privilege escalation
  const { error } = await supabase.rpc("encrypt_and_store_distortion", {
    p_session_id: event.sessionId,
    p_distortion_type: event.distortionType,
    p_transcript_text: event.transcriptText,
    p_confidence: event.confidence,
    p_detection_method: event.detectionMethod,
    p_encryption_key: DISTORTION_ENCRYPTION_KEY,
  } as any); // Type assertion for Supabase RPC

  if (error) {
    // P0 FIX: Sanitize error logging to prevent sensitive data leakage
    console.error({
      context: "Failed to store distortion event",
      errorCode: error.code,
      errorMessage: error.message,
      // DO NOT log error.details, error.hint, or full error object
      // as they may contain sensitive transcript_text
    });
    throw new Error("Failed to store distortion event");
  }
}

/**
 * Returns error response
 */
function errorResponse(
  code: ErrorResponse["code"],
  message: string,
  status: number,
  details?: unknown,
): Response {
  const error: ErrorResponse = { code, message, details };
  return new Response(JSON.stringify(error), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
