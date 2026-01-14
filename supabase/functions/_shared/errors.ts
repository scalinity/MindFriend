// Standardized error response utility for Edge Functions
// All error responses should use this format for consistency

export interface ErrorResponse {
  error: string;
  code: string;
  message?: string;
  details?: Record<string, unknown>;
}

export interface StandardError {
  status: number;
  body: ErrorResponse;
}

/**
 * Standard error codes used across all Edge Functions
 */
export const ErrorCodes = {
  // Authentication errors (4xx)
  UNAUTHORIZED: "UNAUTHORIZED",
  FORBIDDEN: "FORBIDDEN",
  INVALID_TOKEN: "INVALID_TOKEN",
  SESSION_EXPIRED: "SESSION_EXPIRED",

  // Validation errors (400)
  BAD_REQUEST: "BAD_REQUEST",
  INVALID_INPUT: "INVALID_INPUT",
  MISSING_FIELD: "MISSING_FIELD",
  INVALID_FORMAT: "INVALID_FORMAT",

  // Rate limiting (429)
  RATE_LIMITED: "RATE_LIMITED",

  // Quota errors (429/403)
  QUOTA_EXCEEDED: "QUOTA_EXCEEDED",
  AI_QUOTA_EXCEEDED: "AI_QUOTA_EXCEEDED",
  VOICE_QUOTA_EXCEEDED: "VOICE_QUOTA_EXCEEDED",

  // Resource errors (404)
  NOT_FOUND: "NOT_FOUND",
  RESOURCE_NOT_FOUND: "RESOURCE_NOT_FOUND",

  // Server errors (5xx)
  INTERNAL_ERROR: "INTERNAL_ERROR",
  SERVICE_UNAVAILABLE: "SERVICE_UNAVAILABLE",
  CONFIG_ERROR: "CONFIG_ERROR",
  EXTERNAL_SERVICE_ERROR: "EXTERNAL_SERVICE_ERROR",
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];

/**
 * Create a standardized error response
 */
export function createErrorResponse(
  corsHeaders: Record<string, string>,
  error: string,
  code: ErrorCode,
  status: number,
  details?: Record<string, unknown>
): Response {
  const body: ErrorResponse = {
    error,
    code,
  };

  if (details) {
    body.details = details;
  }

  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Common error responses for reuse
 */
export const CommonErrors = {
  unauthorized: (corsHeaders: Record<string, string>) =>
    createErrorResponse(
      corsHeaders,
      "Missing authorization",
      ErrorCodes.UNAUTHORIZED,
      401
    ),

  invalidToken: (corsHeaders: Record<string, string>) =>
    createErrorResponse(
      corsHeaders,
      "Invalid or expired token",
      ErrorCodes.INVALID_TOKEN,
      401
    ),

  forbidden: (corsHeaders: Record<string, string>, message = "Access denied") =>
    createErrorResponse(corsHeaders, message, ErrorCodes.FORBIDDEN, 403),

  badRequest: (
    corsHeaders: Record<string, string>,
    message: string,
    details?: Record<string, unknown>
  ) =>
    createErrorResponse(
      corsHeaders,
      message,
      ErrorCodes.BAD_REQUEST,
      400,
      details
    ),

  notFound: (corsHeaders: Record<string, string>, resource = "Resource") =>
    createErrorResponse(
      corsHeaders,
      `${resource} not found`,
      ErrorCodes.NOT_FOUND,
      404
    ),

  quotaExceeded: (
    corsHeaders: Record<string, string>,
    type: "ai" | "voice" = "ai"
  ) => {
    const code =
      type === "voice"
        ? ErrorCodes.VOICE_QUOTA_EXCEEDED
        : ErrorCodes.AI_QUOTA_EXCEEDED;
    const message =
      type === "voice"
        ? "Voice quota exceeded. Upgrade to Premium for unlimited voice."
        : "Daily AI quota exceeded. Upgrade to Premium for unlimited access.";
    return createErrorResponse(corsHeaders, message, code, 429);
  },

  rateLimited: (
    corsHeaders: Record<string, string>,
    retryAfter?: number,
    headers?: Record<string, string>
  ) =>
    new Response(
      JSON.stringify({
        error: "Too many requests",
        code: ErrorCodes.RATE_LIMITED,
        retryAfter,
      } as ErrorResponse),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          ...headers,
        },
      }
    ),

  internalError: (corsHeaders: Record<string, string>) =>
    createErrorResponse(
      corsHeaders,
      "An unexpected error occurred",
      ErrorCodes.INTERNAL_ERROR,
      500
    ),

  serviceUnavailable: (corsHeaders: Record<string, string>, service: string) =>
    createErrorResponse(
      corsHeaders,
      `${service} is temporarily unavailable`,
      ErrorCodes.SERVICE_UNAVAILABLE,
      503
    ),
};
