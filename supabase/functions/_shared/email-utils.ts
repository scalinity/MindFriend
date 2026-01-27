// Email utility functions for timezone handling, scheduling, rate limiting, crisis suppression, and retry logic

import { PostgrestError } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Supported timezones (IANA format)
const SUPPORTED_TIMEZONES = [
  "UTC",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Anchorage",
  "Pacific/Honolulu",
  "America/Toronto",
  "America/Mexico_City",
  "America/Argentina/Buenos_Aires",
  "Europe/London",
  "Europe/Paris",
  "Europe/Berlin",
  "Europe/Madrid",
  "Europe/Rome",
  "Europe/Amsterdam",
  "Europe/Brussels",
  "Europe/Vienna",
  "Europe/Prague",
  "Europe/Budapest",
  "Europe/Warsaw",
  "Europe/Moscow",
  "Europe/Istanbul",
  "Asia/Dubai",
  "Asia/Kolkata",
  "Asia/Bangkok",
  "Asia/Hong_Kong",
  "Asia/Shanghai",
  "Asia/Tokyo",
  "Asia/Seoul",
  "Asia/Singapore",
  "Asia/Manila",
  "Australia/Sydney",
  "Australia/Melbourne",
  "Australia/Brisbane",
  "Pacific/Auckland",
];

// RATE LIMIT CONSTANTS
export const EMAIL_RATE_LIMIT_COUNT = 10;
export const EMAIL_RATE_LIMIT_WINDOW_DAYS = 7;
export const CRISIS_SUPPRESSION_PERIOD_DAYS = 14;
export const MAX_EMAIL_RETRIES = 3;

// Validate timezone
function validateTimezone(timezone: string): boolean {
  return SUPPORTED_TIMEZONES.includes(timezone);
}

// Timing-safe string comparison to prevent timing attacks
function timingSafeEqual(a: string | null | undefined, b: string | null | undefined): boolean {
  if (a === null || b === null || a === undefined || b === undefined) {
    return false;
  }
  if (a.length !== b.length) {
    return false;
  }
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// Calculate scheduled send time based on user timezone and preferred hour
function calculateScheduledTime(
  userTimezone: string,
  preferredSendHour: number,
  baseDate: Date = new Date(),
): Date {
  // Format the date as it appears in the user's timezone
  const userFormatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTimezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });

  const [month, day, year] = userFormatter.format(baseDate).split("/");

  // Create a reference date at the TARGET HOUR in UTC
  // Then calculate what time it would be in user's timezone to get offset
  const referenceDate = new Date(
    Date.UTC(parseInt(year), parseInt(month) - 1, parseInt(day), preferredSendHour, 0, 0),
  );

  // Format the same instant in user's timezone to get the offset at this hour
  const userTimeFormatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTimezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  const userTimeStr = userTimeFormatter.format(referenceDate);
  const [userMonth, userDay, userYear, userHour, userMinute, userSecond] =
    userTimeStr.match(/\d+/g)!;

  // Calculate the offset between UTC and user timezone at the TARGET HOUR
  const userInstant = new Date(
    Date.UTC(
      parseInt(userYear),
      parseInt(userMonth) - 1,
      parseInt(userDay),
      parseInt(userHour),
      parseInt(userMinute),
      parseInt(userSecond),
    ),
  );

  const offsetMs = referenceDate.getTime() - userInstant.getTime();
  const offsetMinutes = offsetMs / (1000 * 60);

  // Calculate the target time: user's date at preferredSendHour in their timezone, converted to UTC
  const targetUTC = new Date(
    Date.UTC(
      parseInt(year),
      parseInt(month) - 1,
      parseInt(day),
      preferredSendHour,
      0,
      0,
    ),
  );

  // Adjust for timezone offset calculated at the target hour (DST-aware)
  targetUTC.setMinutes(targetUTC.getMinutes() + offsetMinutes);

  return targetUTC;
}

// Get current week start (Monday)
function getCurrentWeekStart(): Date {
  const now = new Date();
  const dayOfWeek = now.getDay();
  const diff = now.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);
  const weekStart = new Date(now);
  weekStart.setDate(diff);
  weekStart.setHours(0, 0, 0, 0);
  return weekStart;
}

// Get current month year string (e.g., "January 2026")
function getMonthYear(date: Date = new Date()): string {
  return date.toLocaleDateString("en-US", { year: "numeric", month: "long" });
}

// Format date for display (e.g., "Jan 19")
function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

// Check if user should receive emails (not in crisis suppression period)
async function checkCrisisSuppressionPeriod(
  supabase: any,
  userId: string,
): Promise<boolean> {
  try {
    const fourteenDaysAgo = new Date();
    fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);

    const { data, error } = await supabase
      .from("crisis_events")
      .select("id")
      .eq("user_id", userId)
      .gte("created_at", fourteenDaysAgo.toISOString())
      .limit(1);

    if (error) throw error;

    // Return true if NO crisis events found (user can receive emails)
    return data.length === 0;
  } catch (error) {
    console.error("Error checking crisis suppression:", error);
    // Default to allowing emails if there's an error
    return true;
  }
}

// Check rate limiting (10 emails per 7 days)
// INTERNAL ONLY - Use insertEmailLogWithRateLimitCheck for atomic enforcement
async function checkRateLimit(supabase: any, userId: string): Promise<boolean> {
  try {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - EMAIL_RATE_LIMIT_WINDOW_DAYS);

    const { data, error } = await supabase
      .from("email_logs")
      .select("id")
      .eq("user_id", userId)
      .eq("status", "sent")
      .gte("sent_at", sevenDaysAgo.toISOString());

    if (error) throw error;

    // Return true if less than limit emails sent in past window
    return data.length < EMAIL_RATE_LIMIT_COUNT;
  } catch (error) {
    console.error("Error checking rate limit:", error);
    // Default to allowing if there's an error (conservative approach)
    return true;
  }
}

// Atomic rate limit check+log insertion (prevents TOCTOU race)
// Returns true if rate limit was within bounds and log was inserted
async function insertEmailLogWithRateLimitCheck(
  supabase: any,
  userId: string,
  emailLog: Record<string, unknown>,
): Promise<{ success: boolean; withinLimit: boolean; error?: string }> {
  try {
    // Call atomic RPC function - executes rate check and insert within single transaction
    const { data, error } = await supabase.rpc(
      "insert_email_log_with_rate_limit_check",
      {
        p_user_id: userId,
        p_email_log_data: emailLog,
      }
    );

    if (error) throw error;

    return {
      success: data?.success ?? false,
      withinLimit: data?.withinLimit ?? false,
      error: data?.error,
    };
  } catch (error) {
    console.error("Error in insertEmailLogWithRateLimitCheck:", error);
    return {
      success: false,
      withinLimit: false,
      error: String(error),
    };
  }
}

// Check if user has unsubscribed
async function checkUnsubscriptionStatus(
  supabase: any,
  userId: string,
): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from("email_preferences")
      .select("unsubscribed_at")
      .eq("user_id", userId)
      .single();

    if (error) throw error;

    // Return true if NOT unsubscribed (user can receive emails)
    return !data?.unsubscribed_at;
  } catch (error) {
    console.error("Error checking unsubscription status:", error);
    // Default to allowing if there's an error
    return true;
  }
}

// Supported email types for allowlist validation
const VALID_EMAIL_TYPES = [
  "weekly_summary",
  "streak_celebration",
  "achievement_unlock",
  "lapsed_nudge",
  "monthly_report",
];

// Check if specific email type is enabled for user
async function isEmailTypeEnabled(
  supabase: any,
  userId: string,
  emailType: string,
): Promise<boolean> {
  try {
    // Validate emailType against allowlist to prevent SQL injection
    if (!VALID_EMAIL_TYPES.includes(emailType)) {
      console.error(`Invalid email type: ${emailType}`);
      return false;
    }

    const { data, error } = await supabase
      .from("email_preferences")
      .select(emailType)
      .eq("user_id", userId)
      .single();

    if (error) throw error;

    return data?.[emailType] === true;
  } catch (error) {
    console.error(`Error checking if ${emailType} is enabled:`, error);
    // Default to enabling if there's an error
    return true;
  }
}

// Check all conditions before sending email
async function shouldSendEmail(
  supabase: any,
  userId: string,
  emailType: string,
): Promise<{
  shouldSend: boolean;
  reason?: string;
}> {
  try {
    // Check if email is suppressed (bounced/complained)
    const suppressed = await isEmailSuppressed(supabase, userId);
    if (suppressed) {
      return { shouldSend: false, reason: "email on suppression list" };
    }

    // Check if type is enabled
    const typeEnabled = await isEmailTypeEnabled(supabase, userId, emailType);
    if (!typeEnabled) {
      return { shouldSend: false, reason: `${emailType} disabled by user` };
    }

    // Check if unsubscribed
    const notUnsubscribed = await checkUnsubscriptionStatus(supabase, userId);
    if (!notUnsubscribed) {
      return { shouldSend: false, reason: "user unsubscribed" };
    }

    // Check crisis suppression
    const notInCrisis = await checkCrisisSuppressionPeriod(supabase, userId);
    if (!notInCrisis) {
      return { shouldSend: false, reason: "crisis suppression active" };
    }

    // NOTE: Rate limit check is now ONLY done atomically during email_log insertion
    // to prevent TOCTOU race conditions (see insertEmailLogWithRateLimitCheck)

    return { shouldSend: true };
  } catch (error) {
    console.error("Error in shouldSendEmail:", error);
    // Default to not sending if there's an error (safe)
    return { shouldSend: false, reason: `error: ${String(error)}` };
  }
}

// Generate unique message ID (for Resend idempotency)
function generateMessageId(): string {
  // Use crypto.getRandomValues for stronger randomness than Math.random
  const randomBytes = new Uint8Array(12);
  crypto.getRandomValues(randomBytes);
  const randomHex = Array.from(randomBytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `mindfriend-${Date.now()}-${randomHex}`;
}

// Calculate days since date
function daysSinceDate(date: Date): number {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  return Math.floor(diffMs / (1000 * 60 * 60 * 24));
}

// Exponential backoff calculation (2^n minutes, max 3 retries)
function calculateNextRetryTime(retryCount: number): Date {
  const delayMinutes = Math.pow(2, retryCount); // 1, 2, 4 minutes
  const nextRetry = new Date();
  nextRetry.setMinutes(nextRetry.getMinutes() + delayMinutes);
  return nextRetry;
}

// Check if email should be retried
function shouldRetryEmail(retryCount: number, maxRetries: number = 3): boolean {
  return retryCount < maxRetries;
}

// Format error message for logging (truncate if too long)
function formatErrorMessage(error: unknown, maxLength: number = 500): string {
  let message = "";

  if (error instanceof Error) {
    message = error.message;
  } else if (typeof error === "string") {
    message = error;
  } else if (error && typeof error === "object" && "message" in error) {
    message = String((error as any).message);
  } else {
    message = String(error);
  }

  // Sanitize PII from error messages
  message = message.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "[REDACTED-UUID]");
  message = message.replace(/[\w.-]+@[\w.-]+\.\w+/g, "[REDACTED-EMAIL]");
  message = message.replace(/Bearer [^ ]+/g, "[REDACTED-TOKEN]");

  return message.substring(0, maxLength);
}

// Check if email is on suppression list
async function isEmailSuppressed(
  supabase: any,
  userId: string,
): Promise<boolean> {
  try {
    const { data, error } = await supabase
      .from("email_suppression_list")
      .select("id")
      .eq("user_id", userId)
      .is("unsuppressed_at", null)
      .limit(1);

    if (error) throw error;
    return data.length > 0;
  } catch (error) {
    console.error("Error checking email suppression:", error);
    return false;
  }
}

export {
  SUPPORTED_TIMEZONES,
  validateTimezone,
  calculateScheduledTime,
  getCurrentWeekStart,
  getMonthYear,
  formatDate,
  checkCrisisSuppressionPeriod,
  checkRateLimit,
  insertEmailLogWithRateLimitCheck,
  checkUnsubscriptionStatus,
  isEmailTypeEnabled,
  shouldSendEmail,
  generateMessageId,
  daysSinceDate,
  calculateNextRetryTime,
  shouldRetryEmail,
  formatErrorMessage,
  isEmailSuppressed,
  timingSafeEqual,
};
