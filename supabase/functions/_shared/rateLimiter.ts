/**
 * Rate limiting utility for Edge Functions
 * Uses Supabase database for tracking request counts
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface RateLimitConfig {
  maxRequests: number; // Max requests allowed
  windowSeconds: number; // Time window in seconds
  keyPrefix: string; // Prefix for the rate limit key (e.g., "efficacy-calc")
}

export interface RateLimitResult {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: Date;
}

/**
 * Simple in-memory rate limiter for Edge Functions
 * Uses a sliding window algorithm
 */
class RateLimiter {
  private config: RateLimitConfig;
  private supabase: SupabaseClient;

  constructor(config: RateLimitConfig, supabase: SupabaseClient) {
    this.config = config;
    this.supabase = supabase;
  }

  /**
   * Check if request is allowed under rate limit
   */
  async checkLimit(identifier: string): Promise<RateLimitResult> {
    const key = `${this.config.keyPrefix}:${identifier}`;
    const now = new Date();
    const windowStart = new Date(
      now.getTime() - this.config.windowSeconds * 1000,
    );

    try {
      // Count requests in current window
      const { count, error } = await this.supabase
        .from("rate_limit_tracker")
        .select("*", { count: "exact", head: true })
        .eq("key", key)
        .gte("timestamp", windowStart.toISOString());

      if (error) {
        console.error("Rate limit check error:", error);
        // Fail open - allow request if we can't check
        return {
          allowed: true,
          limit: this.config.maxRequests,
          remaining: this.config.maxRequests,
          resetAt: new Date(now.getTime() + this.config.windowSeconds * 1000),
        };
      }

      const requestCount = count || 0;
      const remaining = Math.max(0, this.config.maxRequests - requestCount - 1);
      const resetAt = new Date(now.getTime() + this.config.windowSeconds * 1000);

      if (requestCount >= this.config.maxRequests) {
        return {
          allowed: false,
          limit: this.config.maxRequests,
          remaining: 0,
          resetAt,
        };
      }

      // Record this request
      await this.supabase.from("rate_limit_tracker").insert({
        key,
        timestamp: now.toISOString(),
      });

      return {
        allowed: true,
        limit: this.config.maxRequests,
        remaining,
        resetAt,
      };
    } catch (error) {
      console.error("Rate limiter error:", error);
      // Fail open
      return {
        allowed: true,
        limit: this.config.maxRequests,
        remaining: this.config.maxRequests,
        resetAt: new Date(now.getTime() + this.config.windowSeconds * 1000),
      };
    }
  }

  /**
   * Clean up old rate limit records (call periodically)
   */
  async cleanup(): Promise<void> {
    const cutoff = new Date(
      Date.now() - this.config.windowSeconds * 1000 * 2,
    ); // Keep 2x window

    try {
      await this.supabase
        .from("rate_limit_tracker")
        .delete()
        .lt("timestamp", cutoff.toISOString());
    } catch (error) {
      console.error("Rate limit cleanup error:", error);
    }
  }
}

/**
 * Create rate limiter instance
 */
export function createRateLimiter(
  config: RateLimitConfig,
  supabase: SupabaseClient,
): RateLimiter {
  return new RateLimiter(config, supabase);
}

/**
 * Common rate limit configs for different function types
 */
export const RATE_LIMITS = {
  // Calculate efficacy: 20 requests per hour (one per exercise session)
  CALCULATE_EFFICACY: {
    maxRequests: 20,
    windowSeconds: 3600,
    keyPrefix: "calc-efficacy",
  },

  // Get recommendations: 100 requests per hour (frequent access)
  GET_RECOMMENDATIONS: {
    maxRequests: 100,
    windowSeconds: 3600,
    keyPrefix: "recommendations",
  },

  // Get dashboard: 50 requests per hour (moderate access)
  GET_DASHBOARD: {
    maxRequests: 50,
    windowSeconds: 3600,
    keyPrefix: "dashboard",
  },

  // Aggregate profiles: cron only (no user rate limit)
  AGGREGATE_PROFILES: {
    maxRequests: 5,
    windowSeconds: 86400, // 1 day
    keyPrefix: "aggregate",
  },
};
