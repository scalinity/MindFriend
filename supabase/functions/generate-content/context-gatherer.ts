// Context Gatherer Module
// Purpose: Fetch user context for personalized exercise generation
// Author: dev-pipeline
// Date: 2026-01-24

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface GenerationContext {
  mood: {
    level: number; // 1-10
    label: string; // "anxious", "calm", "stressed", etc.
    timestamp: string;
  } | null;
  recentExercises: {
    title: string;
    type: string;
    completedAt: string;
    rating?: number;
  }[];
  timeOfDay: "morning" | "afternoon" | "evening" | "night";
  preferences: {
    imagery: string[];
    guidanceLevel: "minimal" | "moderate" | "detailed";
    avoidThemes: string[];
    voicePreference: string;
  };
}

/**
 * Gather comprehensive user context for personalized exercise generation
 *
 * @param supabase - Supabase client with service role key
 * @param userId - User ID to gather context for
 * @param exerciseType - Type of exercise being generated
 * @returns GenerationContext with mood, history, preferences
 */
export async function gatherGenerationContext(
  supabase: SupabaseClient,
  userId: string,
  exerciseType: string,
): Promise<GenerationContext> {
  // Determine time of day
  const now = new Date();
  const hour = now.getHours();
  const timeOfDay =
    hour < 12
      ? "morning"
      : hour < 17
        ? "afternoon"
        : hour < 21
          ? "evening"
          : "night";

  try {
    // Fetch all context data in parallel
    const [moodData, exercisesData, preferencesData] = await Promise.all([
      fetchRecentMood(supabase, userId),
      fetchRecentExercises(supabase, userId, exerciseType),
      fetchUserPreferences(supabase, userId),
    ]);

    return {
      mood: moodData,
      recentExercises: exercisesData,
      timeOfDay,
      preferences: preferencesData,
    };
  } catch (error) {
    console.error("Context gathering error:", error);

    // Return minimal context on error - don't fail generation
    return {
      mood: null,
      recentExercises: [],
      timeOfDay,
      preferences: getDefaultPreferences(),
    };
  }
}

/**
 * Fetch user's most recent mood (last 24 hours)
 */
async function fetchRecentMood(
  supabase: SupabaseClient,
  userId: string,
): Promise<GenerationContext["mood"]> {
  const twentyFourHoursAgo = new Date(
    Date.now() - 24 * 60 * 60 * 1000,
  ).toISOString();

  const { data, error } = await supabase
    .from("moods")
    .select("mood_category, energy_level, created_at")
    .eq("user_id", userId)
    .gte("created_at", twentyFourHoursAgo)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  if (error || !data) {
    return null;
  }

  return {
    level: data.energy_level || 5,
    label: data.mood_category || "neutral",
    timestamp: data.created_at,
  };
}

/**
 * Fetch user's recent exercises (last 7 days) to avoid repetition
 */
async function fetchRecentExercises(
  supabase: SupabaseClient,
  userId: string,
  currentExerciseType: string,
): Promise<GenerationContext["recentExercises"]> {
  const sevenDaysAgo = new Date(
    Date.now() - 7 * 24 * 60 * 60 * 1000,
  ).toISOString();

  const { data, error } = await supabase
    .from("generated_content")
    .select("title, content_type, created_at, user_rating")
    .eq("user_id", userId)
    .eq("content_type", currentExerciseType) // Only same type for relevance
    .gte("created_at", sevenDaysAgo)
    .order("created_at", { ascending: false })
    .limit(10);

  if (error || !data) {
    return [];
  }

  return data.map((exercise) => ({
    title: exercise.title,
    type: exercise.content_type,
    completedAt: exercise.created_at,
    rating: exercise.user_rating || undefined,
  }));
}

/**
 * Fetch user's exercise generation preferences
 */
async function fetchUserPreferences(
  supabase: SupabaseClient,
  userId: string,
): Promise<GenerationContext["preferences"]> {
  const { data, error } = await supabase
    .from("exercise_generation_preferences")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (error || !data) {
    return getDefaultPreferences();
  }

  return {
    imagery: data.preferred_imagery || ["nature", "water"],
    guidanceLevel: data.guidance_level || "moderate",
    avoidThemes: data.avoid_themes || [],
    voicePreference: data.voice_preference || "warm",
  };
}

/**
 * Get default preferences for users who haven't set them yet
 */
function getDefaultPreferences(): GenerationContext["preferences"] {
  return {
    imagery: ["nature", "water"],
    guidanceLevel: "moderate",
    avoidThemes: [],
    voicePreference: "warm",
  };
}

/**
 * Infer energy level from mood if not explicitly provided
 */
export function inferEnergyLevel(moodLabel: string): number {
  const energyMap: Record<string, number> = {
    // High energy moods
    anxious: 7,
    angry: 8,
    excited: 9,
    // Medium energy moods
    neutral: 5,
    content: 5,
    // Low energy moods
    sad: 3,
    tired: 2,
    depressed: 2,
    calm: 4,
  };

  return energyMap[moodLabel.toLowerCase()] || 5;
}
