// Community Forums Content Moderation Edge Function
// Uses Grok API for AI-powered safety screening with confidence-based approval
// Per decisions.md 2026-01-19: Community Forums Implementation Assumptions

import { sanitizeForPrompt } from "../_shared/sanitize.ts";
import { authenticateRequest, isAuthError } from "../_shared/auth.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { budgetedXAIText, type XAITextBudgetContext } from "../_shared/budgeted-xai-text.ts";

// Moderation confidence thresholds (per decisions.md)
const CONFIDENCE_THRESHOLDS = {
  DECISIVE: 0.8, // Confidence in the safe/unsafe verdict
  TIMEOUT_MS: 30000, // Keep content pending on timeout
};

interface ModerationRequest {
  contentType: "thread" | "reply";
  contentId: string;
}

interface StoredForumContent {
  id: string;
  author_id: string;
  title?: string;
  content: string;
  updated_at: string;
  status: string;
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

export async function handleModerateForumContent(req: Request): Promise<Response> {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Authenticate request
    const authResult = await authenticateRequest(req);
    if (isAuthError(authResult)) {
      return authResult.response;
    }

    const supabase = authResult.supabaseAdmin;
    const { contentType, contentId }: ModerationRequest = await req.json();
    const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

    if ((contentType !== "thread" && contentType !== "reply") ||
        typeof contentId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(contentId)) {
      return new Response(JSON.stringify({ error: "Invalid content type or ID" }), {
        status: 400, headers: jsonHeaders,
      });
    }

    // Never trust caller-supplied text or let one author screen another's row.
    const table = contentType === "thread" ? "forum_threads" : "forum_replies";
    const { data: stored, error: readError } = await supabase
      .from(table)
      .select(contentType === "thread"
        ? "id,author_id,title,content,updated_at,status"
        : "id,author_id,content,updated_at,status")
      .eq("id", contentId)
      .eq("author_id", authResult.user.id)
      .maybeSingle()
      .overrideTypes<StoredForumContent | null, { merge: false }>();
    if (readError) throw readError;
    if (!stored || stored.author_id !== authResult.user.id) {
      return new Response(JSON.stringify({ error: "Content not found" }), {
        status: 404, headers: jsonHeaders,
      });
    }
    if (stored.status !== "pending") {
      return new Response(JSON.stringify({ error: "Content is no longer awaiting moderation" }), {
        status: 409, headers: jsonHeaders,
      });
    }
    const content = stored.content;
    const title = contentType === "thread" ? stored.title : undefined;
    if (typeof content !== "string" || !content || [...content].length > 10000 ||
        (contentType === "thread" &&
          (typeof title !== "string" || !title || [...title].length > 300)) ||
        typeof stored.updated_at !== "string") {
      return new Response(JSON.stringify({ error: "Stored content cannot be screened in full" }), {
        status: 422, headers: jsonHeaders,
      });
    }

    // Check for crisis keywords first (fast path)
    const hasCrisisKeywords = detectCrisisKeywords(`${title ?? ""}\n${content}`);

    // Call Grok API for moderation with timeout
    let moderationResult: GrokModerationResult;
    try {
      moderationResult = await moderateWithGrok(title, content,
        { admin: supabase, userId: authResult.user.id, feature: "forum.moderation" },
        AbortSignal.any([req.signal, AbortSignal.timeout(CONFIDENCE_THRESHOLDS.TIMEOUT_MS)]));
    } catch {
      console.error("Moderation timeout or error");
      // Keep uncertain content pending for human review
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

    // Confidence is confidence in the verdict, not a safety score.
    const status = moderationResult.confidence >= CONFIDENCE_THRESHOLDS.DECISIVE
      ? (moderationResult.safe ? "approved" : "rejected")
      : "pending";

    // The database owns updated_at and refreshes it on every client update.
    // A changed revision must be screened again, never approved by an old result.
    const { data: updated, error: updateError } = await supabase
      .from(table)
      .update({
        status,
        moderation_confidence: moderationResult.confidence,
        is_crisis: moderationResult.isCrisis,
      })
      .eq("id", contentId)
      .eq("author_id", authResult.user.id)
      .eq("updated_at", stored.updated_at)
      .eq("status", "pending")
      .select("id")
      .maybeSingle();

    if (updateError) throw updateError;
    if (!updated) {
      return new Response(JSON.stringify({ error: "Content changed during moderation; please retry" }), {
        status: 409, headers: jsonHeaders,
      });
    }

    // Preserve crisis support independently of publication. Store only metadata,
    // using the actual crisis_events schema, never an excerpt of private text.
    if (moderationResult.isCrisis) {
      const { error: crisisError } = await supabase.from("crisis_events").insert({
        user_id: stored.author_id,
        notes: `Forum ${contentType} ${contentId}: crisis language detected`,
      });
      if (crisisError) console.error("Failed to record forum crisis event");
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
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Moderation function error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) Deno.serve(handleModerateForumContent);

/**
 * Call Grok API for content moderation
 * Per decisions.md: "Be lenient with people sharing struggles, strict on violations"
 */
async function moderateWithGrok(
  title: string | undefined,
  content: string,
  budget: XAITextBudgetContext,
  signal?: AbortSignal,
): Promise<GrokModerationResult> {
  const apiKey = Deno.env.get("XAI_API_KEY");
  if (!apiKey) {
    throw new Error("XAI_API_KEY not configured");
  }

  const sanitizedTitle = title ? sanitizeForPrompt(title, title.length) : undefined;
  const sanitizedContent = sanitizeForPrompt(content, content.length);
  const fullText = sanitizedTitle ? `${sanitizedTitle}\n\n${sanitizedContent}` : sanitizedContent;

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
    const response = await budgetedXAIText({
        ...budget,
        apiKey,
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
        maxTokens: 200,
        signal,
    });

    if (!response.ok) {
      console.error("Grok API error:", response.status);

      // Rate limit error (429) - return ambiguous confidence for retry
      if (response.status === 429) {
        return {
          safe: true,
          confidence: 0.5, // Queue for human review
          isCrisis: false,
          reason: "Rate limit exceeded - pending human review",
        };
      }

      throw new Error(`Grok API error: ${response.status}`);
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
      !Number.isFinite(result.confidence) || result.confidence < 0 || result.confidence > 1 ||
      typeof result.isCrisis !== "boolean"
    ) {
      throw new Error("Invalid Grok API response structure");
    }

    return { ...result, reason: typeof result.reason === "string" ? result.reason : undefined };
  } catch {
    console.error("Grok API call failed");
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
