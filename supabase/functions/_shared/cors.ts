// CORS headers for Edge Functions
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
