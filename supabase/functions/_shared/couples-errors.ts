// Couples Mode Error Handling
// Standardized error codes and response formatting

// ============================================================================
// ERROR TYPES
// ============================================================================

export enum ErrorCode {
  // 4xx Client Errors
  UNAUTHORIZED = "UNAUTHORIZED",
  BAD_REQUEST = "BAD_REQUEST",
  NOT_FOUND = "NOT_FOUND",
  CONFLICT = "CONFLICT",
  PERMISSION_DENIED = "PERMISSION_DENIED",
  QUOTA_EXCEEDED = "QUOTA_EXCEEDED",
  RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED",
  PAYMENT_REQUIRED = "PAYMENT_REQUIRED",

  // 5xx Server Errors
  INTERNAL_ERROR = "INTERNAL_ERROR",
}

export interface ErrorResponse {
  error: ErrorCode;
  message: string;
  details?: Record<string, any>;
}

// ============================================================================
// ERROR DEFINITIONS (Code → HTTP Status + Message)
// ============================================================================

const ERROR_MAP: Record<
  ErrorCode,
  {
    httpStatus: number;
    defaultMessage: string;
  }
> = {
  [ErrorCode.UNAUTHORIZED]: {
    httpStatus: 401,
    defaultMessage: "Authentication required or token invalid",
  },
  [ErrorCode.BAD_REQUEST]: {
    httpStatus: 400,
    defaultMessage: "Invalid request data",
  },
  [ErrorCode.NOT_FOUND]: {
    httpStatus: 404,
    defaultMessage: "Resource not found",
  },
  [ErrorCode.CONFLICT]: {
    httpStatus: 409,
    defaultMessage: "Request conflicts with existing data",
  },
  [ErrorCode.PERMISSION_DENIED]: {
    httpStatus: 403,
    defaultMessage: "You do not have permission to access this resource",
  },
  [ErrorCode.QUOTA_EXCEEDED]: {
    httpStatus: 429,
    defaultMessage: "Usage quota exceeded",
  },
  [ErrorCode.RATE_LIMIT_EXCEEDED]: {
    httpStatus: 429,
    defaultMessage: "Too many requests, please try again later",
  },
  [ErrorCode.PAYMENT_REQUIRED]: {
    httpStatus: 402,
    defaultMessage: "Premium subscription required",
  },
  [ErrorCode.INTERNAL_ERROR]: {
    httpStatus: 500,
    defaultMessage: "An unexpected error occurred",
  },
};

// ============================================================================
// ERROR RESPONSE FORMATTER
// ============================================================================

/**
 * Format error as JSON response
 * Used by all Edge Functions to return consistent error format
 */
export function formatError(
  code: ErrorCode,
  message?: string,
  details?: Record<string, any>,
): Response {
  const errorDef = ERROR_MAP[code];
  const responseBody: ErrorResponse = {
    error: code,
    message: message || errorDef.defaultMessage,
    ...(details && { details }),
  };

  return new Response(JSON.stringify(responseBody), {
    status: errorDef.httpStatus,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

/**
 * Format success response (convenience function)
 */
export function formatSuccess<T>(data: T, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

// ============================================================================
// SPECIFIC ERROR SCENARIOS (Helper functions for common error cases)
// ============================================================================

export const CouplesErrors = {
  /**
   * UNAUTHORIZED: Missing or invalid authentication
   */
  missingAuth(): Response {
    return formatError(
      ErrorCode.UNAUTHORIZED,
      "Authorization header missing or invalid",
    );
  },

  /**
   * BAD_REQUEST: Invalid JSON body
   */
  invalidJson(): Response {
    return formatError(ErrorCode.BAD_REQUEST, "Invalid JSON in request body");
  },

  /**
   * BAD_REQUEST: Missing required field
   */
  missingField(fieldName: string): Response {
    return formatError(
      ErrorCode.BAD_REQUEST,
      `Missing required field: ${fieldName}`,
      { field: fieldName },
    );
  },

  /**
   * BAD_REQUEST: Invalid field type
   */
  invalidFieldType(fieldName: string, expectedType: string): Response {
    return formatError(
      ErrorCode.BAD_REQUEST,
      `Field ${fieldName} must be ${expectedType}`,
      { field: fieldName, expectedType },
    );
  },

  /**
   * BAD_REQUEST: Invalid field value
   */
  invalidFieldValue(fieldName: string, reason: string): Response {
    return formatError(
      ErrorCode.BAD_REQUEST,
      `Invalid value for ${fieldName}: ${reason}`,
      { field: fieldName, reason },
    );
  },

  /**
   * NOT_FOUND: Partner link not found
   */
  partnerLinkNotFound(): Response {
    return formatError(
      ErrorCode.NOT_FOUND,
      "Partner link not found or invite expired",
    );
  },

  /**
   * NOT_FOUND: Session not found
   */
  sessionNotFound(): Response {
    return formatError(ErrorCode.NOT_FOUND, "Exercise session not found");
  },

  /**
   * NOT_FOUND: Exercise not found
   */
  exerciseNotFound(): Response {
    return formatError(ErrorCode.NOT_FOUND, "Exercise not found");
  },

  /**
   * NOT_FOUND: Appreciation message not found
   */
  appreciationNotFound(): Response {
    return formatError(ErrorCode.NOT_FOUND, "Appreciation message not found");
  },

  /**
   * CONFLICT: User already has active partner
   */
  activePartnershipExists(): Response {
    return formatError(
      ErrorCode.CONFLICT,
      "You already have an active partnership",
    );
  },

  /**
   * CONFLICT: Invite code already used
   */
  inviteAlreadyAccepted(): Response {
    return formatError(
      ErrorCode.CONFLICT,
      "This invite code has already been accepted",
    );
  },

  /**
   * CONFLICT: Invite code expired
   */
  inviteExpired(): Response {
    return formatError(
      ErrorCode.CONFLICT,
      "Invite code has expired (valid for 72 hours)",
    );
  },

  /**
   * PERMISSION_DENIED: User cannot access resource
   */
  accessDenied(): Response {
    return formatError(
      ErrorCode.PERMISSION_DENIED,
      "You do not have access to this resource",
    );
  },

  /**
   * PERMISSION_DENIED: Not in partnership
   */
  notPartner(): Response {
    return formatError(
      ErrorCode.PERMISSION_DENIED,
      "You are not in an active partnership",
    );
  },

  /**
   * PERMISSION_DENIED: Cannot delete invite you didn't create
   */
  cannotDeletePartnerInvite(): Response {
    return formatError(
      ErrorCode.PERMISSION_DENIED,
      "You can only delete invites you created",
    );
  },

  /**
   * PERMISSION_DENIED: Session not started by you
   */
  notSessionCreator(): Response {
    return formatError(
      ErrorCode.PERMISSION_DENIED,
      "Only the session creator can end it",
    );
  },

  /**
   * QUOTA_EXCEEDED: Too many invites sent
   */
  tooManyInvites(): Response {
    return formatError(
      ErrorCode.QUOTA_EXCEEDED,
      "You can send a maximum of 3 invites per 24 hours",
      { limit: 3, window: "24h" },
    );
  },

  /**
   * QUOTA_EXCEEDED: Too many appreciations sent
   */
  tooManyAppreciations(): Response {
    return formatError(
      ErrorCode.QUOTA_EXCEEDED,
      "You can send a maximum of 10 appreciation messages per 24 hours",
      { limit: 10, window: "24h" },
    );
  },

  /**
   * RATE_LIMIT_EXCEEDED: Too many failed attempts
   */
  tooManyFailedAttempts(): Response {
    return formatError(
      ErrorCode.RATE_LIMIT_EXCEEDED,
      "Too many failed attempts. Please try again in a minute.",
      { backoffSeconds: 60 },
    );
  },

  /**
   * PAYMENT_REQUIRED: Premium feature locked
   */
  premiumRequired(): Response {
    return formatError(
      ErrorCode.PAYMENT_REQUIRED,
      "This feature requires a premium subscription",
    );
  },

  /**
   * INTERNAL_ERROR: Database error
   */
  databaseError(error?: Error): Response {
    console.error("Database error:", error);
    return formatError(ErrorCode.INTERNAL_ERROR, "Database error occurred");
  },

  /**
   * INTERNAL_ERROR: Generic unexpected error
   */
  unexpectedError(error?: Error): Response {
    console.error("Unexpected error:", error);
    return formatError(
      ErrorCode.INTERNAL_ERROR,
      "An unexpected error occurred",
    );
  },
};
