// Couples Mode Rate Limiting
// Sliding window rate limit checks using rate_limit_tracker table

// ============================================================================
// RATE LIMIT TYPES
// ============================================================================

export type RateLimitAction =
  | "invite_code"
  | "failed_invite_attempt"
  | "appreciation"
  | "session_rating";

interface RateLimitConfig {
  action: RateLimitAction;
  maxCount: number;
  windowHours: number;
}

// ============================================================================
// RATE LIMIT CONFIGURATIONS
// ============================================================================

const RATE_LIMIT_CONFIGS: Record<RateLimitAction, RateLimitConfig> = {
  invite_code: {
    action: "invite_code",
    maxCount: 3,
    windowHours: 24,
  },
  failed_invite_attempt: {
    action: "failed_invite_attempt",
    maxCount: 5,
    windowHours: 0.0167, // 1 minute = 0.0167 hours
  },
  appreciation: {
    action: "appreciation",
    maxCount: 10,
    windowHours: 24,
  },
  session_rating: {
    action: "session_rating",
    maxCount: 1000, // Not enforced (per-session limit)
    windowHours: 24,
  },
};

// ============================================================================
// RATE LIMIT CHECKER
// ============================================================================

/**
 * Check if user has exceeded rate limit for given action
 * Returns true if limit exceeded, false if within limit
 *
 * Uses sliding window: counts all attempts in last N hours
 */
export async function checkRateLimit(
  supabase: any,
  userId: string,
  action: RateLimitAction,
): Promise<boolean> {
  try {
    const config = RATE_LIMIT_CONFIGS[action];
    if (!config) {
      console.error(`Unknown rate limit action: ${action}`);
      return false; // Fail open if config missing
    }

    // Query rate_limit_tracker for recent attempts
    // Using: created_at > NOW() - INTERVAL '<windowHours> hours'
    const windowIntervalString =
      config.windowHours < 1
        ? `${Math.round(config.windowHours * 60)} minutes`
        : `${config.windowHours} hours`;

    const { data: attempts, error } = await supabase
      .from("rate_limit_tracker")
      .select("id", { count: "exact" })
      .eq("user_id", userId)
      .eq("action", action)
      .gt(
        "created_at",
        new Date(Date.now() - config.windowHours * 3600 * 1000).toISOString(),
      );

    if (error) {
      console.error("Rate limit check error:", error);
      return false; // Fail open on database error
    }

    const attemptCount = attempts?.length || 0;
    const isLimited = attemptCount >= config.maxCount;

    if (isLimited) {
      console.warn(
        `Rate limit exceeded for ${userId} action=${action} count=${attemptCount}/${config.maxCount}`,
      );
    }

    return isLimited;
  } catch (error) {
    console.error("Rate limit check exception:", error);
    return false; // Fail open on unexpected error
  }
}

// ============================================================================
// RATE LIMIT LOGGER
// ============================================================================

/**
 * Log an attempt in rate_limit_tracker table
 * Called for both successful and failed attempts
 */
export async function logRateLimitAttempt(
  supabase: any,
  userId: string,
  action: RateLimitAction,
): Promise<void> {
  try {
    const { error } = await supabase.from("rate_limit_tracker").insert({
      user_id: userId,
      action: action,
      created_at: new Date().toISOString(),
    });

    if (error) {
      console.error("Failed to log rate limit attempt:", error);
      // Don't throw - rate limit logging shouldn't break the request
    }
  } catch (error) {
    console.error("Rate limit logging exception:", error);
    // Don't throw - rate limit logging shouldn't break the request
  }
}

// ============================================================================
// CONVENIENCE FUNCTIONS (Action-specific)
// ============================================================================

/**
 * Check if user can send invite (max 3/24h)
 */
export async function canSendInvite(
  supabase: any,
  userId: string,
): Promise<boolean> {
  return !(await checkRateLimit(supabase, userId, "invite_code"));
}

/**
 * Check if user can send appreciation (max 10/24h)
 */
export async function canSendAppreciation(
  supabase: any,
  userId: string,
): Promise<boolean> {
  return !(await checkRateLimit(supabase, userId, "appreciation"));
}

/**
 * Check if user has exceeded failed invite attempts (max 5/min)
 */
export async function tooManyFailedAttempts(
  supabase: any,
  userId: string,
): Promise<boolean> {
  return await checkRateLimit(supabase, userId, "failed_invite_attempt");
}

// ============================================================================
// BATCH LOGGING (Utility for cleanup)
// ============================================================================

/**
 * Clean up old rate limit entries (older than 30 days)
 * Should be called periodically (e.g., via cron job)
 */
export async function cleanupOldRateLimitEntries(
  supabase: any,
  daysToKeep: number = 30,
): Promise<number> {
  try {
    const cutoffDate = new Date(
      Date.now() - daysToKeep * 24 * 3600 * 1000,
    ).toISOString();

    const { error } = await supabase
      .from("rate_limit_tracker")
      .delete()
      .lt("created_at", cutoffDate);

    if (error) {
      console.error("Failed to cleanup rate limit entries:", error);
      return 0;
    }

    console.log(`Cleaned up rate limit entries older than ${daysToKeep} days`);
    return 1;
  } catch (error) {
    console.error("Cleanup exception:", error);
    return 0;
  }
}
