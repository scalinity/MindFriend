// Pattern Detection Module for Weekly Insights
// Analyzes user data to detect behavioral and mood patterns
// See: specs/06-weekly-insights.md

export interface Pattern {
  type: "time" | "activity" | "streak";
  description: string;
  confidence: number; // 0 to 1
}

export interface MoodData {
  mood_score: number;
  created_at: string;
  day_of_week: number; // 0 = Sunday, 6 = Saturday
  hour_of_day: number;
  source?: string;
}

export interface ExerciseCorrelation {
  exercise_type: string;
  exercise_date: string;
  mood_before: number | null;
  mood_after: number | null;
}

interface DayStats {
  count: number;
  sum: number;
  avg: number;
}

const DAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];
const SHORT_DAY_NAMES = ["Sun", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// Minimum confidence threshold to include pattern
const MIN_CONFIDENCE = 0.6;

// Minimum data points for meaningful analysis
const MIN_MOODS_FOR_PATTERNS = 5;
const MIN_EXERCISES_FOR_CORRELATION = 3;

/**
 * Detect patterns from user's mood and activity data
 */
export function detectPatterns(
  moods: MoodData[],
  exerciseCorrelations: ExerciseCorrelation[],
  streakDays: number,
  avgMood: number | null,
): Pattern[] {
  const patterns: Pattern[] = [];

  // Only analyze if we have enough data
  if (moods.length >= MIN_MOODS_FOR_PATTERNS) {
    // Time-based patterns
    const timePatterns = detectTimePatterns(moods);
    patterns.push(...timePatterns);

    // Weekend vs weekday patterns
    const weekendPattern = detectWeekendPattern(moods);
    if (weekendPattern) patterns.push(weekendPattern);
  }

  // Activity correlation patterns
  if (exerciseCorrelations.length >= MIN_EXERCISES_FOR_CORRELATION) {
    const activityPatterns = detectActivityCorrelations(exerciseCorrelations);
    patterns.push(...activityPatterns);
  }

  // Streak impact pattern
  if (streakDays >= 3 && avgMood !== null && avgMood >= 3.5) {
    patterns.push({
      type: "streak",
      description: `Your ${streakDays}-day streak correlates with higher mood`,
      confidence: Math.min(0.9, 0.6 + streakDays / 20),
    });
  }

  // Filter by minimum confidence
  return patterns.filter((p) => p.confidence >= MIN_CONFIDENCE);
}

/**
 * Detect time-based mood patterns (best/worst days)
 */
function detectTimePatterns(moods: MoodData[]): Pattern[] {
  const patterns: Pattern[] = [];

  // Group moods by day of week
  const dayStats: Record<number, DayStats> = {};
  for (let i = 0; i < 7; i++) {
    dayStats[i] = { count: 0, sum: 0, avg: 0 };
  }

  for (const mood of moods) {
    const day = mood.day_of_week;
    dayStats[day].count++;
    dayStats[day].sum += mood.mood_score;
  }

  // Calculate averages
  for (let i = 0; i < 7; i++) {
    if (dayStats[i].count > 0) {
      dayStats[i].avg = dayStats[i].sum / dayStats[i].count;
    }
  }

  // Find days with at least 2 data points
  const validDays = Object.entries(dayStats)
    .filter(([_, stats]) => stats.count >= 2)
    .map(([day, stats]) => ({ day: parseInt(day), ...stats }));

  if (validDays.length < 2) return patterns;

  // Sort by average
  const sorted = [...validDays].sort((a, b) => b.avg - a.avg);
  const highest = sorted[0];
  const lowest = sorted[sorted.length - 1];

  // Check if there's a significant difference
  const diff = highest.avg - lowest.avg;
  if (diff >= 0.8) {
    const confidence = Math.min(0.9, 0.5 + diff / 3);
    patterns.push({
      type: "time",
      description: `Your mood tends to be higher on ${DAY_NAMES[highest.day]}s and lower on ${DAY_NAMES[lowest.day]}s`,
      confidence,
    });
  }

  return patterns;
}

/**
 * Detect weekend vs weekday mood difference
 */
function detectWeekendPattern(moods: MoodData[]): Pattern | null {
  const weekdayMoods: number[] = [];
  const weekendMoods: number[] = [];

  for (const mood of moods) {
    if (mood.day_of_week === 0 || mood.day_of_week === 6) {
      weekendMoods.push(mood.mood_score);
    } else {
      weekdayMoods.push(mood.mood_score);
    }
  }

  // Need at least 2 data points in each category
  if (weekdayMoods.length < 2 || weekendMoods.length < 2) return null;

  const weekdayAvg =
    weekdayMoods.reduce((a, b) => a + b, 0) / weekdayMoods.length;
  const weekendAvg =
    weekendMoods.reduce((a, b) => a + b, 0) / weekendMoods.length;

  const diff = Math.abs(weekendAvg - weekdayAvg);

  if (diff >= 0.7) {
    const higher = weekendAvg > weekdayAvg ? "weekends" : "weekdays";
    const confidence = Math.min(0.85, 0.5 + diff / 3);
    return {
      type: "time",
      description: `Your mood is generally higher on ${higher}`,
      confidence,
    };
  }

  return null;
}

/**
 * Detect exercise-mood correlations
 */
function detectActivityCorrelations(
  correlations: ExerciseCorrelation[],
): Pattern[] {
  const patterns: Pattern[] = [];

  // Filter to correlations with both before and after mood
  const validCorrelations = correlations.filter(
    (c) => c.mood_before !== null && c.mood_after !== null,
  );

  if (validCorrelations.length < MIN_EXERCISES_FOR_CORRELATION) return patterns;

  // Calculate average mood improvement after exercise
  let totalImprovement = 0;
  let improvementCount = 0;

  for (const c of validCorrelations) {
    const improvement = c.mood_after! - c.mood_before!;
    totalImprovement += improvement;
    improvementCount++;
  }

  const avgImprovement = totalImprovement / improvementCount;

  if (avgImprovement >= 0.5) {
    const confidence = Math.min(0.85, 0.5 + avgImprovement / 3);
    patterns.push({
      type: "activity",
      description: "Your mood tends to improve after exercises",
      confidence,
    });
  }

  // Check by exercise type
  const typeStats: Record<string, { count: number; improvement: number }> = {};

  for (const c of validCorrelations) {
    if (!typeStats[c.exercise_type]) {
      typeStats[c.exercise_type] = { count: 0, improvement: 0 };
    }
    typeStats[c.exercise_type].count++;
    typeStats[c.exercise_type].improvement += c.mood_after! - c.mood_before!;
  }

  // Find most effective exercise type
  const typeEntries = Object.entries(typeStats)
    .filter(([_, stats]) => stats.count >= 2)
    .map(([type, stats]) => ({
      type,
      avgImprovement: stats.improvement / stats.count,
      count: stats.count,
    }));

  if (typeEntries.length > 0) {
    const best = typeEntries.sort(
      (a, b) => b.avgImprovement - a.avgImprovement,
    )[0];
    if (best.avgImprovement >= 0.6) {
      const typeName = best.type.charAt(0).toUpperCase() + best.type.slice(1);
      patterns.push({
        type: "activity",
        description: `${typeName} exercises seem most effective for your mood`,
        confidence: Math.min(0.8, 0.5 + best.avgImprovement / 3),
      });
    }
  }

  return patterns;
}
