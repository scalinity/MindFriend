import type { UserProfile, DailyActions, RecoveryAction, CategoryStats } from "../_shared/wellbeing-debt-types.ts";
import { getDateNDaysLater } from "../_shared/wellbeing-debt-utils.ts";
import { RECOVERY_POINTS } from "../_shared/recovery-points.ts";

export function generateDailyActions(
  startDate: string,
  profile: UserProfile,
  exercises: any[],
  dailyTarget: number,
  intensity: string,
): DailyActions[] {
  const topDrains = profile.top_drains?.categories || [];
  const topDeposits = profile.top_deposits?.categories || [];

  const dailyPlans: DailyActions[] = [];

  // Intensity multiplier
  const intensityMultiplier =
    intensity === "gentle" ? 0.7 : intensity === "aggressive" ? 1.3 : 1.0;
  const adjustedTarget = Math.round(dailyTarget * intensityMultiplier);

  for (let day = 1; day <= 7; day++) {
    const date = getDateNDaysLater(startDate, day - 1);
    const focusArea = getFocusAreaForDay(day, topDrains);
    const actions = generateActionsForDay(
      day,
      focusArea,
      topDrains,
      topDeposits,
      exercises,
      adjustedTarget,
    );

    dailyPlans.push({
      day,
      date,
      focus_area: focusArea,
      actions,
    });
  }

  return dailyPlans;
}

function getFocusAreaForDay(day: number, topDrains: CategoryStats[]): string {
  // Cycle through top drains and general recovery
  const drainCategories = topDrains.map((d) =>
    mapCategoryToFocusArea(d.category),
  );

  const focusAreas = [
    ...drainCategories,
    "sleep_optimization",
    "stress_reduction",
    "social_connection",
  ];

  return focusAreas[(day - 1) % focusAreas.length];
}

function mapCategoryToFocusArea(category: string): string {
  const mapping: Record<string, string> = {
    poor_sleep: "sleep_optimization",
    missed_sleep: "sleep_optimization",
    negative_mood: "emotional_regulation",
    social_isolation: "social_connection",
    work_stress: "stress_reduction",
    conflict: "conflict_resolution",
    health_issue: "physical_wellness",
    circadian_disruption: "circadian_alignment",
  };

  return mapping[category] || "general_wellness";
}

function generateActionsForDay(
  day: number,
  focusArea: string,
  topDrains: CategoryStats[],
  topDeposits: CategoryStats[],
  exercises: any[],
  dailyTarget: number,
): RecoveryAction[] {
  const actions: RecoveryAction[] = [];

  // 1. Core exercise based on focus area (largest point value)
  const coreExercise = selectExerciseForFocusArea(
    focusArea,
    exercises,
    "moderate",
  );
  if (coreExercise) {
    actions.push({
      category: "exercise_completion",
      action: `Complete: ${coreExercise.title} (${coreExercise.duration_minutes}min)`,
      target_points: RECOVERY_POINTS.exercise,
      source: "exercise_sessions",
    });
  }

  // 2. Sleep hygiene action (if sleep is a top drain)
  if (topDrains.some((d) => d.category.includes("sleep"))) {
    actions.push({
      category: "sleep_quality",
      action: "Keep a consistent sleep routine. Points depend on recorded Health sleep measurements.",
      target_points: 0,
      source: "healthkit",
    });
  }

  // 3. Mood regulation action
  actions.push({
    category: "positive_event",
    action: "Log a positive moment or gratitude entry (no automatic debt points)",
    target_points: 0,
    source: "mood_log",
  });

  // 4. Social connection (if isolation is a drain)
  if (topDrains.some((d) => d.category === "social_isolation")) {
    actions.push({
      category: "social_connection",
      action: `Post a daily check-in to your circle (up to ${RECOVERY_POINTS.circleDailyCap} points per day)`,
      target_points: RECOVERY_POINTS.circlePost,
      source: "circle_posts",
    });
  }

  // 5. Quest completion
  actions.push({
    category: "quest_completion",
    action: "Complete your daily quest",
    target_points: RECOVERY_POINTS.quest,
    source: "quests",
  });

  // 6. Supplementary exercise (if target not met)
  const currentTotal = actions.reduce((sum, a) => sum + a.target_points, 0);
  if (currentTotal < dailyTarget) {
    const breathingExercise = selectExerciseForFocusArea(
      "stress_reduction",
      exercises,
      "gentle",
    );
    if (breathingExercise) {
      actions.push({
        category: "exercise_completion",
        action: `Optional: ${breathingExercise.title} (${breathingExercise.duration_minutes}min)`,
        target_points: RECOVERY_POINTS.exercise,
        source: "exercise_sessions",
      });
    }
  }

  return actions;
}

// =============================================================================
// EXERCISE SELECTION
// =============================================================================

function selectExerciseForFocusArea(
  focusArea: string,
  exercises: any[],
  difficulty: string,
): any | null {
  // Map focus areas to exercise types
  const typeMapping: Record<string, string[]> = {
    sleep_optimization: ["breathing", "meditation"],
    stress_reduction: ["breathing", "grounding", "meditation"],
    emotional_regulation: ["journaling", "grounding", "meditation"],
    social_connection: ["movement", "journaling"],
    physical_wellness: ["movement", "breathing"],
    circadian_alignment: ["movement", "meditation"],
    conflict_resolution: ["journaling", "grounding"],
    general_wellness: ["breathing", "meditation", "movement"],
  };

  const preferredTypes = typeMapping[focusArea] || ["meditation"];

  // Filter exercises by type and difficulty
  const candidates = exercises.filter(
    (ex) =>
      preferredTypes.includes(ex.type) &&
      (difficulty === "gentle" ? ex.difficulty_level === "beginner" : true),
  );

  // Return random selection (simple algorithm)
  if (candidates.length === 0) return null;
  return candidates[Math.floor(Math.random() * candidates.length)];
}

