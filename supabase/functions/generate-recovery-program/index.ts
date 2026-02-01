// N006: Wellbeing Debt Calculator - Recovery Program Generator Edge Function
// HTTP POST endpoint: generates personalized 7-day recovery programs
// Triggered when user's debt reaches danger level or manually requested

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import type {
  DebtScore,
  UserProfile,
  RecoveryProgram,
  DailyActions,
  RecoveryAction,
  TransactionCategory,
  CategoryStats,
} from "../_shared/wellbeing-debt-types.ts";
import { getDateNDaysLater } from "../_shared/wellbeing-debt-utils.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: getCorsHeaders(req) });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const { startDate, intensity = "moderate" } = await req.json();
    const programStartDate =
      startDate || new Date().toISOString().split("T")[0];

    // Generate recovery program
    const result = await generateRecoveryProgram(
      supabase,
      user.id,
      programStartDate,
      intensity,
    );

    // Handle case where not enough data exists
    if ("needsMoreData" in result) {
      return new Response(
        JSON.stringify({
          success: false,
          error: result.message,
          needsMoreData: true,
        }),
        {
          status: 200, // Not a server error, just missing data
          headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify({ success: true, program: result }), {
      headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in generate-recovery-program:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: "An unexpected error occurred",
        needsMoreData: false 
      }),
      {
        status: 500,
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      },
    );
  }
});

// =============================================================================
// USER PROFILE MANAGEMENT (matches calculate-debt-score logic)
// =============================================================================

async function getOrCreateUserProfile(
  supabase: any,
  userId: string,
): Promise<UserProfile> {
  const { data: profile, error } = await supabase
    .from("wellbeing_debt_profiles")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (error || !profile) {
    // Create default profile with rebalanced threshold
    const defaultProfile: UserProfile = {
      user_id: userId,
      personal_threshold: -75,
      crash_history: { crashes: [], last_updated: null },
      top_drains: { categories: [], last_updated: null },
      top_deposits: { categories: [], last_updated: null },
    };

    await supabase
      .from("wellbeing_debt_profiles")
      .insert(defaultProfile)
      .single();

    return defaultProfile;
  }

  return profile;
}

// =============================================================================
// RECOVERY PROGRAM GENERATION
// =============================================================================

async function generateRecoveryProgram(
  supabase: any,
  userId: string,
  startDate: string,
  intensity: string,
): Promise<RecoveryProgram | { needsMoreData: true; message: string }> {
  // 1. Get current debt score
  const { data: currentScore, error: scoreError } = await supabase
    .from("wellbeing_debt_scores")
    .select("*")
    .eq("user_id", userId)
    .order("date", { ascending: false })
    .limit(1)
    .single();

  if (scoreError || !currentScore) {
    // No debt data yet - user needs to track for a few days
    return {
      needsMoreData: true,
      message:
        "Not enough wellbeing data yet. Please track your mood and activities for a few days to generate a personalized recovery program.",
    };
  }

  // 2. Get or create user profile
  const profile = await getOrCreateUserProfile(supabase, userId);

  // 3. Get available exercises
  const { data: exercises, error: exercisesError } = await supabase
    .from("exercises")
    .select("id, title, type, duration_minutes, difficulty_level");

  if (exercisesError || !exercises || exercises.length === 0) {
    return {
      needsMoreData: true,
      message: "Exercise library not available. Please try again later.",
    };
  }

  // 4. Calculate target debt reduction
  const currentDebt = currentScore.rolling_debt_14day;
  const targetReduction = Math.max(currentDebt * 0.5, 20); // 50% reduction or min 20 points
  const dailyTarget = Math.ceil(targetReduction / 7);

  // 5. Generate 7-day action plan
  const dailyActions = generateDailyActions(
    startDate,
    profile,
    exercises,
    dailyTarget,
    intensity,
  );

  return {
    user_id: userId,
    generated_at: new Date().toISOString(),
    target_debt_reduction: targetReduction,
    daily_actions: dailyActions,
  };
}

// =============================================================================
// RECOVERY PLAN GENERATION
// =============================================================================

function generateDailyActions(
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
      category: getCategoryForExercise(coreExercise.type),
      action: `Complete: ${coreExercise.title} (${coreExercise.duration_minutes}min)`,
      target_points: 10,
      source: "exercise_sessions",
    });
  }

  // 2. Sleep hygiene action (if sleep is a top drain)
  if (topDrains.some((d) => d.category.includes("sleep"))) {
    actions.push({
      category: "sleep_quality",
      action: "Maintain 7-8 hours sleep with consistent bedtime",
      target_points: 8,
      source: "healthkit",
    });
  }

  // 3. Mood regulation action
  actions.push({
    category: "positive_event",
    action: "Log a positive moment or gratitude entry",
    target_points: 3,
    source: "mood_log",
  });

  // 4. Social connection (if isolation is a drain)
  if (topDrains.some((d) => d.category === "social_isolation")) {
    actions.push({
      category: "social_connection",
      action: "Post daily check-in to your circle",
      target_points: 5,
      source: "circle_posts",
    });
  }

  // 5. Quest completion
  actions.push({
    category: "quest_completion",
    action: "Complete your daily quest",
    target_points: 5,
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
        category: "meditation",
        action: `Optional: ${breathingExercise.title} (${breathingExercise.duration_minutes}min)`,
        target_points: Math.min(5, dailyTarget - currentTotal),
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

function getCategoryForExercise(exerciseType: string): TransactionCategory {
  const mapping: Record<string, TransactionCategory> = {
    breathing: "meditation",
    meditation: "meditation",
    grounding: "meditation",
    journaling: "positive_event",
    movement: "exercise_completion",
  };

  return mapping[exerciseType] || "meditation";
}
