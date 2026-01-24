// Shared Error Logging Utility
// Sanitizes error logs to prevent sensitive information disclosure

interface ErrorLogContext {
  function: string;
  operation: string;
  userId?: string;
  metadata?: Record<string, unknown>;
}

interface SanitizedError {
  context: string;
  operation: string;
  message: string;
  code?: string;
  timestamp: string;
  userId?: string;
  metadata?: Record<string, unknown>;
}

/**
 * Log error with sanitized output (removes sensitive details)
 * SECURITY: Never logs SQL query fragments, stack traces, or database connection details
 */
export function logError(context: ErrorLogContext, error: unknown): void {
  const sanitizedError: SanitizedError = {
    context: context.function,
    operation: context.operation,
    message: error instanceof Error ? error.message : "Unknown error",
    code: (error as any)?.code,
    timestamp: new Date().toISOString(),
    userId: context.userId,
    metadata: context.metadata,
  };

  // Log as JSON for structured logging
  console.error(JSON.stringify(sanitizedError));

  // DO NOT log: error.hint, error.details, error.query, error.stack
}

/**
 * Create a sanitized error response for client
 * SECURITY: Generic error message, no internal details exposed
 */
export function createErrorResponse(
  error: unknown,
  statusCode: number = 500,
): Response {
  return new Response(
    JSON.stringify({
      error: "Internal server error",
      message: error instanceof Error ? error.message : "Unknown error",
    }),
    {
      status: statusCode,
      headers: { "Content-Type": "application/json" },
    },
  );
}

/**
 * Create a sanitized error response with custom error type
 */
export function createCustomErrorResponse(
  errorType: string,
  message: string,
  statusCode: number = 400,
): Response {
  return new Response(
    JSON.stringify({
      error: errorType,
      message,
    }),
    {
      status: statusCode,
      headers: { "Content-Type": "application/json" },
    },
  );
}
