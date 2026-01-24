// N006: Wellbeing Debt Calculator - Shared Utility Functions

/**
 * Calculate linear regression slope for trend analysis
 * @param values Array of debt values over time
 * @returns Slope (points per day)
 */
export function calculateSlope(values: number[]): number {
  const n = values.length;
  if (n < 2) return 0;

  let sumX = 0;
  let sumY = 0;
  let sumXY = 0;
  let sumXX = 0;

  for (let i = 0; i < n; i++) {
    sumX += i;
    sumY += values[i];
    sumXY += i * values[i];
    sumXX += i * i;
  }

  const denominator = n * sumXX - sumX * sumX;
  
  // Prevent division by zero (constant values case)
  if (Math.abs(denominator) < 1e-10) return 0;
  
  const slope = (n * sumXY - sumX * sumY) / denominator;
  return isNaN(slope) || !isFinite(slope) ? 0 : slope;
}

/**
 * Get date string N days before given date
 * @param date ISO date string (YYYY-MM-DD)
 * @param days Number of days to subtract
 * @returns ISO date string
 */
export function getDateNDaysAgo(date: string, days: number): string {
  const d = new Date(date);
  d.setDate(d.getDate() - days);
  return d.toISOString().split("T")[0];
}

/**
 * Get date string N days after given date
 * @param date ISO date string (YYYY-MM-DD)
 * @param days Number of days to add
 * @returns ISO date string
 */
export function getDateNDaysLater(date: string, days: number): string {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d.toISOString().split("T")[0];
}

/**
 * Get today's date in ISO format (YYYY-MM-DD)
 * @returns ISO date string
 */
export function getTodayISO(): string {
  return new Date().toISOString().split("T")[0];
}

/**
 * Get yesterday's date in ISO format (YYYY-MM-DD)
 * @returns ISO date string
 */
export function getYesterdayISO(): string {
  return getDateNDaysAgo(getTodayISO(), 1);
}

/**
 * Calculate sleep quality from HealthKit data
 * Assumption #2 from decisions.md (2026-01-24):
 * - iOS 16+: (deep_sleep + rem_sleep) / total_sleep
 * - iOS <16: total_sleep_hours / 8
 *
 * @param totalSleepSeconds Total sleep duration in seconds
 * @param deepSleepSeconds Deep sleep in seconds (iOS 16+ only)
 * @param remSleepSeconds REM sleep in seconds (iOS 16+ only)
 * @returns Quality score 0-1
 */
export function calculateSleepQuality(
  totalSleepSeconds: number,
  deepSleepSeconds: number | null,
  remSleepSeconds: number | null,
): number {
  // Guard: Return 0 quality if no sleep data
  if (totalSleepSeconds <= 0) return 0;

  if (deepSleepSeconds !== null && remSleepSeconds !== null) {
    // iOS 16+: Use sleep stages
    const qualitySleepSeconds = Math.max(0, deepSleepSeconds + remSleepSeconds);
    
    // Data integrity check: quality sleep cannot exceed total sleep
    if (qualitySleepSeconds > totalSleepSeconds) {
      console.warn(
        `Sleep data integrity issue: quality=${qualitySleepSeconds}s > total=${totalSleepSeconds}s. Clamping.`
      );
      return 1.0;
    }
    
    return Math.min(1.0, qualitySleepSeconds / totalSleepSeconds);
  } else {
    // iOS <16: Duration-based fallback
    const hoursSlept = totalSleepSeconds / 3600;
    return Math.min(1.0, hoursSlept / 8);
  }
}

/**
 * Calculate sleep deposit amount based on quality
 * @param quality Sleep quality (0-1 scale)
 * @returns Deposit points (0-10)
 */
export function calculateSleepDeposit(quality: number): number {
  return Math.round(quality * 10);
}

/**
 * Calculate poor sleep withdrawal based on duration
 * @param hoursSlept Hours of sleep
 * @returns Withdrawal points (0 if ≥6h, 5 if <6h)
 */
export function calculatePoorSleepWithdrawal(hoursSlept: number): number {
  return hoursSlept < 6 ? 5 : 0;
}

/**
 * Calculate 10th percentile of an array (for threshold learning)
 * Uses linear interpolation for accuracy
 * Assumption #3 from decisions.md (2026-01-24)
 *
 * @param values Array of numbers
 * @returns 10th percentile value
 */
export function calculatePercentile10(values: number[]): number {
  if (values.length === 0) return 0;
  
  // Filter out NaN and infinite values
  const validValues = values.filter(v => !isNaN(v) && isFinite(v));
  
  if (validValues.length === 0) return 0;
  if (validValues.length === 1) return validValues[0];

  const sorted = [...validValues].sort((a, b) => a - b);
  const position = (sorted.length - 1) * 0.1;
  const lowerIndex = Math.floor(position);
  const upperIndex = Math.ceil(position);
  
  if (lowerIndex === upperIndex) {
    return sorted[lowerIndex];
  }
  
  const weight = position - lowerIndex;
  return sorted[lowerIndex] * (1 - weight) + sorted[upperIndex] * weight;
}

/**
 * Clamp a value between min and max
 * @param value Value to clamp
 * @param min Minimum value
 * @param max Maximum value
 * @returns Clamped value
 */
export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Format number with 2 decimal places
 * @param value Number to format
 * @returns Formatted string
 */
export function formatDecimal(value: number): string {
  return value.toFixed(2);
}

/**
 * Check if date is within last N days
 * @param date ISO date string to check
 * @param referenceDate Reference ISO date string
 * @param days Number of days
 * @returns True if within last N days
 */
export function isWithinLastNDays(
  date: string,
  referenceDate: string,
  days: number,
): boolean {
  const checkDate = new Date(date);
  const refDate = new Date(referenceDate);
  const nDaysAgo = new Date(referenceDate);
  nDaysAgo.setDate(nDaysAgo.getDate() - days);

  return checkDate >= nDaysAgo && checkDate <= refDate;
}

/**
 * Get list of dates between start and end (inclusive)
 * @param startDate ISO date string
 * @param endDate ISO date string
 * @returns Array of ISO date strings
 */
export function getDateRange(startDate: string, endDate: string): string[] {
  const dates: string[] = [];
  const current = new Date(startDate);
  const end = new Date(endDate);

  // Guard: Return empty array if date range is invalid
  if (current > end) {
    console.warn(`Invalid date range: start=${startDate}, end=${endDate}`);
    return [];
  }

  while (current <= end) {
    dates.push(current.toISOString().split("T")[0]);
    current.setDate(current.getDate() + 1);
  }

  return dates;
}
