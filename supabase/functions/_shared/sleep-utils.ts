// Sleep Optimization Utilities

export interface SleepEntry {
  id: string;
  user_id: string;
  date: string;
  bedtime: string;
  wake_time: string;
  time_in_bed_minutes: number;
  time_asleep_minutes: number | null;
  deep_sleep_minutes: number | null;
  rem_sleep_minutes: number | null;
  sleep_score: number | null;
}

export interface SleepGoals {
  id: string;
  user_id: string;
  target_bedtime: string | null;
  target_wake_time: string | null;
  target_duration_minutes: number;
  preferred_wind_down_types: string[];
}

/**
 * Calculate average bedtime from sleep entries (returns HH:MM format)
 */
export function calculateAverageBedtime(entries: SleepEntry[]): string {
  if (entries.length === 0) return "23:00";

  const totalMinutes = entries.reduce((sum, entry) => {
    const bedtime = new Date(entry.bedtime);
    const minutes = bedtime.getHours() * 60 + bedtime.getMinutes();
    return sum + minutes;
  }, 0);

  const avgMinutes = Math.round(totalMinutes / entries.length);
  const hours = Math.floor(avgMinutes / 60);
  const mins = avgMinutes % 60;

  return `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
}

/**
 * Calculate average wake time from sleep entries (returns HH:MM format)
 */
export function calculateAverageWakeTime(entries: SleepEntry[]): string {
  if (entries.length === 0) return "07:00";

  const totalMinutes = entries.reduce((sum, entry) => {
    const wakeTime = new Date(entry.wake_time);
    const minutes = wakeTime.getHours() * 60 + wakeTime.getMinutes();
    return sum + minutes;
  }, 0);

  const avgMinutes = Math.round(totalMinutes / entries.length);
  const hours = Math.floor(avgMinutes / 60);
  const mins = avgMinutes % 60;

  return `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
}

/**
 * Calculate sleep consistency score (0-1) based on bedtime variance
 */
export function calculateConsistency(entries: SleepEntry[]): number {
  if (entries.length < 2) return 1.0;

  const bedtimes = entries.map((entry) => {
    const bedtime = new Date(entry.bedtime);
    return bedtime.getHours() * 60 + bedtime.getMinutes();
  });

  const avg = bedtimes.reduce((a, b) => a + b, 0) / bedtimes.length;
  const variance =
    bedtimes.reduce((sum, time) => sum + Math.pow(time - avg, 2), 0) /
    bedtimes.length;
  const stdDev = Math.sqrt(variance);

  // Consistency score: higher stdDev = lower consistency
  // Perfect consistency (0 variance) = 1.0
  // 60 min stdDev = 0.5
  // 120 min stdDev = 0.0
  const consistency = Math.max(0, 1 - stdDev / 120);

  return Math.round(consistency * 100) / 100;
}

/**
 * Detect weekend sleep shift pattern
 */
export function detectWeekendShift(entries: SleepEntry[]): {
  hasShift: boolean;
  shiftHours: number;
  description: string;
} {
  const weekdayEntries = entries.filter((entry) => {
    const day = new Date(entry.date).getDay();
    return day >= 1 && day <= 5; // Monday-Friday
  });

  const weekendEntries = entries.filter((entry) => {
    const day = new Date(entry.date).getDay();
    return day === 0 || day === 6; // Saturday-Sunday
  });

  if (weekdayEntries.length < 3 || weekendEntries.length < 1) {
    return { hasShift: false, shiftHours: 0, description: "" };
  }

  const weekdayAvg =
    weekdayEntries.reduce((sum, entry) => {
      const bedtime = new Date(entry.bedtime);
      return sum + (bedtime.getHours() * 60 + bedtime.getMinutes());
    }, 0) / weekdayEntries.length;

  const weekendAvg =
    weekendEntries.reduce((sum, entry) => {
      const bedtime = new Date(entry.bedtime);
      return sum + (bedtime.getHours() * 60 + bedtime.getMinutes());
    }, 0) / weekendEntries.length;

  const shiftMinutes = Math.abs(weekendAvg - weekdayAvg);
  const shiftHours = Math.round((shiftMinutes / 60) * 10) / 10; // Round to 1 decimal

  if (shiftMinutes > 60) {
    // More than 1 hour shift
    const direction = weekendAvg > weekdayAvg ? "later" : "earlier";
    return {
      hasShift: true,
      shiftHours,
      description: `You sleep ${shiftHours} hours ${direction} on weekends`,
    };
  }

  return { hasShift: false, shiftHours: 0, description: "" };
}

/**
 * Calculate average sleep duration
 */
export function calculateAverageDuration(entries: SleepEntry[]): number {
  if (entries.length === 0) return 0;

  const totalMinutes = entries.reduce((sum, entry) => {
    return sum + (entry.time_asleep_minutes || entry.time_in_bed_minutes);
  }, 0);

  return Math.round(totalMinutes / entries.length);
}

/**
 * Calculate average sleep score
 */
export function calculateAverageScore(entries: SleepEntry[]): number {
  const scoredEntries = entries.filter((e) => e.sleep_score !== null);

  if (scoredEntries.length === 0) return 0;

  const totalScore = scoredEntries.reduce(
    (sum, entry) => sum + (entry.sleep_score || 0),
    0,
  );

  return Math.round(totalScore / scoredEntries.length);
}

/**
 * Format duration in minutes to "Xh Ym" format
 */
export function formatDuration(minutes: number): string {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;

  if (mins === 0) {
    return `${hours}h`;
  }

  return `${hours}h ${mins}m`;
}
