// Rate limiting using Supabase database
// Uses sliding window approach with PostgreSQL

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: Date;
  retryAfter?: number; // seconds
}

interface RateLimitConfig {
  windowMs: number; // Time window in milliseconds
  maxRequests: number; // Maximum requests per window
}

// Default: 10 requests per minute
const DEFAULT_CONFIG: RateLimitConfig = {
  windowMs: 60 * 1000, // 1 minute
  maxRequests: 10,
};

/**
 * Check and record rate limit for a user
 * Uses PostgreSQL for distributed rate limiting across Edge Function instances
 */
export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  endpoint: string,
  config: RateLimitConfig = DEFAULT_CONFIG,
): Promise<RateLimitResult> {
  const now = new Date();
  const windowStart = new Date(now.getTime() - config.windowMs);

  // Use atomic database operation to check and increment
  const { data, error } = await supabase.rpc("check_rate_limit", {
    p_user_id: userId,
    p_endpoint: endpoint,
    p_window_start: windowStart.toISOString(),
    p_max_requests: config.maxRequests,
    p_window_ms: config.windowMs,
  });

  if (error) {
    // On error, fail closed for security-critical endpoints to prevent abuse
    console.error("Rate limit check failed (failing closed):", error.code);
    return {
      allowed: false,
      remaining: 0,
      resetAt: new Date(now.getTime() + config.windowMs),
      retryAfter: Math.ceil(config.windowMs / 1000),
    };
  }

  const result = data?.[0];
  if (!result) {
    return {
      allowed: true,
      remaining: config.maxRequests,
      resetAt: new Date(now.getTime() + config.windowMs),
    };
  }

  const resetAt = new Date(result.reset_at);
  const retryAfter = result.allowed
    ? undefined
    : Math.ceil((resetAt.getTime() - now.getTime()) / 1000);

  return {
    allowed: result.allowed,
    remaining: result.remaining,
    resetAt,
    retryAfter,
  };
}

/**
 * Generate rate limit headers for response
 */
export function getRateLimitHeaders(
  result: RateLimitResult,
): Record<string, string> {
  const headers: Record<string, string> = {
    "X-RateLimit-Remaining": String(result.remaining),
    "X-RateLimit-Reset": String(Math.floor(result.resetAt.getTime() / 1000)),
  };

  if (result.retryAfter) {
    headers["Retry-After"] = String(result.retryAfter);
  }

  return headers;
}
