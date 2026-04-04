// MindFriend Journal Analysis Edge Function
// Analyzes journal entries using Grok AI to detect cognitive distortions
// and provide supportive insights with gentle, non-clinical language

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Type alias for untyped Supabase client
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";
import { sanitizeForPrompt } from "../_shared/sanitize.ts";

// Constants
const MAX_CONTENT_LENGTH = 50000; // ~12,500 tokens
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const XAI_API_URL = "https://api.x.ai/v1/chat/completions";
const FREE_DAILY_QUOTA = 3;

// Banned clinical language patterns - must be filtered from AI responses
const BANNED_PATTERNS = [
  /\b(diagnos(is|e|ed|ing)|disorder|symptom|treatment|therapy required)\b/gi,
  /\b(you (should|must|need to|have to))\b/gi,
  /\b(that's (wrong|bad|irrational|illogical))\b/gi,
  /\b(patient|clinical|pathological|abnormal)\b/gi,
  /\b(mentally ill|crazy|insane)\b/gi,
];

// Required supportive patterns - at least one should be present
const SUPPORTIVE_PATTERNS = [
  /\b(it's (natural|understandable|common|okay))\b/gi,
  /\b(many people (feel|experience|think))\b/gi,
  /\b(you might (consider|try|explore))\b/gi,
  /\b(one perspective|another way to look at)\b/gi,
];

// Cognitive distortion types with supportive explanations
const DISTORTION_INFO: Record<
  string,
  { displayName: string; supportiveDescription: string }
> = {
  all_or_nothing: {
    displayName: "All-or-Nothing Thinking",
    supportiveDescription:
      "This is when we see things in black and white, without room for middle ground. It's a common thinking pattern, especially when we're stressed.",
  },
  catastrophizing: {
    displayName: "Catastrophizing",
    supportiveDescription:
      "This is when our mind jumps to the worst possible outcome. Our brains are actually wired to do this as a protection mechanism.",
  },
  emotional_reasoning: {
    displayName: "Emotional Reasoning",
    supportiveDescription:
      "This is when we believe something must be true because we feel it strongly. Our emotions are valid, but they don't always reflect reality.",
  },
  fortune_telling: {
    displayName: "Fortune Telling",
    supportiveDescription:
      "This is when we predict negative outcomes as if they're certain. While planning ahead is helpful, this pattern can create unnecessary worry.",
  },
  labeling: {
    displayName: "Labeling",
    supportiveDescription:
      "This is when we define ourselves or others with a single word based on one event. We're all much more complex than any single label.",
  },
  magnification: {
    displayName: "Magnification",
    supportiveDescription:
      "This is when we make problems seem bigger than they are, or minimize our strengths. Finding balance helps us see things more clearly.",
  },
  mind_reading: {
    displayName: "Mind Reading",
    supportiveDescription:
      "This is when we assume we know what others are thinking, usually negatively. In reality, we can't know others' thoughts without asking.",
  },
  mental_filter: {
    displayName: "Mental Filter",
    supportiveDescription:
      "This is when we focus only on the negative and filter out the positive. It's like wearing tinted glasses that only show one color.",
  },
  overgeneralization: {
    displayName: "Overgeneralization",
    supportiveDescription:
      "This is when one negative experience becomes a never-ending pattern in our minds. Words like 'always' and 'never' can be clues.",
  },
  should_statements: {
    displayName: "Should Statements",
    supportiveDescription:
      "This is when we pressure ourselves with rigid rules about how things 'should' be. These can create guilt and frustration.",
  },
};

// System prompt for AI analysis - emphasizes supportive, non-clinical language
const ANALYSIS_SYSTEM_PROMPT = `You are MindFriend's supportive journal analyst. Your role is to help users gain insights from their journal entries with warmth and understanding.

## Your Purpose
Analyze the user's journal entry to:
1. Identify emotional themes
2. Notice any thinking patterns that might be causing extra stress (cognitive distortions)
3. Offer gentle reframes and alternative perspectives
4. Provide a supportive summary

## Critical Guidelines - FOLLOW EXACTLY
1. NEVER use clinical language: no "diagnosis", "disorder", "symptom", "treatment", "therapy"
2. NEVER say "you should", "you must", "you need to", "you have to"
3. NEVER label anything as "wrong", "bad", "irrational", or "illogical"
4. ALWAYS use phrases like "It's natural to feel...", "Many people experience...", "One perspective might be..."
5. Focus on GROWTH and SELF-COMPASSION, not fixing or correcting
6. Acknowledge the VALIDITY of their feelings before offering alternative views
7. Be WARM, CURIOUS, and ENCOURAGING

## Cognitive Distortions to Look For
When you notice these patterns, explain them gently:
- All-or-Nothing Thinking: Black and white thinking without middle ground
- Catastrophizing: Jumping to worst-case scenarios
- Emotional Reasoning: Believing feelings are facts
- Fortune Telling: Predicting negative outcomes as certain
- Labeling: Defining self/others by single events
- Magnification: Making problems bigger or strengths smaller
- Mind Reading: Assuming we know others' thoughts
- Mental Filter: Focusing only on negatives
- Overgeneralization: One event becomes a forever pattern
- Should Statements: Rigid rules creating guilt

## Response Format
Return a JSON object with this EXACT structure:
{
  "emotionalThemes": ["theme1", "theme2", ...],
  "suggestedReframes": [
    {
      "original": "exact quote from entry",
      "reframe": "alternative perspective",
      "rationale": "why this reframe might help"
    }
  ],
  "patternsIdentified": [
    {
      "patternType": "description of pattern",
      "description": "what you noticed"
    }
  ],
  "cognitiveDistortions": [
    {
      "type": "distortion_type_key",
      "quote": "exact text from entry",
      "explanation": "warm, supportive explanation",
      "alternativePerspective": "gentle alternative view"
    }
  ],
  "supportiveSummary": "2-3 sentence warm summary acknowledging their feelings and highlighting growth opportunities"
}

Remember: Your goal is to help the user feel UNDERSTOOD and SUPPORTED, not analyzed or judged.`;

interface AnalyzeRequest {
  entryId: string;
}

interface SuggestedReframe {
  original: string;
  reframe: string;
  rationale: string;
}

interface PatternInfo {
  patternType: string;
  description: string;
}

interface CognitiveDistortion {
  type: string;
  displayName: string;
  quote: string;
  explanation: string;
  alternativePerspective: string;
}

interface AnalysisResult {
  emotionalThemes: string[];
  suggestedReframes: SuggestedReframe[];
  patternsIdentified: PatternInfo[];
  cognitiveDistortions: CognitiveDistortion[];
  supportiveSummary: string;
}

/**
 * Sanitize AI output to remove any clinical language that slipped through
 */
function sanitizeOutput(text: string): string {
  let sanitized = text;

  // Replace banned patterns with supportive alternatives
  sanitized = sanitized.replace(/\byou should\b/gi, "you might consider");
  sanitized = sanitized.replace(/\byou must\b/gi, "it could help to");
  sanitized = sanitized.replace(/\byou need to\b/gi, "one option is to");
  sanitized = sanitized.replace(/\byou have to\b/gi, "you might try");
  sanitized = sanitized.replace(
    /\bthat's wrong\b/gi,
    "that's one way to see it",
  );
  sanitized = sanitized.replace(/\bthat's bad\b/gi, "that can be challenging");
  sanitized = sanitized.replace(
    /\bthat's irrational\b/gi,
    "that thinking pattern is common",
  );
  sanitized = sanitized.replace(/\bdiagnosis\b/gi, "pattern");
  sanitized = sanitized.replace(/\bdisorder\b/gi, "experience");
  sanitized = sanitized.replace(/\bsymptom\b/gi, "sign");
  sanitized = sanitized.replace(/\btreatment\b/gi, "support");

  return sanitized;
}

/**
 * Parse and validate AI response
 */
function parseAnalysisResponse(content: string): AnalysisResult | null {
  try {
    // Extract JSON from response (may be wrapped in markdown code blocks)
    let jsonStr = content;
    const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1];
    }

    const parsed = JSON.parse(jsonStr);

    // Validate required fields
    if (!parsed.emotionalThemes || !Array.isArray(parsed.emotionalThemes)) {
      parsed.emotionalThemes = [];
    }
    if (!parsed.suggestedReframes || !Array.isArray(parsed.suggestedReframes)) {
      parsed.suggestedReframes = [];
    }
    if (
      !parsed.patternsIdentified ||
      !Array.isArray(parsed.patternsIdentified)
    ) {
      parsed.patternsIdentified = [];
    }
    if (
      !parsed.cognitiveDistortions ||
      !Array.isArray(parsed.cognitiveDistortions)
    ) {
      parsed.cognitiveDistortions = [];
    }
    if (
      !parsed.supportiveSummary ||
      typeof parsed.supportiveSummary !== "string"
    ) {
      parsed.supportiveSummary =
        "Thank you for sharing your thoughts. Journaling is a wonderful practice for self-reflection.";
    }

    // Sanitize all text fields
    parsed.supportiveSummary = sanitizeOutput(parsed.supportiveSummary);

    // Enhance cognitive distortions with display info
    parsed.cognitiveDistortions = parsed.cognitiveDistortions.map(
      (d: CognitiveDistortion) => {
        const info = DISTORTION_INFO[d.type] || {
          displayName: d.type
            .replace(/_/g, " ")
            .replace(/\b\w/g, (c) => c.toUpperCase()),
          supportiveDescription: "This is a common thinking pattern.",
        };
        return {
          ...d,
          displayName: info.displayName,
          explanation: sanitizeOutput(
            d.explanation || info.supportiveDescription,
          ),
          alternativePerspective: sanitizeOutput(
            d.alternativePerspective || "",
          ),
        };
      },
    );

    // Sanitize reframes
    parsed.suggestedReframes = parsed.suggestedReframes.map(
      (r: SuggestedReframe) => ({
        ...r,
        reframe: sanitizeOutput(r.reframe || ""),
        rationale: sanitizeOutput(r.rationale || ""),
      }),
    );

    return parsed;
  } catch (error) {
    console.error("Failed to parse AI response:", error);
    return null;
  }
}

serve(async (req) => {
  // Get origin for CORS handling
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    // Validate auth header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    // Create user-scoped client
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    );

    // Create admin client for elevated operations
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate user
    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      console.error("Auth validation failed:", authError?.message);
      return new Response(
        JSON.stringify({
          error: "Invalid token",
          message: "Please sign out and sign back in.",
        }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting (10 requests per minute)
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "analyze-journal",
    );

    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          message: "Please wait a moment before analyzing another entry.",
          retryAfter: rateLimitResult.retryAfter,
        }),
        {
          status: 429,
          headers: {
            ...baseCorsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    const responseHeaders = {
      ...baseCorsHeaders,
      "Content-Type": "application/json",
      ...getRateLimitHeaders(rateLimitResult),
    };

    // Parse request
    let requestBody: AnalyzeRequest;
    try {
      requestBody = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const { entryId } = requestBody;

    // Validate entryId
    if (!entryId || typeof entryId !== "string") {
      return new Response(JSON.stringify({ error: "Missing entryId" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    if (!UUID_REGEX.test(entryId)) {
      return new Response(
        JSON.stringify({ error: "Invalid entry identifier" }),
        {
          status: 400,
          headers: responseHeaders,
        },
      );
    }

    // Fetch the journal entry (ownership verified by RLS)
    const { data: entry, error: entryError } = await supabaseAdmin
      .from("journal_entries")
      .select("id, user_id, content, title, is_analyzed")
      .eq("id", entryId)
      .single();

    if (entryError || !entry) {
      return new Response(
        JSON.stringify({ error: "Entry not found", code: "ENTRY_NOT_FOUND" }),
        {
          status: 404,
          headers: responseHeaders,
        },
      );
    }

    // Verify ownership
    if (entry.user_id !== user.id) {
      console.error("Unauthorized journal access attempt", {
        entryId,
        userId: user.id,
      });
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: responseHeaders,
      });
    }

    // Check if already analyzed
    if (entry.is_analyzed) {
      // Return existing analysis
      const { data: existingAnalysis } = await supabaseAdmin
        .from("journal_analyses")
        .select("*")
        .eq("entry_id", entryId)
        .single();

      if (existingAnalysis) {
        return new Response(
          JSON.stringify({
            analysisId: existingAnalysis.id,
            emotionalThemes: existingAnalysis.emotional_themes,
            suggestedReframes: existingAnalysis.suggested_reframes,
            patternsIdentified: existingAnalysis.patterns_identified,
            cognitiveDistortions: existingAnalysis.cognitive_distortions,
            supportiveSummary: existingAnalysis.supportive_summary,
            cached: true,
          }),
          { headers: responseHeaders },
        );
      }
    }

    // Check premium status
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("subscription_tier")
      .eq("id", user.id)
      .single();

    const isPremium = profile?.subscription_tier === "premium";

    // Check daily quota for free users
    if (!isPremium) {
      const today = new Date().toISOString().split("T")[0];
      const { data: usage } = await supabaseAdmin
        .from("journal_daily_usage")
        .select("analyses_used")
        .eq("user_id", user.id)
        .eq("date", today)
        .single();

      const analysesUsed = usage?.analyses_used || 0;

      if (analysesUsed >= FREE_DAILY_QUOTA) {
        return new Response(
          JSON.stringify({
            error: "AI_QUOTA_EXCEEDED",
            code: "QUOTA_EXCEEDED",
            message:
              "You've reached your daily AI analysis limit. Upgrade to Premium for unlimited analyses!",
            quotaUsed: analysesUsed,
            quotaLimit: FREE_DAILY_QUOTA,
          }),
          { status: 429, headers: responseHeaders },
        );
      }
    }

    // Validate content length
    if (!entry.content || entry.content.length === 0) {
      return new Response(
        JSON.stringify({ error: "Entry has no content to analyze" }),
        { status: 400, headers: responseHeaders },
      );
    }

    if (entry.content.length > MAX_CONTENT_LENGTH) {
      return new Response(
        JSON.stringify({
          error: "Entry too long for analysis",
          maxLength: MAX_CONTENT_LENGTH,
        }),
        { status: 400, headers: responseHeaders },
      );
    }

    // Call Grok AI for analysis
    const xaiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiKey) {
      console.error("XAI_API_KEY not configured");
      return new Response(
        JSON.stringify({
          error: "Service temporarily unavailable",
          code: "AI_UNAVAILABLE",
        }),
        { status: 503, headers: responseHeaders },
      );
    }

    // Sanitize journal content before sending to LLM
    const sanitizedContent = sanitizeForPrompt(entry.content, 50000);
    const sanitizedTitle = entry.title ? sanitizeForPrompt(entry.title, 200) : null;

    const userMessage = sanitizedTitle
      ? `Title: ${sanitizedTitle}\n\n${sanitizedContent}`
      : sanitizedContent;

    const aiResponse = await fetch(XAI_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${xaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-4-1-fast-reasoning",
        messages: [
          { role: "system", content: ANALYSIS_SYSTEM_PROMPT },
          { role: "user", content: userMessage },
        ],
        max_tokens: 2000,
        temperature: 0.7,
      }),
    });

    if (!aiResponse.ok) {
      console.error("xAI API error:", aiResponse.status);
      return new Response(
        JSON.stringify({
          error: "AI service temporarily unavailable",
          code: "AI_UNAVAILABLE",
        }),
        { status: 502, headers: responseHeaders },
      );
    }

    const aiData = await aiResponse.json();
    const aiContent = aiData.choices?.[0]?.message?.content;

    if (!aiContent) {
      console.error("Empty AI response");
      return new Response(
        JSON.stringify({
          error: "AI service returned empty response",
          code: "AI_UNAVAILABLE",
        }),
        { status: 502, headers: responseHeaders },
      );
    }

    // Parse and validate AI response
    const analysis = parseAnalysisResponse(aiContent);

    if (!analysis) {
      // Fallback to a basic supportive response
      const fallbackAnalysis: AnalysisResult = {
        emotionalThemes: ["reflection", "self-expression"],
        suggestedReframes: [],
        patternsIdentified: [],
        cognitiveDistortions: [],
        supportiveSummary:
          "Thank you for taking the time to journal today. Writing about our experiences is a powerful way to process our thoughts and feelings. Keep up this wonderful practice of self-reflection.",
      };

      // Store fallback analysis
      const { data: savedAnalysis, error: saveError } = await supabaseAdmin
        .from("journal_analyses")
        .insert({
          entry_id: entryId,
          user_id: user.id,
          emotional_themes: fallbackAnalysis.emotionalThemes,
          suggested_reframes: fallbackAnalysis.suggestedReframes,
          patterns_identified: fallbackAnalysis.patternsIdentified,
          cognitive_distortions: fallbackAnalysis.cognitiveDistortions,
          supportive_summary: fallbackAnalysis.supportiveSummary,
          ai_model: "grok-4-1-fast-reasoning",
        })
        .select()
        .single();

      if (saveError) {
        console.error("Failed to save analysis:", saveError.code);
      }

      // Mark entry as analyzed
      await supabaseAdmin
        .from("journal_entries")
        .update({ is_analyzed: true })
        .eq("id", entryId);

      return new Response(
        JSON.stringify({
          analysisId: savedAnalysis?.id,
          ...fallbackAnalysis,
          cached: false,
        }),
        { headers: responseHeaders },
      );
    }

    // Store analysis
    const { data: savedAnalysis, error: saveError } = await supabaseAdmin
      .from("journal_analyses")
      .insert({
        entry_id: entryId,
        user_id: user.id,
        emotional_themes: analysis.emotionalThemes,
        suggested_reframes: analysis.suggestedReframes,
        patterns_identified: analysis.patternsIdentified,
        cognitive_distortions: analysis.cognitiveDistortions,
        supportive_summary: analysis.supportiveSummary,
        ai_model: "grok-4-1-fast-reasoning",
      })
      .select()
      .single();

    if (saveError) {
      console.error("Failed to save analysis:", saveError.code);
      // Continue anyway - return the analysis even if storage failed
    }

    // Mark entry as analyzed
    await supabaseAdmin
      .from("journal_entries")
      .update({ is_analyzed: true })
      .eq("id", entryId);

    // Update daily usage for free users
    if (!isPremium) {
      const today = new Date().toISOString().split("T")[0];
      await supabaseAdmin.from("journal_daily_usage").upsert(
        {
          user_id: user.id,
          date: today,
          analyses_used: 1,
        },
        {
          onConflict: "user_id,date",
        },
      );

      // Increment analyses_used if row existed
      await supabaseAdmin
        .rpc("increment_journal_analysis_usage", {
          p_user_id: user.id,
          p_date: today,
        })
        .catch(() => {
          // If RPC doesn't exist, manually update
          supabaseAdmin
            .from("journal_daily_usage")
            .update({ analyses_used: 1 })
            .eq("user_id", user.id)
            .eq("date", today);
        });
    }

    // Get updated quota info for response
    let quotaUsed = 0;
    let quotaLimit = FREE_DAILY_QUOTA;
    if (!isPremium) {
      const today = new Date().toISOString().split("T")[0];
      const { data: updatedUsage } = await supabaseAdmin
        .from("journal_daily_usage")
        .select("analyses_used")
        .eq("user_id", user.id)
        .eq("date", today)
        .single();
      quotaUsed = updatedUsage?.analyses_used || 1;
    } else {
      quotaLimit = -1; // Unlimited for premium
    }

    return new Response(
      JSON.stringify({
        analysisId: savedAnalysis?.id,
        emotionalThemes: analysis.emotionalThemes,
        suggestedReframes: analysis.suggestedReframes,
        patternsIdentified: analysis.patternsIdentified,
        cognitiveDistortions: analysis.cognitiveDistortions,
        supportiveSummary: analysis.supportiveSummary,
        cached: false,
        quotaUsed,
        quotaLimit,
      }),
      { headers: responseHeaders },
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  }
});
