import { Throttle, SkipThrottle } from '@nestjs/throttler';

/**
 * Apply auth rate limit (10 requests/minute)
 * Use on authentication endpoints
 */
export const ThrottleAuth = () => Throttle({ auth: { limit: 10, ttl: 60000 } });

/**
 * Apply chat rate limit (60 requests/minute)
 * Use on chat/AI endpoints
 */
export const ThrottleChat = () => Throttle({ chat: { limit: 60, ttl: 60000 } });

/**
 * Apply default rate limit (100 requests/minute)
 * Use on general API endpoints
 */
export const ThrottleDefault = () =>
  Throttle({ default: { limit: 100, ttl: 60000 } });

/**
 * Apply strict rate limit (5 requests/minute)
 * Use on sensitive endpoints like password reset, account deletion
 */
export const ThrottleStrict = () =>
  Throttle({ default: { limit: 5, ttl: 60000 } });

/**
 * Skip rate limiting for this endpoint
 * Use sparingly - only for health checks, etc.
 */
export { SkipThrottle };
