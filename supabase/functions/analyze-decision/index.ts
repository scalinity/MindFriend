/**
 * Analyze Decision Edge Function
 * AI-powered decision analysis using user's top 5 values and xAI Grok API
 * Provides aligned/conflicting values + actionable suggestions
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  callGrokAPI,
  sanitizeForPrompt,
  parseAIJSON,
} from "../_shared/xai-client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface AnalyzeRequest {
  decisionText: string; // The decision question (10-500 chars)
  options?: Array<{ id: string; label: string; notes?: string }>; // Optional decision options
}

interface ValueAlignment {
  value: string; // value_key
  valueName: string; // display_name
  reason: string;
  strength: number; // 0.0-1.0
}

interface DecisionAnalysis {
  alignedValues: ValueAlignment[];
  conflictingValues: ValueAlignment[];
  suggestions: string[];
  confidenceScore: number; // -1.0 to 1.0
  recommendation?: string;
}

interface AnalyzeResponse {
  success: boolean;
  decisionId?: string;
  analysis?: DecisionAnalysis;
  error?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Create Supabase client
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
        },
      },
    );

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body: AnalyzeRequest = await req.json();
    const { decisionText, options } = body;

    // Validate decision text length
    if (
      !decisionText ||
      decisionText.length < 10 ||
      decisionText.length > 500
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Decision text must be between 10 and 500 characters",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch user's top 5 values
    const { data: userValues, error: valuesError } = await supabaseClient
      .from("user_values")
      .select("top_values")
      .eq("user_id", user.id)
      .single();

    if (
      valuesError ||
      !userValues ||
      !userValues.top_values ||
      userValues.top_values.length === 0
    ) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "You must complete values discovery before analyzing decisions",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch value card details for the user's top 5
    const { data: valueCards, error: cardsError } = await supabaseClient
      .from("values_cards")
      .select("value_key, display_name, description")
      .in("value_key", userValues.top_values);

    if (cardsError || !valueCards || valueCards.length === 0) {
      console.error(
        "[analyze-decision] Failed to fetch value cards:",
        cardsError,
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to load your values. Please try again.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build values context for AI prompt
    const valuesContext = valueCards
      .map(
        (card) =>
          `- ${card.display_name} (${card.value_key}): ${card.description}`,
      )
      .join("\n");

    // Sanitize decision text
    const sanitizedDecision = sanitizeForPrompt(decisionText);

    // Construct AI prompts
    const systemPrompt = `You are a values-based decision coach. Your role is to help users make decisions aligned with their core values.

Analyze the user's decision against their top 5 values and provide:
1. Which values ALIGN with the decision (support it)
2. Which values CONFLICT with the decision (oppose it)
3. 2-3 actionable suggestions for navigating this decision

Return your analysis as JSON in this exact format:
{
  "aligned": [
    {"value": "value_key", "reason": "why this value supports the decision", "strength": 0.9}
  ],
  "conflicting": [
    {"value": "value_key", "reason": "why this value opposes the decision", "strength": 0.7}
  ],
  "suggestions": [
    "Specific, actionable suggestion 1",
    "Specific, actionable suggestion 2"
  ],
  "recommendation": "Brief summary recommendation (optional)"
}

Strength scores: 0.0 (weak) to 1.0 (strong).
Be specific and practical. Avoid generic advice.`;

    const userPrompt = `User's Top 5 Values:
${valuesContext}

Decision:
"${sanitizedDecision}"

${options ? `Options being considered:\n${options.map((opt) => `- ${opt.label}${opt.notes ? ` (${opt.notes})` : ""}`).join("\n")}` : ""}

Analyze this decision against these values.`;

    // Call xAI Grok API
    console.log("[analyze-decision] Calling Grok API for decision analysis...");
    const aiResponse = await callGrokAPI(systemPrompt, userPrompt, {
      maxTokens: 300,
      temperature: 0.7,
      timeout: 10000,
    });

    // Fallback if AI fails
    if (!aiResponse) {
      console.warn("[analyze-decision] AI analysis failed, using fallback");

      // Create fallback analysis (generic)
      const fallbackAnalysis: DecisionAnalysis = {
        alignedValues: [],
        conflictingValues: [],
        suggestions: [
          "Consider how this decision aligns with your core values.",
          "Think about short-term vs long-term impact on what matters most to you.",
          "Seek advice from someone who embodies the values you're prioritizing.",
        ],
        confidenceScore: 0,
        recommendation:
          "AI analysis unavailable. Reflect on your values and trust your judgment.",
      };

      // Still save the decision with fallback analysis
      const { data: savedDecision, error: saveError } = await supabaseClient
        .from("user_decisions")
        .insert({
          user_id: user.id,
          question: decisionText,
          options: options || [],
          relevant_values: userValues.top_values,
          analysis: fallbackAnalysis,
          confidence_score: 0,
        })
        .select("id")
        .single();

      if (saveError) {
        console.error("[analyze-decision] Failed to save decision:", saveError);
      }

      const response: AnalyzeResponse = {
        success: true,
        decisionId: savedDecision?.id || "",
        analysis: fallbackAnalysis,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse AI response
    interface AIAnalysisFormat {
      aligned: Array<{ value: string; reason: string; strength: number }>;
      conflicting: Array<{ value: string; reason: string; strength: number }>;
      suggestions: string[];
      recommendation?: string;
    }

    const parsedAI = parseAIJSON<AIAnalysisFormat>(aiResponse);

    if (!parsedAI || !parsedAI.aligned || !parsedAI.conflicting) {
      console.error(
        "[analyze-decision] Failed to parse AI response:",
        aiResponse,
      );

      // Use fallback
      const fallbackAnalysis: DecisionAnalysis = {
        alignedValues: [],
        conflictingValues: [],
        suggestions: [
          "Reflect on how this decision aligns with your top values.",
          "Consider the long-term impact on what matters most to you.",
        ],
        confidenceScore: 0,
      };

      const { data: savedDecision } = await supabaseClient
        .from("user_decisions")
        .insert({
          user_id: user.id,
          question: decisionText,
          options: options || [],
          relevant_values: userValues.top_values,
          analysis: fallbackAnalysis,
          confidence_score: 0,
        })
        .select("id")
        .single();

      return new Response(
        JSON.stringify({
          success: true,
          decisionId: savedDecision?.id || "",
          analysis: fallbackAnalysis,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Build final analysis with value names
    const alignedValues: ValueAlignment[] = parsedAI.aligned.map((item) => {
      const card = valueCards.find((c) => c.value_key === item.value);
      return {
        value: item.value,
        valueName: card?.display_name || item.value,
        reason: item.reason,
        strength: item.strength,
      };
    });

    const conflictingValues: ValueAlignment[] = parsedAI.conflicting.map(
      (item) => {
        const card = valueCards.find((c) => c.value_key === item.value);
        return {
          value: item.value,
          valueName: card?.display_name || item.value,
          reason: item.reason,
          strength: item.strength,
        };
      },
    );

    // Compute confidence score: (aligned - conflicting) / total
    // Range: -1.0 (all conflict) to +1.0 (all align)
    const totalValues = userValues.top_values.length;
    const alignedCount = alignedValues.length;
    const conflictingCount = conflictingValues.length;
    const confidenceScore =
      totalValues > 0 ? (alignedCount - conflictingCount) / totalValues : 0;

    const finalAnalysis: DecisionAnalysis = {
      alignedValues,
      conflictingValues,
      suggestions: parsedAI.suggestions || [],
      confidenceScore: Math.max(-1, Math.min(1, confidenceScore)), // Clamp to [-1, 1]
      recommendation: parsedAI.recommendation,
    };

    // Save decision to database
    const { data: savedDecision, error: saveError } = await supabaseClient
      .from("user_decisions")
      .insert({
        user_id: user.id,
        question: decisionText,
        options: options || [],
        relevant_values: userValues.top_values,
        analysis: finalAnalysis,
        confidence_score: finalAnalysis.confidenceScore,
      })
      .select("id")
      .single();

    if (saveError) {
      console.error("[analyze-decision] Failed to save decision:", saveError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to save decision. Please try again.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const response: AnalyzeResponse = {
      success: true,
      decisionId: savedDecision.id,
      analysis: finalAnalysis,
    };

    console.log(
      `[analyze-decision] Success - Decision ID: ${savedDecision.id}, Confidence: ${finalAnalysis.confidenceScore.toFixed(2)}`,
    );

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("[analyze-decision] Unexpected error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
