// Time-based badge awarding utilities
// Awards night_owl and early_bird badges based on activity time

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;

interface TimeBadgeResult {
  awarded: boolean;
  badge?: {
    slug: string;
    name: string;
    xpReward: number;
  };
}

/**
 * Check and award time-based badges (night_owl, early_bird)
 * Should be called when any activity is completed
 *
 * @param supabase - Supabase client with service role key
 * @param userId - User ID to award badge to
 * @param activityTimestamp - Timestamp of the activity (defaults to now)
 * @returns Result indicating if a badge was awarded
 */
export async function checkTimeBadges(
  supabase: UntypedSupabaseClient,
  userId: string,
  activityTimestamp?: Date,
): Promise<TimeBadgeResult[]> {
  const results: TimeBadgeResult[] = [];
  const timestamp = activityTimestamp || new Date();

  // Get hour in user's local time (approximated using UTC for now)
  // TODO: Consider user's timezone preference from user_settings
  const hour = timestamp.getUTCHours();

  // Night Owl: Activity after midnight (00:00-04:59)
  const isNightOwl = hour >= 0 && hour < 5;

  // Early Bird: Activity before 6am (05:00-05:59)
  const isEarlyBird = hour >= 5 && hour < 6;

  if (isNightOwl) {
    const awarded = await awardBadgeIfNotEarned(supabase, userId, "night_owl");
    if (awarded) {
      results.push({
        awarded: true,
        badge: {
          slug: "night_owl",
          name: "Night Owl",
          xpReward: 100,
        },
      });
    }
  }

  if (isEarlyBird) {
    const awarded = await awardBadgeIfNotEarned(supabase, userId, "early_bird");
    if (awarded) {
      results.push({
        awarded: true,
        badge: {
          slug: "early_bird",
          name: "Early Bird",
          xpReward: 100,
        },
      });
    }
  }

  return results;
}

/**
 * Award a badge to user if they haven't already earned it
 * @returns true if badge was newly awarded, false if already earned or error
 */
async function awardBadgeIfNotEarned(
  supabase: UntypedSupabaseClient,
  userId: string,
  badgeSlug: string,
): Promise<boolean> {
  try {
    // Get badge ID
    const { data: badge, error: badgeError } = await supabase
      .from("badges_v2")
      .select("id, xp_reward")
      .eq("slug", badgeSlug)
      .eq("is_active", true)
      .single();

    if (badgeError || !badge) {
      console.error(`Badge ${badgeSlug} not found:`, badgeError);
      return false;
    }

    // Check if already earned
    const { data: existing } = await supabase
      .from("user_badges_v2")
      .select("is_earned")
      .eq("user_id", userId)
      .eq("badge_id", badge.id)
      .single();

    if (existing?.is_earned) {
      return false; // Already earned
    }

    // Award the badge
    const { error: upsertError } = await supabase.from("user_badges_v2").upsert(
      {
        user_id: userId,
        badge_id: badge.id,
        progress_current: 1,
        progress_target: 1,
        is_earned: true,
        earned_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      {
        onConflict: "user_id,badge_id",
      },
    );

    if (upsertError) {
      console.error(`Failed to award badge ${badgeSlug}:`, upsertError);
      return false;
    }

    // Award XP for the badge
    if (badge.xp_reward > 0) {
      await awardBadgeXP(
        supabase,
        userId,
        badge.id,
        badge.xp_reward,
        badgeSlug,
      );
    }

    console.log(`Awarded ${badgeSlug} badge to user ${userId}`);
    return true;
  } catch (error) {
    console.error(`Error awarding badge ${badgeSlug}:`, error);
    return false;
  }
}

/**
 * Award XP for earning a badge
 */
async function awardBadgeXP(
  supabase: UntypedSupabaseClient,
  userId: string,
  badgeId: string,
  xpAmount: number,
  badgeName: string,
): Promise<void> {
  try {
    // Get current XP
    const { data: exp } = await supabase
      .from("user_experience")
      .select("total_xp")
      .eq("user_id", userId)
      .single();

    const currentXp = exp?.total_xp || 0;
    const newXp = currentXp + xpAmount;
    const newLevel = Math.max(1, Math.floor(Math.sqrt(newXp / 50)) + 1);

    // Update user experience
    await supabase.from("user_experience").upsert(
      {
        user_id: userId,
        total_xp: newXp,
        current_level: newLevel,
        xp_to_next_level: 50 * newLevel * newLevel - newXp,
        updated_at: new Date().toISOString(),
      },
      {
        onConflict: "user_id",
      },
    );

    // Log transaction
    await supabase.from("xp_transactions").insert({
      user_id: userId,
      amount: xpAmount,
      source: "badge",
      source_id: badgeId,
      description: `Earned badge: ${badgeName}`,
      multiplier_applied: 1.0,
      base_amount: xpAmount,
    });
  } catch (error) {
    console.error("Error awarding badge XP:", error);
  }
}
