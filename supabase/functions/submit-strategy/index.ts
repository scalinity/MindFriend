/**
 * submit-strategy Edge Function
 * Handles user-submitted coping strategies with moderation
 *
 * Security:
 * - Rate limited: 5 submissions per day per user
 * - PII detection before storage
 * - Content length limits
 * - Category validation
 * - Status defaults to pending (requires approval)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  validateStrategyText,
  isValidCategory,
  VALID_CATEGORIES,
} from "../_shared/pii-detector.ts";

// Rate limiting configuration - more strict for submissions
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000; // 24 hours
const RATE_LIMIT_MAX_REQUESTS = 5;
const rateLimitCache = new Map<string, { count: number; resetAt: number }>();

const corsHeaders = {
  "Access-Control-Allow-Origin":
    Deno.env.get("ALLOWED_ORIGIN") || "https://getmindfriend.app",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface SubmitStrategyRequest {
  category: string;
  strategyText: string;
  context?: string;
  subcategory?: string;
}

/**
 * Checks rate limit for a user
 */
function checkRateLimit(userId: string): {
  allowed: boolean;
  remaining: number;
  resetAt: number;
} {
  const now = Date.now();
  const key = `submit:${userId}`;

  let entry = rateLimitCache.get(key);

  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };
    rateLimitCache.set(key, entry);
  }

  if (entry.count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }

  entry.count++;
  return {
    allowed: true,
    remaining: RATE_LIMIT_MAX_REQUESTS - entry.count,
    resetAt: entry.resetAt,
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "UNAUTHORIZED", message: "Invalid token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check rate limit
    const rateLimit = checkRateLimit(user.id);
    if (!rateLimit.allowed) {
      return new Response(
        JSON.stringify({
          error: "RATE_LIMITED",
          message:
            "You've reached the daily submission limit. Please try again tomorrow.",
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": String(Math.ceil(rateLimit.resetAt / 1000)),
          },
        },
      );
    }

    // Parse request body
    const body: SubmitStrategyRequest = await req.json();
    const { category, strategyText, context, subcategory } = body;

    // Validate category
    if (!category || !isValidCategory(category)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_CATEGORY",
          message: "Please select a valid category",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate strategy text (length, PII, content quality)
    const textValidation = validateStrategyText(strategyText);
    if (!textValidation.valid) {
      return new Response(
        JSON.stringify({
          error: textValidation.hasPII ? "PII_DETECTED" : "INVALID_CONTENT",
          message: textValidation.hasPII
            ? "Please remove personal information before submitting"
            : textValidation.errors[0] || "Invalid content",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate context if provided
    if (context && context.length > 200) {
      return new Response(
        JSON.stringify({
          error: "INVALID_CONTENT",
          message: "Context must be 200 characters or less",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for duplicate strategies (fuzzy match would be better, but basic check for MVP)
    const { data: existingStrategies } = await supabase
      .from("community_strategies")
      .select("id, strategy_text")
      .eq("category", category)
      .eq("status", "approved")
      .limit(100);

    if (existingStrategies) {
      const normalizedNew = normalizeText(strategyText);
      for (const existing of existingStrategies) {
        const normalizedExisting = normalizeText(existing.strategy_text);
        if (calculateSimilarity(normalizedNew, normalizedExisting) > 0.8) {
          return new Response(
            JSON.stringify({
              error: "DUPLICATE_STRATEGY",
              message:
                "A similar strategy already exists. Try adding a unique perspective.",
            }),
            {
              status: 409,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // Insert strategy with pending status
    const { data: strategy, error: insertError } = await supabase
      .from("community_strategies")
      .insert({
        category,
        subcategory: subcategory || null,
        strategy_text: strategyText.trim(),
        context: context?.trim() || null,
        status: "pending", // Requires moderation
      })
      .select("id, status")
      .single();

    if (insertError) {
      console.error("Insert error:", insertError);
      return new Response(
        JSON.stringify({
          error: "INSERT_FAILED",
          message: "Failed to save strategy",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check moderation queue size (alert if backlog)
    const { count: pendingCount } = await supabase
      .from("community_strategies")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending");

    let message = "Thanks for sharing! Your strategy will be reviewed.";
    if (pendingCount && pendingCount > 100) {
      message =
        "Thanks for sharing! Review may take 2-3 days due to high volume.";
    }

    return new Response(
      JSON.stringify({
        success: true,
        strategyId: strategy.id,
        status: strategy.status,
        message,
      }),
      {
        status: 201,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Submit strategy error:", error);
    return new Response(
      JSON.stringify({
        error: "INTERNAL_ERROR",
        message: "An unexpected error occurred",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Normalizes text for comparison
 */
function normalizeText(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Calculates simple Jaccard similarity between two strings
 */
function calculateSimilarity(text1: string, text2: string): number {
  const words1 = new Set(text1.split(" "));
  const words2 = new Set(text2.split(" "));

  const intersection = new Set([...words1].filter((w) => words2.has(w)));
  const union = new Set([...words1, ...words2]);

  return intersection.size / union.size;
}
