// CORS headers and request validation for Edge Functions
// For mobile-only apps, we restrict CORS to prevent browser-based attacks
// The iOS app doesn't send Origin headers, so requests without Origin are allowed

const ALLOWED_ORIGINS = [
  "capacitor://localhost", // iOS Capacitor apps
  "ionic://localhost", // Ionic apps
  "http://localhost:3000", // Local development
  "http://localhost:5173", // Vite dev server
  "https://getmindfriend.app", // Production website
];

export function getCorsHeaders(origin: string | null): Record<string, string> {
  // Allow requests without Origin header (native mobile apps)
  // Or from explicitly allowed origins
  // SECURITY: Do NOT allow arbitrary origins - only whitelisted ones
  let allowedOrigin: string;

  if (!origin) {
    // No origin = native mobile app or server-to-server
    // Allow but don't reflect back wildcard
    allowedOrigin = "null";
  } else if (ALLOWED_ORIGINS.includes(origin)) {
    // Whitelisted origin - reflect it back
    allowedOrigin = origin;
  } else {
    // Unknown origin - reject with null
    allowedOrigin = "null";
  }

  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400", // Cache preflight for 24 hours
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
  };
}

// Rate limiting helper - IN-MEMORY IMPLEMENTATION (DEPRECATED)
// SECURITY WARNING: This in-memory rate limiter does NOT work across Edge Function instances.
// Distributed requests can bypass rate limits. Use ratelimit.ts (database-backed) instead.
// See: supabase/functions/_shared/ratelimit.ts
const rateLimitStore = new Map<string, { count: number; resetAt: number }>();

/**
 * @deprecated Use checkRateLimit from ratelimit.ts instead.
 * This in-memory implementation does not work across Edge Function instances
 * and should not be used in production code.
 *
 * Import from ratelimit.ts:
 * import { checkRateLimit } from "./_shared/ratelimit.ts";
 *
 * @internal This function is exported only for backward compatibility.
 * It will be removed in a future version.
 */
export function _deprecatedInMemoryRateLimit(
  identifier: string,
  maxRequests: number = 60,
  windowMs: number = 60000, // 1 minute window
): { allowed: boolean; remaining: number; resetIn: number } {
  console.warn(
    "⚠️ DEPRECATED: Using in-memory rate limiter from cors.ts. " +
    "This does NOT work across Edge Function instances. " +
    "Import checkRateLimit from _shared/ratelimit.ts (database-backed) instead.",
  );

  const now = Date.now();
  const entry = rateLimitStore.get(identifier);

  if (!entry || now > entry.resetAt) {
    // New window
    rateLimitStore.set(identifier, { count: 1, resetAt: now + windowMs });
    return { allowed: true, remaining: maxRequests - 1, resetIn: windowMs };
  }

  if (entry.count >= maxRequests) {
    // Rate limited
    return {
      allowed: false,
      remaining: 0,
      resetIn: entry.resetAt - now,
    };
  }

  // Increment count
  entry.count++;
  return {
    allowed: true,
    remaining: maxRequests - entry.count,
    resetIn: entry.resetAt - now,
  };
}

export function getRateLimitHeaders(
  remaining: number,
  resetIn: number,
): Record<string, string> {
  return {
    "X-RateLimit-Remaining": String(remaining),
    "X-RateLimit-Reset": String(Math.ceil(resetIn / 1000)),
  };
}

// Legacy export for backward compatibility - prefer getCorsHeaders()
// NOTE: This should only be used for internal/cron functions that don't need CORS
export const corsHeaders = {
  "Access-Control-Allow-Origin": "null",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "X-Content-Type-Options": "nosniff",
};

/**
 * Validate Content-Type header for JSON requests
 * Returns an error response if Content-Type is not application/json
 */
export function validateContentType(
  req: Request,
  corsHeaders: Record<string, string>,
): Response | null {
  // Skip validation for OPTIONS (preflight) and GET requests
  if (req.method === "OPTIONS" || req.method === "GET") {
    return null;
  }

  const contentType = req.headers.get("Content-Type");

  // Allow requests without body (empty POST)
  const contentLength = req.headers.get("Content-Length");
  if (contentLength === "0" || contentLength === null) {
    return null;
  }

  // Check for JSON content type
  if (!contentType?.includes("application/json")) {
    return new Response(
      JSON.stringify({
        error: "Content-Type must be application/json",
        code: "INVALID_CONTENT_TYPE",
      }),
      {
        status: 415, // Unsupported Media Type
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  return null;
}

/**
 * Helper to parse JSON body with error handling
 * Returns null on parse error and the parsed body on success
 */
export async function parseJsonBody<T>(req: Request): Promise<T | null> {
  try {
    return await req.json();
  } catch {
    return null;
  }
}
