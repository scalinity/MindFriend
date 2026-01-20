// Community Forums Content Moderation Edge Function
// Uses Grok API for AI-powered safety screening with confidence-based approval
// Per decisions.md 2026-01-19: Community Forums Implementation Assumptions

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const XAI_API_KEY = Deno.env.get("XAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

// Moderation confidence thresholds (per decisions.md)
const CONFIDENCE_THRESHOLDS = {
  AUTO_APPROVE: 0.8, // High confidence safe content
  AUTO_REJECT: 0.3, // High confidence violation
  TIMEOUT_MS: 30000, // 30 seconds before auto-approve
};

interface ModerationRequest {
  contentType: "thread" | "reply";
  contentId: string;
  title?: string; // Only for threads
  content: string;
}

interface ModerationResponse {
  status: "approved" | "pending" | "rejected";
  confidence?: number;
  isCrisis: boolean;
  message?: string;
}

interface GrokModerationResult {
  safe: boolean;
  confidence: number; // 0.0-1.0
  isCrisis: boolean;
  reason?: string;
}

// Crisis keywords for detection (English)
const CRISIS_KEYWORDS = [
  "suicide",
  "suicidal",
  "kill myself",
  "end my life",
  "want to die",
  "better off dead",
  "self harm",
  "self-harm",
  "cut myself",
  "hurt myself",
  "no reason to live",
];

serve(async (req) => {
  try {
    // Initialize Supabase client with service role
    const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

    // Parse request body
    const { contentType, contentId, title, content }: ModerationRequest =
      await req.json();

    // Validate request
    if (!contentType || !contentId || !content) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check for crisis keywords first (fast path)
    const hasCrisisKeywords = detectCrisisKeywords(content);

    // Call Grok API for moderation with timeout
    let moderationResult: GrokModerationResult;
    try {
      moderationResult = await Promise.race([
        moderateWithGrok(title, content),
        timeoutPromise<GrokModerationResult>(CONFIDENCE_THRESHOLDS.TIMEOUT_MS),
      ]);
    } catch (error) {
      console.error("Moderation timeout or error:", error);
      // Auto-approve on timeout, flag for human review
      moderationResult = {
        safe: true,
        confidence: 0.5, // Ambiguous = pending queue
        isCrisis: hasCrisisKeywords,
        reason: "Moderation timeout - flagged for human review",
      };
    }

    // Override crisis detection if keywords found
    if (hasCrisisKeywords) {
      moderationResult.isCrisis = true;
    }

    // Determine status based on confidence thresholds
    let status: "approved" | "pending" | "rejected";
    if (moderationResult.confidence >= CONFIDENCE_THRESHOLDS.AUTO_APPROVE) {
      status = "approved";
    } else if (
      moderationResult.confidence <= CONFIDENCE_THRESHOLDS.AUTO_REJECT
    ) {
      status = "rejected";
    } else {
      status = "pending"; // Queue for human moderator review
    }

    // Special handling for crisis content: always approve (allow peer support)
    if (moderationResult.isCrisis) {
      status = "approved";
    }

    // Update database with moderation result
    const table = contentType === "thread" ? "forum_threads" : "forum_replies";
    const { error: updateError } = await supabase
      .from(table)
      .update({
        status,
        moderation_confidence: moderationResult.confidence,
        is_crisis: moderationResult.isCrisis,
      })
      .eq("id", contentId);

    if (updateError) {
      console.error("Failed to update content status:", updateError);
      throw updateError;
    }

    // Log crisis event if detected
    if (moderationResult.isCrisis) {
      // Get author_id from content
      const { data: contentData, error: fetchError } = await supabase
        .from(table)
        .select("author_id")
        .eq("id", contentId)
        .single();

      if (!fetchError && contentData) {
        await supabase.from("crisis_events").insert({
          user_id: contentData.author_id,
          source: "forum",
          content_preview: content.substring(0, 200),
        });
      }
    }

    // Return moderation response
    const response: ModerationResponse = {
      status,
      confidence: moderationResult.confidence,
      isCrisis: moderationResult.isCrisis,
      message: status === "rejected" ? moderationResult.reason : undefined,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Moderation function error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

/**
 * Call Grok API for content moderation
 * Per decisions.md: "Be lenient with people sharing struggles, strict on violations"
 */
async function moderateWithGrok(
  title: string | undefined,
  content: string,
): Promise<GrokModerationResult> {
  if (!XAI_API_KEY) {
    throw new Error("XAI_API_KEY not configured");
  }

  const fullText = title ? `${title}\n\n${content}` : content;

  const prompt = `You are a content moderator for a mental health support forum. Analyze this forum post for safety and appropriateness.

IMPORTANT: Be lenient with users expressing mental health struggles (anxiety, depression, fear). The forum exists to provide peer support for these experiences. Only flag content that clearly violates guidelines.

Be strict on:
- Harassment, bullying, or attacking other users
- Spam or self-promotion
- Medical misinformation or harmful advice (e.g., "don't take your medication")
- Graphic violence or disturbing content
- Requests for or sharing of personal information

CONTENT TO ANALYZE:
${fullText}

Respond with JSON in this exact format:
{
  "safe": true/false,
  "confidence": 0.0-1.0,
  "isCrisis": true/false (true if user mentions suicide, self-harm, or immediate danger),
  "reason": "brief explanation if not safe"
}`;

  try {
    const response = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${XAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-beta",
        messages: [
          {
            role: "system",
            content:
              "You are a content safety analyzer. Always respond with valid JSON only.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
        temperature: 0.3, // Lower temperature for more consistent moderation
        max_tokens: 200,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Grok API error:", response.status, errorText);

      // Rate limit error (429) - return ambiguous confidence for retry
      if (response.status === 429) {
        return {
          safe: true,
          confidence: 0.5, // Queue for human review
          isCrisis: false,
          reason: "Rate limit exceeded - pending human review",
        };
      }

      throw new Error(`Grok API error: ${response.status} ${errorText}`);
    }

    const data = await response.json();
    const resultText = data.choices?.[0]?.message?.content;

    if (!resultText) {
      throw new Error("No content in Grok API response");
    }

    // Parse JSON response
    const result: GrokModerationResult = JSON.parse(resultText);

    // Validate response structure
    if (
      typeof result.safe !== "boolean" ||
      typeof result.confidence !== "number" ||
      typeof result.isCrisis !== "boolean"
    ) {
      throw new Error("Invalid Grok API response structure");
    }

    // Clamp confidence to 0-1 range
    result.confidence = Math.max(0, Math.min(1, result.confidence));

    return result;
  } catch (error) {
    console.error("Grok API call failed:", error);
    // On error, return ambiguous confidence (will trigger pending queue)
    return {
      safe: true,
      confidence: 0.5,
      isCrisis: false,
      reason: "Moderation API error - pending human review",
    };
  }
}

/**
 * Fast keyword-based crisis detection
 * Catches immediate danger situations even if Grok API misses them
 */
function detectCrisisKeywords(text: string): boolean {
  const lowerText = text.toLowerCase();
  return CRISIS_KEYWORDS.some((keyword) => lowerText.includes(keyword));
}

/**
 * Promise that rejects after specified milliseconds
 */
function timeoutPromise<T>(ms: number): Promise<T> {
  return new Promise((_, reject) => {
    setTimeout(() => reject(new Error("Timeout")), ms);
  });
}
