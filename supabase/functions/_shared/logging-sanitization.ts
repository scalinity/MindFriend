/**
 * Logging Sanitization Utilities
 *
 * CRITICAL SECURITY POLICY:
 * - NEVER log raw biometric values (heart rate, HRV)
 * - NEVER log calendar event titles (may contain medical/personal PII)
 * - NEVER log full context objects without sanitization
 * - Use sanitizeForLogging() for all TriggerContext logging
 * - Only log error.message, never full error objects with stack traces
 *
 * Compliance: HIPAA §164.308(a)(1)(ii)(D) - Information System Activity Review
 * Compliance: GDPR Article 32(2) - Pseudonymization
 */

interface TriggerContext {
  biometrics?:
    | {
        heartRate?: number;
        hrv?: number;
      }
    | {
        hasElevatedHR?: boolean;
        hrCategory?: string;
        hasLowHRV?: boolean;
        hrvCategory?: string;
      };
  timeOfDay?: string;
  recentMood?: number;
  upcomingEvents?: Array<{
    id: string;
    title?: string;
    classification: string;
    stressScore: number;
    needsArmor: boolean;
    startDate: string;
  }>;
  timingConfidence?: number;
}

/**
 * Sanitize TriggerContext for logging
 * Removes all PHI while preserving debugging information
 */
export function sanitizeForLogging(
  context?: TriggerContext,
): Record<string, unknown> {
  if (!context) return {};

  const sanitized: Record<string, unknown> = {
    timeOfDay: context.timeOfDay ?? null,
    hasMood: context.recentMood !== undefined,
    hasTimingConfidence: context.timingConfidence !== undefined,
  };

  // Biometrics: only log presence and categories, NOT raw values
  if (context.biometrics) {
    // Check if already sanitized (has categories) or raw (has numeric values)
    if ("heartRate" in context.biometrics || "hrv" in context.biometrics) {
      // Raw biometric data - DO NOT LOG VALUES
      sanitized.biometrics = {
        hasHeartRate:
          "heartRate" in context.biometrics &&
          context.biometrics.heartRate !== undefined,
        hasHRV:
          "hrv" in context.biometrics && context.biometrics.hrv !== undefined,
        WARNING:
          "Raw biometric values detected but NOT logged (PHI protection)",
      };
    } else {
      // Already sanitized - safe to log categories
      sanitized.biometrics = {
        hasElevatedHR: context.biometrics.hasElevatedHR ?? null,
        hrCategory: context.biometrics.hrCategory ?? null,
        hasLowHRV: context.biometrics.hasLowHRV ?? null,
        hrvCategory: context.biometrics.hrvCategory ?? null,
      };
    }
  } else {
    sanitized.hasBiometrics = false;
  }

  // Calendar events: log metadata but NEVER titles
  if (context.upcomingEvents) {
    sanitized.upcomingEvents = context.upcomingEvents.map((event) => ({
      id: event.id,
      classification: event.classification,
      stressScore: event.stressScore,
      needsArmor: event.needsArmor,
      startDateISO: event.startDate,
      hasTitle: !!event.title, // Boolean flag only, never the actual title
      // title: NEVER LOG THIS (PII)
    }));
  } else {
    sanitized.hasUpcomingEvents = false;
  }

  return sanitized;
}

/**
 * Sanitize error objects for logging
 * Only logs error message, never stack traces or internal details
 */
export function sanitizeError(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      message: error.message,
      name: error.name,
      // DO NOT include: stack, cause, or any custom properties that may contain PHI
    };
  }

  if (typeof error === "string") {
    return { message: error };
  }

  return { message: "Unknown error" };
}

/**
 * Sanitize user data for logging
 * Only logs non-sensitive identifiers
 */
export function sanitizeUser(user: {
  id?: string;
  email?: string;
}): Record<string, unknown> {
  return {
    userId: user.id ?? "unknown",
    // DO NOT log email or other PII
  };
}

/**
 * Log with automatic sanitization
 * Use this instead of console.log() for any context-aware operations
 */
export function logSanitized(
  level: "info" | "warn" | "error",
  message: string,
  data?: {
    context?: TriggerContext;
    error?: unknown;
    user?: { id?: string; email?: string };
    metadata?: Record<string, unknown>;
  },
) {
  const sanitizedData: Record<string, unknown> = {
    message,
    timestamp: new Date().toISOString(),
  };

  if (data?.context) {
    sanitizedData.context = sanitizeForLogging(data.context);
  }

  if (data?.error) {
    sanitizedData.error = sanitizeError(data.error);
  }

  if (data?.user) {
    sanitizedData.user = sanitizeUser(data.user);
  }

  if (data?.metadata) {
    // Metadata should already be sanitized by caller, but pass through
    sanitizedData.metadata = data.metadata;
  }

  switch (level) {
    case "error":
      console.error(JSON.stringify(sanitizedData));
      break;
    case "warn":
      console.warn(JSON.stringify(sanitizedData));
      break;
    default:
      console.log(JSON.stringify(sanitizedData));
  }
}

/**
 * Examples of CORRECT logging:
 *
 * ✅ GOOD:
 * logSanitized('info', 'Processing intervention trigger', {
 *   context: triggerContext,
 *   user: { id: userId }
 * });
 *
 * ✅ GOOD:
 * console.log('Context summary:', sanitizeForLogging(context));
 *
 * ❌ BAD:
 * console.log('Raw context:', context); // MAY CONTAIN PHI
 *
 * ❌ BAD:
 * console.log(`HR: ${context.biometrics.heartRate}`); // DIRECT PHI EXPOSURE
 *
 * ❌ BAD:
 * console.log('Event:', context.upcomingEvents[0].title); // CALENDAR PII
 */
