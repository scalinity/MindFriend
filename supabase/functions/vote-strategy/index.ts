/**
 * vote-strategy Edge Function
 * Handles helpful/not-helpful votes on community strategies
 *
 * Features:
 * - One vote per user per strategy (UPSERT)
 * - Rate limited: 30 votes per hour per user
 * - Atomic count updates via database trigger with SERIALIZABLE isolation
 * - Vote change support (switch from helpful to not-helpful)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Rate limiting configuration
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_MAX_REQUESTS = 30;
const rateLimitCache = new Map<string, { count: number; resetAt: number }>();

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") || "app.mindfriend.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface VoteRequest {
  strategyId: string;
  voteType: "helpful" | "not_helpful";
}

/**
 * Checks rate limit for a user
 */
function checkRateLimit(userId: string): { allowed: boolean; remaining: number; resetAt: number } {
  const now = Date.now();
  const key = `vote:${userId}`;
  
  let entry = rateLimitCache.get(key);
  
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };
    rateLimitCache.set(key, entry);
  }
  
  if (entry.count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }
  
  entry.count++;
  return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - entry.count, resetAt: entry.resetAt };
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
          message: "Too many votes. Please try again later.",
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
    const body: VoteRequest = await req.json();
    const { strategyId, voteType } = body;

    // Validate vote type
    if (!voteType || !["helpful", "not_helpful"].includes(voteType)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_VOTE_TYPE",
          message: "Vote type must be 'helpful' or 'not_helpful'",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate strategy ID format
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!strategyId || !uuidRegex.test(strategyId)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_STRATEGY_ID",
          message: "Invalid strategy ID format",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify strategy exists and is approved
    const { data: strategy, error: strategyError } = await supabase
      .from("community_strategies")
      .select("id, status, helpful_count, not_helpful_count")
      .eq("id", strategyId)
      .single();

    if (strategyError || !strategy) {
      return new Response(
        JSON.stringify({
          error: "STRATEGY_NOT_FOUND",
          message: "Strategy not found",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (strategy.status !== "approved") {
      return new Response(
        JSON.stringify({
          error: "STRATEGY_NOT_APPROVED",
          message: "Can only vote on approved strategies",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Use RPC function for atomic vote with SERIALIZABLE isolation
    // This prevents race conditions in vote count updates
    const { data: voteResult, error: voteError } = await supabase.rpc(
      "upsert_strategy_vote",
      {
        p_strategy_id: strategyId,
        p_user_id: user.id,
        p_vote_type: voteType,
      }
    );

    if (voteError) {
      console.error("Vote error:", voteError.code);
      return new Response(
        JSON.stringify({
          error: "VOTE_FAILED",
          message: "Failed to record vote",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get updated counts from the RPC result
    const helpfulCount = voteResult?.helpful_count ?? strategy.helpful_count ?? 0;
    const notHelpfulCount = voteResult?.not_helpful_count ?? strategy.not_helpful_count ?? 0;
    const total = helpfulCount + notHelpfulCount;
    const helpfulPercentage =
      total > 0 ? Math.round((helpfulCount / total) * 100) : 0;

    return new Response(
      JSON.stringify({
        success: true,
        strategyId,
        voteType,
        strategy: {
          helpfulCount,
          notHelpfulCount,
          helpfulPercentage,
        },
      }),
      {
        status: 200,
        headers: { 
          ...corsHeaders, 
          "Content-Type": "application/json",
          "X-RateLimit-Remaining": String(rateLimit.remaining),
        },
      },
    );
  } catch (error) {
    console.error("Vote strategy error:", (error as Error).message);
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
