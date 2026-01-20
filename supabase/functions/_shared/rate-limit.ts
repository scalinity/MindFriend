/**
 * Rate Limiting Utilities for Therapist API
 * Uses in-memory sliding window with periodic cleanup
 */

interface RateLimitEntry {
  timestamps: number[];
}

// In-memory store (per function instance)
const rateLimitStore = new Map<string, RateLimitEntry>();

// Cleanup old entries every 5 minutes
setInterval(
  () => {
    const now = Date.now();
    const oneHourAgo = now - 60 * 60 * 1000;

    for (const [key, entry] of rateLimitStore.entries()) {
      entry.timestamps = entry.timestamps.filter((ts) => ts > oneHourAgo);
      if (entry.timestamps.length === 0) {
        rateLimitStore.delete(key);
      }
    }
  },
  5 * 60 * 1000,
);

/**
 * Check if request is within rate limit
 * @param key - Unique identifier (e.g., api_key_id)
 * @param limitPerHour - Maximum requests allowed per hour
 * @returns { allowed: boolean, remaining: number, resetAt: Date }
 */
export function checkRateLimit(
  key: string,
  limitPerHour: number,
): { allowed: boolean; remaining: number; resetAt: Date } {
  const now = Date.now();
  const oneHourAgo = now - 60 * 60 * 1000;

  // Get or create entry
  let entry = rateLimitStore.get(key);
  if (!entry) {
    entry = { timestamps: [] };
    rateLimitStore.set(key, entry);
  }

  // Remove timestamps older than 1 hour
  entry.timestamps = entry.timestamps.filter((ts) => ts > oneHourAgo);

  // Check if limit exceeded
  const currentCount = entry.timestamps.length;
  const allowed = currentCount < limitPerHour;

  if (allowed) {
    // Record this request
    entry.timestamps.push(now);
  }

  // Calculate reset time (oldest timestamp + 1 hour)
  const oldestTimestamp = entry.timestamps[0] || now;
  const resetAt = new Date(oldestTimestamp + 60 * 60 * 1000);

  return {
    allowed,
    remaining: Math.max(0, limitPerHour - currentCount - (allowed ? 1 : 0)),
    resetAt,
  };
}

/**
 * Clear rate limit for a specific key (useful for testing)
 */
export function clearRateLimit(key: string): void {
  rateLimitStore.delete(key);
}

/**
 * Get current request count for a key
 */
export function getCurrentCount(key: string): number {
  const now = Date.now();
  const oneHourAgo = now - 60 * 60 * 1000;

  const entry = rateLimitStore.get(key);
  if (!entry) return 0;

  entry.timestamps = entry.timestamps.filter((ts) => ts > oneHourAgo);
  return entry.timestamps.length;
}
