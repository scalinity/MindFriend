// Simple in-memory rate limiter for Edge Functions
// SECURITY: Prevents DoS attacks and resource exhaustion

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

const rateLimits = new Map<string, RateLimitEntry>();

/**
 * Check if user has exceeded rate limit
 * @param userId - User identifier
 * @param maxRequests - Maximum requests allowed in window
 * @param windowMs - Time window in milliseconds
 * @returns true if within limit, false if exceeded
 */
export function checkRateLimit(
  userId: string,
  maxRequests: number,
  windowMs: number,
): boolean {
  const now = Date.now();
  const userLimit = rateLimits.get(userId);

  // No existing limit or window expired
  if (!userLimit || now > userLimit.resetAt) {
    rateLimits.set(userId, { count: 1, resetAt: now + windowMs });
    return true;
  }

  // Rate limit exceeded
  if (userLimit.count >= maxRequests) {
    return false;
  }

  // Increment count
  userLimit.count++;
  return true;
}

/**
 * Create rate limit exceeded response
 */
export function createRateLimitResponse(retryAfterSeconds: number): Response {
  return new Response(
    JSON.stringify({
      error: "rate_limit_exceeded",
      message: "Too many requests. Please try again later.",
      retryAfter: retryAfterSeconds,
    }),
    {
      status: 429,
      headers: {
        "Content-Type": "application/json",
        "Retry-After": retryAfterSeconds.toString(),
      },
    },
  );
}

/**
 * Cleanup expired rate limit entries (call periodically)
 */
export function cleanupExpiredLimits(): void {
  const now = Date.now();
  for (const [userId, entry] of rateLimits.entries()) {
    if (now > entry.resetAt) {
      rateLimits.delete(userId);
    }
  }
}

// Cleanup every 5 minutes
setInterval(cleanupExpiredLimits, 5 * 60 * 1000);
