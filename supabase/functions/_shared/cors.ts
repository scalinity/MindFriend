// CORS headers and request validation for Edge Functions
// For mobile-only apps, we restrict CORS to prevent browser-based attacks
// The iOS app doesn't send Origin headers, so requests without Origin are allowed

const ALLOWED_ORIGINS = [
  "capacitor://localhost", // iOS Capacitor apps
  "ionic://localhost", // Ionic apps
  "http://localhost:3000", // Local development
  "http://localhost:5173", // Vite dev server
];

export function getCorsHeaders(origin: string | null): Record<string, string> {
  // Allow requests without Origin header (native mobile apps)
  // Or from explicitly allowed origins
  const allowedOrigin =
    !origin || ALLOWED_ORIGINS.includes(origin) ? origin || "*" : "null";

  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "X-Content-Type-Options": "nosniff",
  };
}

// Legacy export for backward compatibility - prefer getCorsHeaders()
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * Validate Content-Type header for JSON requests
 * Returns an error response if Content-Type is not application/json
 */
export function validateContentType(
  req: Request,
  corsHeaders: Record<string, string>
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
      }
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
