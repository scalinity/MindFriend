/**
 * HTTPS/TLS Enforcement Middleware
 * Purpose: Ensure all requests use secure HTTPS connections
 * Security: Blocks non-HTTPS requests in production
 */

/**
 * Check if request is using HTTPS
 * @param req - Request object
 * @returns { secure: boolean, error?: Response }
 */
export function enforceHTTPS(req: Request): {
  secure: boolean;
  error?: Response;
} {
  const url = new URL(req.url);

  // Allow HTTP for local development
  const isLocalDev =
    url.hostname === "localhost" ||
    url.hostname === "127.0.0.1" ||
    url.hostname.endsWith(".local");

  if (isLocalDev) {
    return { secure: true };
  }

  // Check X-Forwarded-Proto header (set by reverse proxy/load balancer)
  // Supabase Edge Functions terminate TLS at the load balancer, so we need to check this header
  const forwardedProto =
    req.headers.get("X-Forwarded-Proto") ||
    req.headers.get("x-forwarded-proto");
  const isHttps = forwardedProto === "https" || url.protocol === "https:";

  // Enforce HTTPS in production
  if (!isHttps) {
    return {
      secure: false,
      error: new Response(
        JSON.stringify({
          error: "HTTPS_REQUIRED",
          message:
            "This endpoint requires a secure HTTPS connection. Please use https:// instead of http://",
        }),
        {
          status: 426, // Upgrade Required
          headers: {
            "Content-Type": "application/json",
            Upgrade: "TLS/1.3, HTTP/1.1",
            Connection: "Upgrade",
          },
        },
      ),
    };
  }

  // Check for TLS version in headers (if provided by reverse proxy)
  const tlsVersion = req.headers.get("X-Forwarded-Proto-Version");
  if (tlsVersion && parseFloat(tlsVersion) < 1.2) {
    return {
      secure: false,
      error: new Response(
        JSON.stringify({
          error: "TLS_VERSION_TOO_OLD",
          message: "TLS 1.2 or higher is required. Please upgrade your client.",
        }),
        {
          status: 426,
          headers: {
            "Content-Type": "application/json",
          },
        },
      ),
    };
  }

  return { secure: true };
}

/**
 * Set security headers for HTTPS enforcement
 * @returns Headers object with security headers
 */
export function getSecurityHeaders(): Record<string, string> {
  return {
    // Force HTTPS for 1 year
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
    // Prevent MIME sniffing
    "X-Content-Type-Options": "nosniff",
    // Prevent clickjacking
    "X-Frame-Options": "DENY",
    // XSS protection
    "X-XSS-Protection": "1; mode=block",
    // Referrer policy
    "Referrer-Policy": "strict-origin-when-cross-origin",
    // Content Security Policy
    "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'",
  };
}
