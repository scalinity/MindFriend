// Shared utilities for time capsule Edge Functions
// Eliminates code duplication and centralizes business logic

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

/**
 * User wellness snapshot structure
 */
export interface UserSnapshot {
  current_streak: number;
  total_quests_completed: number;
  total_exercises: number;
  total_moods_logged: number;
  average_mood_30d: number | null;
  badges_earned: number;
  level: number;
  total_xp: number;
  top_emotions: string[] | null;
}

/**
 * Capture current user wellness metrics
 * Uses efficient RPC call to reduce database round-trips
 *
 * @param supabase Supabase client with service role key
 * @param userId User ID to capture snapshot for
 * @returns User wellness snapshot
 */
export async function captureUserSnapshot(
  supabase: SupabaseClient,
  userId: string,
): Promise<UserSnapshot> {
  const { data, error } = await supabase.rpc("capture_user_snapshot", {
    p_user_id: userId,
  });

  if (error) {
    console.error("Failed to capture user snapshot:", error);
    // Return default snapshot on error
    return {
      current_streak: 0,
      total_quests_completed: 0,
      total_exercises: 0,
      total_moods_logged: 0,
      average_mood_30d: null,
      badges_earned: 0,
      level: 1,
      total_xp: 0,
      top_emotions: null,
    };
  }

  return data as UserSnapshot;
}

/**
 * Calculate journey highlights from then vs now snapshots
 *
 * @param thenSnapshot Snapshot at capsule creation
 * @param nowSnapshot Current snapshot
 * @returns Array of highlight strings
 */
export function calculateHighlights(
  thenSnapshot: UserSnapshot | null,
  nowSnapshot: UserSnapshot,
): string[] {
  const highlights: string[] = [];

  if (!thenSnapshot) {
    return highlights;
  }

  // Quest completion highlights
  const questsDiff =
    nowSnapshot.total_quests_completed -
    (thenSnapshot.total_quests_completed || 0);
  if (questsDiff >= 100) {
    highlights.push(`Completed an incredible ${questsDiff} quests!`);
  } else if (questsDiff >= 30) {
    highlights.push(`Completed ${questsDiff} quests`);
  }

  // Streak growth highlights
  const streakGrowth =
    nowSnapshot.current_streak - (thenSnapshot.current_streak || 0);
  if (streakGrowth >= 30) {
    highlights.push(
      `Streak grew from ${thenSnapshot.current_streak || 0} to ${nowSnapshot.current_streak} days`,
    );
  }

  // Level growth highlights
  const levelGrowth = nowSnapshot.level - (thenSnapshot.level || 1);
  if (levelGrowth >= 5) {
    highlights.push(`Leveled up ${levelGrowth} times`);
  }

  // Badge highlights
  const badgesDiff =
    nowSnapshot.badges_earned - (thenSnapshot.badges_earned || 0);
  if (badgesDiff >= 5) {
    highlights.push(`Earned ${badgesDiff} new badges`);
  }

  // Mood trend highlights
  if (thenSnapshot.average_mood_30d && nowSnapshot.average_mood_30d) {
    const moodDiff =
      nowSnapshot.average_mood_30d - thenSnapshot.average_mood_30d;
    if (moodDiff > 0.5) {
      highlights.push(
        `Mood improved from ${thenSnapshot.average_mood_30d.toFixed(1)} to ${nowSnapshot.average_mood_30d.toFixed(1)}`,
      );
    }
  }

  return highlights;
}

/**
 * Format time difference for companion letter
 *
 * @param createdAt Capsule creation date
 * @param now Current date
 * @returns Human-readable time string (e.g., "6 months ago")
 */
export function formatTimeAgo(createdAt: Date, now: Date): string {
  const diffMs = now.getTime() - createdAt.getTime();
  const diffDays = Math.floor(diffMs / (24 * 60 * 60 * 1000));
  const diffMonths = Math.floor(diffDays / 30);
  const diffYears = Math.floor(diffDays / 365);

  if (diffYears > 0) {
    return `${diffYears} year${diffYears > 1 ? "s" : ""} ago`;
  } else if (diffMonths > 0) {
    return `${diffMonths} month${diffMonths > 1 ? "s" : ""} ago`;
  } else {
    return `${diffDays} day${diffDays > 1 ? "s" : ""} ago`;
  }
}

/**
 * Validate user exists and is not deleted
 *
 * @param supabase Supabase client
 * @param userId User ID to validate
 * @returns true if user exists and is active
 */
export async function validateUser(
  supabase: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .single();

  return !error && !!data;
}

/**
 * Default snapshot for fallback cases
 */
export const DEFAULT_SNAPSHOT: UserSnapshot = {
  current_streak: 0,
  total_quests_completed: 0,
  total_exercises: 0,
  total_moods_logged: 0,
  average_mood_30d: null,
  badges_earned: 0,
  level: 1,
  total_xp: 0,
  top_emotions: null,
};
