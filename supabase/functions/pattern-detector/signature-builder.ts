/**
 * Signature Builder
 *
 * Aggregates user_patterns into signature pattern summaries for stress signature visualization.
 * Creates "signature_*" pattern types that represent user-friendly categories and timelines.
 */

export interface UserPattern {
  id: string;
  userId: string;
  patternType: string;
  patternKey: string;
  confidenceScore: number;
  evidenceCount: number;
  firstDetectedAt: string;
  lastDetectedAt: string;
  patternData: any;
  isActive: boolean;
}

export interface SignaturePattern {
  patternType:
    | "signature_stress_trigger"
    | "signature_coping_strategy"
    | "signature_time_pattern";
  patternKey: string;
  confidenceScore: number;
  evidenceCount: number;
  firstDetectedAt: string;
  lastDetectedAt: string;
  patternData: {
    category: string;
    frequency: number;
    timeline: Array<{
      date: string;
      count: number;
    }>;
    topExercises?: string[];
    peakTimes?: string[];
  };
}

/**
 * Build signature patterns from detected user patterns
 *
 * @param userId - User ID for pattern ownership
 * @param allPatterns - All detected patterns for the user
 * @returns Array of signature patterns ready for DB insertion
 */
export async function buildSignaturePatterns(
  userId: string,
  allPatterns: UserPattern[],
): Promise<SignaturePattern[]> {
  // Input validation
  if (!userId || typeof userId !== 'string' || userId.trim() === '') {
    throw new Error('Invalid userId: must be non-empty string');
  }
  if (!Array.isArray(allPatterns)) {
    throw new Error('Invalid allPatterns: must be an array');
  }

  const signaturePatterns: SignaturePattern[] = [];

  // Filter confident patterns only
  const confidentPatterns = allPatterns.filter(
    (p) => p.confidenceScore >= 0.5 && p.isActive,
  );

  // Group stress triggers
  const stressTriggers = confidentPatterns.filter((p) =>
    ["stress_high_mood", "anxiety_spike", "low_energy"].includes(p.patternType),
  );

  for (const trigger of stressTriggers) {
    const timeline = buildTimeline(trigger);
    const frequency = calculateFrequency(trigger);

    signaturePatterns.push({
      patternType: "signature_stress_trigger",
      patternKey: trigger.patternKey,
      confidenceScore: trigger.confidenceScore,
      evidenceCount: trigger.evidenceCount,
      firstDetectedAt: trigger.firstDetectedAt,
      lastDetectedAt: trigger.lastDetectedAt,
      patternData: {
        category: categorizeStressTrigger(trigger.patternKey),
        frequency,
        timeline,
      },
    });
  }

  // Group coping strategies
  const copingStrategies = confidentPatterns.filter((p) =>
    ["exercise_correlation", "mood_improvement"].includes(p.patternType),
  );

  for (const strategy of copingStrategies) {
    const timeline = buildTimeline(strategy);
    const frequency = calculateFrequency(strategy);
    const topExercises = extractTopExercises(strategy);

    signaturePatterns.push({
      patternType: "signature_coping_strategy",
      patternKey: strategy.patternKey,
      confidenceScore: strategy.confidenceScore,
      evidenceCount: strategy.evidenceCount,
      firstDetectedAt: strategy.firstDetectedAt,
      lastDetectedAt: strategy.lastDetectedAt,
      patternData: {
        category: categorizeCopingStrategy(strategy.patternKey),
        frequency,
        timeline,
        topExercises,
      },
    });
  }

  // Group time patterns
  const timePatterns = confidentPatterns.filter((p) =>
    ["day_of_week", "time_of_day"].includes(p.patternType),
  );

  for (const timePattern of timePatterns) {
    const timeline = buildTimeline(timePattern);
    const frequency = calculateFrequency(timePattern);
    const peakTimes = extractPeakTimes(timePattern);

    signaturePatterns.push({
      patternType: "signature_time_pattern",
      patternKey: timePattern.patternKey,
      confidenceScore: timePattern.confidenceScore,
      evidenceCount: timePattern.evidenceCount,
      firstDetectedAt: timePattern.firstDetectedAt,
      lastDetectedAt: timePattern.lastDetectedAt,
      patternData: {
        category: categorizeTimePattern(timePattern.patternKey),
        frequency,
        timeline,
        peakTimes,
      },
    });
  }

  return signaturePatterns;
}

/**
 * Build timeline from pattern start/end dates
 * MVP: Returns simple start/end points
 * Future: Weekly/monthly bucketing
 */
function buildTimeline(
  pattern: UserPattern,
): Array<{ date: string; count: number }> {
  // MVP: Start and end points only
  return [
    { date: pattern.firstDetectedAt, count: 1 },
    { date: pattern.lastDetectedAt, count: pattern.evidenceCount },
  ];
}

/**
 * Minimum weeks active to prevent division by near-zero
 * (prevents frequency spikes from patterns detected in first few days)
 */
const MIN_WEEKS_ACTIVE = 0.1;

/**
 * Calculate pattern frequency in patterns per week
 * Protected against division by zero and invalid dates
 */
function calculateFrequency(pattern: UserPattern): number {
  const firstDate = new Date(pattern.firstDetectedAt);
  const lastDate = new Date(pattern.lastDetectedAt);
  
  // Validate dates
  if (isNaN(firstDate.getTime()) || isNaN(lastDate.getTime())) {
    return 0;
  }
  
  const daysSinceFirst = Math.max(
    1,
    (lastDate.getTime() - firstDate.getTime()) / (1000 * 60 * 60 * 24),
  );
  const weeksActive = Math.max(MIN_WEEKS_ACTIVE, daysSinceFirst / 7);
  return Number((pattern.evidenceCount / weeksActive).toFixed(2));
}

/**
 * Generic categorization function to eliminate code duplication
 * Maps pattern keys to user-friendly category names
 */
function categorizePattern(
  patternKey: string,
  categories: Record<string, string>,
  defaultCategory: string,
  caseSensitive = true,
): string {
  // Check exact match first
  if (categories[patternKey]) {
    return categories[patternKey];
  }

  // Check partial matches
  const searchKey = caseSensitive ? patternKey : patternKey.toLowerCase();
  for (const [key, category] of Object.entries(categories)) {
    const compareKey = caseSensitive ? key : key.toLowerCase();
    if (searchKey.includes(compareKey)) {
      return category;
    }
  }

  return defaultCategory;
}

/**
 * Stress trigger category mappings
 */
const STRESS_TRIGGER_CATEGORIES: Record<string, string> = {
  work_stress: "Work Stress",
  social_anxiety: "Social Situations",
  family_conflict: "Family Relationships",
  health_concern: "Health Concerns",
  financial_worry: "Financial Pressure",
  relationship_stress: "Relationships",
  performance_anxiety: "Performance Pressure",
  uncertainty: "Uncertainty",
  high_anxiety: "High Anxiety",
  low_mood: "Low Mood",
  stress_spike: "Stress Spike",
};

/**
 * Coping strategy category mappings
 */
const COPING_STRATEGY_CATEGORIES: Record<string, string> = {
  breathing_exercises: "Breathing Techniques",
  meditation: "Meditation",
  physical_activity: "Movement",
  journaling: "Reflective Writing",
  social_support: "Connecting with Others",
  exercise_correlation: "Physical Exercise",
  mood_improvement: "Mood-Boosting Activities",
  grounding: "Grounding Techniques",
  mindfulness: "Mindfulness Practices",
};

/**
 * Time pattern category mappings
 */
const TIME_PATTERN_CATEGORIES: Record<string, string> = {
  morning_routine: "Morning Patterns",
  evening_wind_down: "Evening Patterns",
  weekday_stress: "Weekday Patterns",
  weekend_recovery: "Weekend Patterns",
  monday: "Monday Patterns",
  tuesday: "Tuesday Patterns",
  wednesday: "Wednesday Patterns",
  thursday: "Thursday Patterns",
  friday: "Friday Patterns",
  saturday: "Saturday Patterns",
  sunday: "Sunday Patterns",
};

/**
 * Map pattern keys to user-friendly stress trigger categories
 */
function categorizeStressTrigger(patternKey: string): string {
  return categorizePattern(
    patternKey,
    STRESS_TRIGGER_CATEGORIES,
    "Other Stressors",
  );
}

/**
 * Map pattern keys to user-friendly coping strategy categories
 */
function categorizeCopingStrategy(patternKey: string): string {
  return categorizePattern(
    patternKey,
    COPING_STRATEGY_CATEGORIES,
    "Other Strategies",
  );
}

/**
 * Map pattern keys to user-friendly time pattern categories
 */
function categorizeTimePattern(patternKey: string): string {
  return categorizePattern(
    patternKey,
    TIME_PATTERN_CATEGORIES,
    "Other Time Patterns",
    false,  // Case-insensitive matching for time patterns
  );
}

/**
 * Extract top exercises from pattern data
 * Validates array elements are strings
 */
function extractTopExercises(strategy: UserPattern): string[] {
  // Extract from pattern_data.exercises if available
  if (
    strategy.patternData?.exercises &&
    Array.isArray(strategy.patternData.exercises)
  ) {
    return strategy.patternData.exercises
      .filter((e): e is string => typeof e === 'string')
      .slice(0, 3);
  }

  // Extract from pattern_data.topActivities
  if (
    strategy.patternData?.topActivities &&
    Array.isArray(strategy.patternData.topActivities)
  ) {
    return strategy.patternData.topActivities
      .filter((a): a is string => typeof a === 'string')
      .slice(0, 3);
  }

  return [];
}

/**
 * Extract peak times from time pattern data
 * Validates array elements are numbers
 */
function extractPeakTimes(timePattern: UserPattern): string[] {
  // Extract from pattern_data.peakHours if available
  if (
    timePattern.patternData?.peakHours &&
    Array.isArray(timePattern.patternData.peakHours)
  ) {
    return timePattern.patternData.peakHours
      .filter((h): h is number => typeof h === 'number' && !isNaN(h))
      .map((h) => `${h.toString().padStart(2, "0")}:00`);
  }

  // Extract from pattern_data.times
  if (
    timePattern.patternData?.times &&
    Array.isArray(timePattern.patternData.times)
  ) {
    return timePattern.patternData.times
      .filter((t): t is string => typeof t === 'string')
      .slice(0, 3);
  }

  return [];
}
