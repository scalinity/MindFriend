/**
 * Longitudinal Intelligence - Shared Utilities
 * Provides calculation helpers for aggregation Edge Functions
 */

/**
 * Calculate population variance: Σ(x - μ)² / N
 * @param values - Array of numeric values
 * @returns Population variance, or null if insufficient data
 */
export function calculatePopulationVariance(values: number[]): number | null {
  if (values.length < 2) return null;

  const mean = values.reduce((sum, v) => sum + v, 0) / values.length;
  const squaredDiffs = values.map((v) => Math.pow(v - mean, 2));
  const variance = squaredDiffs.reduce((sum, v) => sum + v, 0) / values.length;

  return Math.round(variance * 1000) / 1000; // 3 decimal places
}

/**
 * Calculate mood trend based on delta between current and prior period
 * @param currentAvg - Current period average mood
 * @param priorAvg - Prior period average mood (null for first period)
 * @returns Mood trend enum value
 */
export function calculateMoodTrend(
  currentAvg: number | null,
  priorAvg: number | null,
): "improving" | "declining" | "stable" | "baseline" {
  if (priorAvg === null || currentAvg === null) return "baseline";

  const delta = currentAvg - priorAvg;

  if (delta > 0.5) return "improving";
  if (delta < -0.5) return "declining";
  return "stable";
}

/**
 * Get UTC week bounds (Sunday 00:00:00 to Saturday 23:59:59)
 * @param date - Any date within the target week
 * @returns Start and end timestamps for the week
 */
export function getWeekBounds(date: Date): { start: Date; end: Date } {
  const d = new Date(date);
  d.setUTCHours(0, 0, 0, 0);

  // Get the day of week (0 = Sunday)
  const dayOfWeek = d.getUTCDay();

  // Calculate Sunday of this week
  const start = new Date(d);
  start.setUTCDate(d.getUTCDate() - dayOfWeek);

  // Calculate Saturday end (Sunday + 7 days, minus 1ms)
  const end = new Date(start);
  end.setUTCDate(start.getUTCDate() + 7);

  return { start, end };
}

/**
 * Get UTC month bounds (1st 00:00:00 to last day 23:59:59)
 * @param date - Any date within the target month
 * @returns Start and end timestamps for the month
 */
export function getMonthBounds(date: Date): { start: Date; end: Date } {
  const d = new Date(date);

  // First day of month at midnight UTC
  const start = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1, 0, 0, 0, 0),
  );

  // First day of next month at midnight UTC
  const end = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1, 0, 0, 0, 0),
  );

  return { start, end };
}

/**
 * Get the previous week's Sunday date
 * @param currentWeekStart - Sunday of current week
 * @returns Sunday of previous week
 */
export function getPreviousWeekStart(currentWeekStart: Date): Date {
  const prev = new Date(currentWeekStart);
  prev.setUTCDate(prev.getUTCDate() - 7);
  return prev;
}

/**
 * Get the previous month's first day
 * @param currentMonthStart - First of current month
 * @returns First of previous month
 */
export function getPreviousMonthStart(currentMonthStart: Date): Date {
  const d = new Date(currentMonthStart);
  d.setUTCMonth(d.getUTCMonth() - 1);
  return d;
}

/**
 * Determine season for a given month (Northern Hemisphere)
 * Winter: Dec-Feb, Spring: Mar-May, Summer: Jun-Aug, Fall: Sep-Nov
 * @param month - Month number (0-11)
 * @returns Season name
 */
export function getSeasonForMonth(
  month: number,
): "winter" | "spring" | "summer" | "fall" {
  if (month === 11 || month === 0 || month === 1) return "winter";
  if (month >= 2 && month <= 4) return "spring";
  if (month >= 5 && month <= 7) return "summer";
  return "fall";
}

/**
 * Get quarter for a given month
 * @param month - Month number (0-11)
 * @returns Quarter number (0-3)
 */
export function getQuarterForMonth(month: number): 0 | 1 | 2 | 3 {
  if (month <= 2) return 0; // Q1: Jan-Mar
  if (month <= 5) return 1; // Q2: Apr-Jun
  if (month <= 8) return 2; // Q3: Jul-Sep
  return 3; // Q4: Oct-Dec
}

/**
 * Calculate days in a month
 * @param year - Full year (e.g., 2026)
 * @param month - Month number (0-11)
 * @returns Number of days in the month
 */
export function getDaysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
}

/**
 * Calculate average from an array of numbers, ignoring nulls
 * @param values - Array that may contain nulls
 * @returns Average or null if no valid values
 */
export function calculateAverage(values: (number | null)[]): number | null {
  const valid = values.filter((v): v is number => v !== null);
  if (valid.length === 0) return null;

  const avg = valid.reduce((sum, v) => sum + v, 0) / valid.length;
  return Math.round(avg * 100) / 100; // 2 decimal places
}

/**
 * Count unique days from an array of timestamps
 * @param timestamps - Array of date/timestamps
 * @returns Number of unique days
 */
export function countUniqueDays(timestamps: (Date | string)[]): number {
  const uniqueDays = new Set(
    timestamps.map((t) => {
      const d = typeof t === "string" ? new Date(t) : t;
      return `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
    }),
  );
  return uniqueDays.size;
}

/**
 * Format date as ISO date string (YYYY-MM-DD)
 * @param date - Date to format
 * @returns ISO date string
 */
export function formatISODate(date: Date): string {
  return date.toISOString().split("T")[0];
}

/**
 * Check if a date falls within a range
 * @param date - Date to check
 * @param start - Range start (inclusive)
 * @param end - Range end (exclusive)
 * @returns True if date is within range
 */
export function isDateInRange(date: Date, start: Date, end: Date): boolean {
  return date >= start && date < end;
}

/**
 * Batch process users in chunks
 * @param userIds - Array of user IDs
 * @param batchSize - Size of each batch
 * @param processor - Async function to process each batch
 */
export async function processBatches<T>(
  userIds: string[],
  batchSize: number,
  processor: (batch: string[]) => Promise<T[]>,
): Promise<T[]> {
  const results: T[] = [];

  for (let i = 0; i < userIds.length; i += batchSize) {
    const batch = userIds.slice(i, i + batchSize);
    const batchResults = await processor(batch);
    results.push(...batchResults);
  }

  return results;
}
