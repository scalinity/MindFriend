/**
 * Ritual Validation Utilities
 *
 * Shared validation logic for ritual creation and joining.
 */

import { isValidRitualType, RitualType } from "./ritual-prompts.ts";

/**
 * Sanitize user input to prevent XSS attacks
 * Encodes HTML entities in the input string
 */
export function sanitizeInput(input: string): string {
  if (!input) return "";
  return input
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;")
    .replace(/\//g, "&#x2F;");
}

/**
 * Sanitize and trim user input
 */
export function sanitizeAndTrim(input: string): string {
  return sanitizeInput(input.trim());
}

// Constants
export const GRACE_PERIOD_MS = 2 * 60 * 1000; // 2 minutes
export const MIN_DURATION_SECONDS = 180;
export const MAX_DURATION_SECONDS = 300;
export const MAX_TITLE_LENGTH = 60;
export const MAX_REFLECTION_LENGTH = 140;

export interface CreateRitualInput {
  circleId: string;
  title: string;
  ritualType: string;
  startOption: "now" | "scheduled";
  scheduledFor?: string; // ISO8601 timestamp
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

/**
 * Validate ritual creation input
 */
export function validateCreateRitualInput(
  input: CreateRitualInput,
): ValidationResult {
  const errors: string[] = [];

  // Validate circleId
  if (!input.circleId || !isValidUUID(input.circleId)) {
    errors.push("Invalid circleId");
  }

  // Validate title
  if (!input.title || input.title.trim().length === 0) {
    errors.push("Title is required");
  } else if (input.title.length > MAX_TITLE_LENGTH) {
    errors.push(`Title must be ${MAX_TITLE_LENGTH} characters or less`);
  }

  // Validate ritualType
  if (!input.ritualType || !isValidRitualType(input.ritualType)) {
    errors.push(
      "Invalid ritual type. Must be one of: gratitude, grounding, wins, breathing",
    );
  }

  // Validate startOption
  if (!input.startOption || !["now", "scheduled"].includes(input.startOption)) {
    errors.push("Invalid start option. Must be 'now' or 'scheduled'");
  }

  // Validate scheduledFor if startOption is 'scheduled'
  if (input.startOption === "scheduled") {
    if (!input.scheduledFor) {
      errors.push(
        "Scheduled time is required when start option is 'scheduled'",
      );
    } else {
      const scheduledTime = new Date(input.scheduledFor);
      if (isNaN(scheduledTime.getTime())) {
        errors.push("Invalid scheduled time format");
      } else if (scheduledTime.getTime() <= Date.now()) {
        errors.push("Scheduled time must be in the future");
      }
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Validate reflection content
 */
export function validateReflectionContent(content: string): ValidationResult {
  const errors: string[] = [];

  if (!content || content.trim().length === 0) {
    errors.push("Reflection content is required");
  } else if (content.length > MAX_REFLECTION_LENGTH) {
    errors.push(
      `Reflection must be ${MAX_REFLECTION_LENGTH} characters or less`,
    );
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Check if current time is within grace period for joining a ritual
 *
 * @param scheduledFor - The scheduled start time of the ritual
 * @param currentTime - The current time (optional, defaults to now)
 * @returns true if within grace period (can join), false otherwise
 */
export function isWithinGracePeriod(
  scheduledFor: Date | string,
  currentTime: Date = new Date(),
): boolean {
  const scheduled =
    scheduledFor instanceof Date ? scheduledFor : new Date(scheduledFor);
  const diffMs = currentTime.getTime() - scheduled.getTime();

  // Can join if:
  // - Ritual hasn't started yet (diffMs < 0), OR
  // - Started within grace period (0 <= diffMs <= GRACE_PERIOD_MS)
  return diffMs <= GRACE_PERIOD_MS;
}

/**
 * Check if ritual has started (past scheduled time)
 */
export function hasRitualStarted(
  scheduledFor: Date | string,
  currentTime: Date = new Date(),
): boolean {
  const scheduled =
    scheduledFor instanceof Date ? scheduledFor : new Date(scheduledFor);
  return currentTime.getTime() >= scheduled.getTime();
}

/**
 * Check if ritual time has elapsed (completed)
 */
export function hasRitualElapsed(
  scheduledFor: Date | string,
  durationSeconds: number,
  currentTime: Date = new Date(),
): boolean {
  const scheduled =
    scheduledFor instanceof Date ? scheduledFor : new Date(scheduledFor);
  const endTime = scheduled.getTime() + durationSeconds * 1000;
  return currentTime.getTime() >= endTime;
}

/**
 * Calculate elapsed seconds since ritual started
 */
export function calculateElapsedSeconds(
  scheduledFor: Date | string,
  currentTime: Date = new Date(),
): number {
  const scheduled =
    scheduledFor instanceof Date ? scheduledFor : new Date(scheduledFor);
  const elapsedMs = currentTime.getTime() - scheduled.getTime();
  return Math.max(0, Math.floor(elapsedMs / 1000));
}

/**
 * Validate UUID format
 */
export function isValidUUID(value: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(value);
}

/**
 * Standard error response creator
 */
export interface ErrorResponse {
  error: string;
  code: string;
  details?: string[];
}

export function createErrorResponse(
  code: string,
  message: string,
  details?: string[],
): ErrorResponse {
  return {
    error: message,
    code,
    details,
  };
}

/**
 * HTTP response helpers
 */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

export function errorResponse(
  code: string,
  message: string,
  status: number,
  details?: string[],
): Response {
  return jsonResponse(createErrorResponse(code, message, details), status);
}
