// Secure Error Handling Utility
// Prevents information disclosure by sanitizing error messages
// All errors logged server-side, generic messages returned to clients

import { createLogger } from "./logger.ts";

const log = createLogger("error-handler");

interface ErrorResponse {
  error: string;
  code?: string;
  statusCode: number;
}

/**
 * Sanitize error information for client response
 * - Logs full error server-side (for debugging)
 * - Returns generic error message to client (prevents reconnaissance)
 *
 * @param error - The error to sanitize
 * @param context - Context about the error (for logging)
 * @param statusCode - HTTP status code (default 500)
 * @returns Safe response for client
 */
export function handleError(
  error: unknown,
  context?: Record<string, unknown>,
  statusCode: number = 500,
): ErrorResponse {
  // Log full error details server-side
  log.error("Request failed", {
    errorType: error instanceof Error ? error.constructor.name : typeof error,
    message: error instanceof Error ? error.message : String(error),
    stack: error instanceof Error ? error.stack : undefined,
    ...context,
  });

  // Generic error message for client (prevents reconnaissance)
  return {
    error: "Request failed",
    statusCode,
  };
}

/**
 * Create JSON response with proper headers and status
 */
export function errorResponse(
  error: unknown,
  context?: Record<string, unknown>,
  statusCode: number = 500,
  corsHeaders?: Record<string, string>,
): Response {
  const { error: message } = handleError(error, context, statusCode);

  return new Response(JSON.stringify({ error: message }), {
    status: statusCode,
    headers: {
      "Content-Type": "application/json",
      ...(corsHeaders || {}),
    },
  });
}

/**
 * Safely extract and sanitize Supabase error details
 * Logs specific error codes internally while returning generic message
 */
export function handleSupabaseError(
  error: {
    code?: string;
    message?: string;
    details?: string;
  } | null,
  context?: Record<string, unknown>,
  corsHeaders?: Record<string, string>,
): Response {
  if (!error) {
    return new Response(JSON.stringify({ error: "Request failed" }), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        ...(corsHeaders || {}),
      },
    });
  }

  // Log specific error code for debugging
  log.error("Supabase error", {
    code: error.code,
    ...context,
  });

  // Return generic error to client
  return new Response(JSON.stringify({ error: "Request failed" }), {
    status: 500,
    headers: {
      "Content-Type": "application/json",
      ...(corsHeaders || {}),
    },
  });
}
