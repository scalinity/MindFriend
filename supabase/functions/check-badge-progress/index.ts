// MindFriend Check Badge Progress Edge Function
// Checks user progress against badge requirements and awards earned badges

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface Badge {
  id: string;
  slug: string;
  name: string;
  description: string;
  icon_url: string;
  category: string;
  tier: string | null;
  requirement_type: string;
  requirement_config: RequirementConfig;
  rarity: string;
  xp_reward: number;
  is_secret: boolean;
}

interface RequirementConfig {
  metric?: string;
  target?: number;
  streak_type?: string;
  trigger?: string;
  filter?: Record<string, unknown>;
}

interface UserBadge {
  id: string;
  badge_id: string;
  progress_current: number;
  progress_target: number | null;
  is_earned: boolean;
  earned_at: string | null;
}

interface CheckResult {
  badgeId: string;
  badgeSlug: string;
  badgeName: string;
  progressCurrent: number;
  progressTarget: number | null;
  isEarned: boolean;
  isNewlyEarned: boolean;
  xpAwarded: number;
}

interface UserMetrics {
  questsCompleted: number;
  moodsLogged: number;
  exercisesCompleted: number;
  meditationsCompleted: number;
  meditationTimeSeconds: number;
  circlesJoined: number;
  circlePosts: number;
  currentQuestStreak: number;
  currentLevel: number;
  breathingExercises: number;
  groundingExercises: number;
  // Manual badge triggers
  circlesCreated: number;
  profileComplete: boolean;
  daysSinceLastActivity: number;
  userCreatedAt: Date | null;
  userTimezone: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch user's current metrics
    const metrics = await fetchUserMetrics(supabase, user.id);

    // Fetch all active badges (including manual badges for trigger checking)
    const { data: badges, error: badgesError } = await supabase
      .from("badges_v2")
      .select("*")
      .eq("is_active", true)
      .in("requirement_type", ["count", "streak", "time", "manual"]);

    if (badgesError) {
      console.error("Error fetching badges:", badgesError);
      return new Response(JSON.stringify({ error: "Failed to fetch badges" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch user's existing badge progress
    const { data: userBadges } = await supabase
      .from("user_badges_v2")
      .select("*")
      .eq("user_id", user.id);

    const userBadgeMap = new Map<string, UserBadge>();
    userBadges?.forEach((ub: UserBadge) => {
      userBadgeMap.set(ub.badge_id, ub);
    });

    // Check each badge
    const results: CheckResult[] = [];
    const newlyEarnedBadges: Badge[] = [];

    for (const badge of badges || []) {
      const existingProgress = userBadgeMap.get(badge.id);

      // Skip already earned badges
      if (existingProgress?.is_earned) {
        continue;
      }

      // Calculate current progress
      const { progress, target } = calculateProgress(badge, metrics);

      // Check if badge is now earned
      const isEarned = target !== null && progress >= target;
      const isNewlyEarned = isEarned && !existingProgress?.is_earned;

      // Upsert user badge progress
      const { error: upsertError } = await supabase
        .from("user_badges_v2")
        .upsert(
          {
            user_id: user.id,
            badge_id: badge.id,
            progress_current: progress,
            progress_target: target,
            is_earned: isEarned,
            earned_at: isNewlyEarned
              ? new Date().toISOString()
              : existingProgress?.earned_at || null,
            updated_at: new Date().toISOString(),
          },
          {
            onConflict: "user_id,badge_id",
          },
        );

      if (upsertError) {
        console.error("Error upserting badge progress:", upsertError);
        continue;
      }

      // Track newly earned badges
      if (isNewlyEarned) {
        newlyEarnedBadges.push(badge);
      }

      results.push({
        badgeId: badge.id,
        badgeSlug: badge.slug,
        badgeName: badge.name,
        progressCurrent: progress,
        progressTarget: target,
        isEarned,
        isNewlyEarned,
        xpAwarded: isNewlyEarned ? badge.xp_reward : 0,
      });
    }

    // Award XP for newly earned badges
    let totalXpAwarded = 0;
    for (const badge of newlyEarnedBadges) {
      if (badge.xp_reward > 0) {
        // Use the award-xp function logic inline for efficiency
        const { data: exp } = await supabase
          .from("user_experience")
          .select("total_xp")
          .eq("user_id", user.id)
          .single();

        const currentXp = exp?.total_xp || 0;
        const newXp = currentXp + badge.xp_reward;

        await supabase.from("user_experience").upsert(
          {
            user_id: user.id,
            total_xp: newXp,
            current_level: calculateLevel(newXp),
            xp_to_next_level:
              totalXpForLevel(calculateLevel(newXp) + 1) - newXp,
            updated_at: new Date().toISOString(),
          },
          {
            onConflict: "user_id",
          },
        );

        await supabase.from("xp_transactions").insert({
          user_id: user.id,
          amount: badge.xp_reward,
          source: "badge",
          source_id: badge.id,
          description: `Earned badge: ${badge.name}`,
          multiplier_applied: 1.0,
          base_amount: badge.xp_reward,
        });

        totalXpAwarded += badge.xp_reward;
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        badgesChecked: results.length,
        newlyEarned: newlyEarnedBadges.map((b) => ({
          id: b.id,
          slug: b.slug,
          name: b.name,
          description: b.description,
          iconUrl: b.icon_url,
          rarity: b.rarity,
          xpReward: b.xp_reward,
        })),
        totalXpAwarded,
        progress: results,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error checking badge progress:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...getCorsHeaders(null), "Content-Type": "application/json" },
    });
  }
});

// Fetch all user metrics needed for badge calculations
// deno-lint-ignore no-explicit-any
async function fetchUserMetrics(
  supabase: any,
  userId: string,
): Promise<UserMetrics> {
  // Parallel fetch for efficiency
  const [
    questsResult,
    moodsResult,
    exercisesResult,
    circlesResult,
    circlePostsResult,
    streakResult,
    levelResult,
    playbackResult,
    // Manual badge metrics
    circlesCreatedResult,
    profileResult,
    lastActivityResult,
  ] = await Promise.all([
    // Quests completed
    supabase
      .from("quests")
      .select("id", { count: "exact" })
      .eq("user_id", userId)
      .eq("status", "completed"),

    // Moods logged
    supabase
      .from("moods")
      .select("id", { count: "exact" })
      .eq("user_id", userId),

    // Exercise sessions with types
    supabase
      .from("exercise_sessions")
      .select("id, exercise:exercises(type)")
      .eq("user_id", userId)
      .eq("completed", true),

    // Circles joined
    supabase
      .from("circle_members")
      .select("id", { count: "exact" })
      .eq("user_id", userId),

    // Circle posts
    supabase
      .from("circle_posts")
      .select("id", { count: "exact" })
      .eq("user_id", userId),

    // Quest streak
    supabase
      .from("user_streaks_v2")
      .select("current_count")
      .eq("user_id", userId)
      .eq("streak_type", "quest")
      .single(),

    // User level
    supabase
      .from("user_experience")
      .select("current_level")
      .eq("user_id", userId)
      .single(),

    // Playback sessions (meditations)
    supabase
      .from("playback_sessions")
      .select("id, duration_played_seconds, track:audio_tracks(category)")
      .eq("user_id", userId)
      .eq("completed", true),

    // Circles created (for circle_creator badge)
    supabase
      .from("circles")
      .select("id", { count: "exact" })
      .eq("created_by", userId),

    // Profile data (for profile_complete badge and timezone)
    supabase
      .from("profiles")
      .select("display_name, avatar_url, created_at, timezone")
      .eq("id", userId)
      .single(),

    // Last activity date (for comeback_kid badge)
    supabase
      .from("quests")
      .select("completed_at")
      .eq("user_id", userId)
      .eq("status", "completed")
      .order("completed_at", { ascending: false })
      .limit(1)
      .single(),
  ]);

  // Calculate exercise counts by type
  // deno-lint-ignore no-explicit-any
  const exercises = (exercisesResult.data || []) as any[];
  let breathingExercises = 0;
  let groundingExercises = 0;
  const totalExercises = exercises.length;

  for (const session of exercises) {
    const exerciseData = session.exercise as { type?: string } | null;
    if (exerciseData?.type === "breathing") breathingExercises++;
    if (exerciseData?.type === "grounding") groundingExercises++;
  }

  // Calculate meditation stats
  // deno-lint-ignore no-explicit-any
  const playbacks = (playbackResult.data || []) as any[];
  let meditationsCompleted = 0;
  let meditationTimeSeconds = 0;

  for (const session of playbacks) {
    const trackData = session.track as { category?: string } | null;
    if (trackData?.category === "meditation") {
      meditationsCompleted++;
      meditationTimeSeconds += session.duration_played_seconds || 0;
    }
  }

  // deno-lint-ignore no-explicit-any
  const streakData = streakResult.data as any;
  // deno-lint-ignore no-explicit-any
  const levelData = levelResult.data as any;
  // deno-lint-ignore no-explicit-any
  const profileData = profileResult.data as any;
  // deno-lint-ignore no-explicit-any
  const lastActivityData = lastActivityResult.data as any;

  // Calculate profile completeness (has display_name and avatar_url)
  const profileComplete = Boolean(
    profileData?.display_name && profileData?.avatar_url,
  );

  // Calculate days since last activity
  let daysSinceLastActivity = 0;
  if (lastActivityData?.completed_at) {
    const lastActivity = new Date(lastActivityData.completed_at);
    const now = new Date();
    daysSinceLastActivity = Math.floor(
      (now.getTime() - lastActivity.getTime()) / (1000 * 60 * 60 * 24),
    );
  }

  // User created_at for founding_member badge
  const userCreatedAt = profileData?.created_at
    ? new Date(profileData.created_at)
    : null;

  return {
    questsCompleted: questsResult.count || 0,
    moodsLogged: moodsResult.count || 0,
    exercisesCompleted: totalExercises,
    meditationsCompleted,
    meditationTimeSeconds,
    circlesJoined: circlesResult.count || 0,
    circlePosts: circlePostsResult.count || 0,
    currentQuestStreak: streakData?.current_count || 0,
    currentLevel: levelData?.current_level || 1,
    breathingExercises,
    groundingExercises,
    // Manual badge metrics
    circlesCreated: circlesCreatedResult.count || 0,
    profileComplete,
    daysSinceLastActivity,
    userCreatedAt,
    userTimezone: profileData?.timezone || "UTC",
  };
}

// Calculate progress for a badge based on its requirements
function calculateProgress(
  badge: Badge,
  metrics: UserMetrics,
): { progress: number; target: number | null } {
  const config = badge.requirement_config;

  if (badge.requirement_type === "count") {
    const target = config.target || 0;
    let progress = 0;

    switch (config.metric) {
      case "quests_completed":
        progress = metrics.questsCompleted;
        break;
      case "moods_logged":
        progress = metrics.moodsLogged;
        break;
      case "exercises_completed":
        // Check for type filter
        if (config.filter && typeof config.filter === "object") {
          const filterType = (config.filter as Record<string, unknown>).type;
          if (filterType === "breathing") {
            progress = metrics.breathingExercises;
          } else if (filterType === "grounding") {
            progress = metrics.groundingExercises;
          } else {
            progress = metrics.exercisesCompleted;
          }
        } else {
          progress = metrics.exercisesCompleted;
        }
        break;
      case "meditations_completed":
        progress = metrics.meditationsCompleted;
        break;
      case "circles_joined":
        progress = metrics.circlesJoined;
        break;
      case "circle_posts":
        progress = metrics.circlePosts;
        break;
      case "user_level":
        progress = metrics.currentLevel;
        break;
      default:
        progress = 0;
    }

    return { progress, target };
  }

  if (badge.requirement_type === "streak") {
    const target = config.target || 0;
    let progress = 0;

    // Currently only supporting quest streaks
    if (config.streak_type === "quest") {
      progress = metrics.currentQuestStreak;
    }

    return { progress, target };
  }

  if (badge.requirement_type === "time") {
    const target = config.target || 0;
    let progress = 0;

    if (config.metric === "meditation_time") {
      progress = metrics.meditationTimeSeconds;
    }

    return { progress, target };
  }

  // Manual badges - check specific triggers
  if (badge.requirement_type === "manual") {
    const trigger = config.trigger;

    switch (trigger) {
      case "profile_complete":
        // Profile is complete when user has display_name and avatar_url
        return {
          progress: metrics.profileComplete ? 1 : 0,
          target: 1,
        };

      case "circle_created":
        // User has created at least one circle
        return {
          progress: metrics.circlesCreated,
          target: 1,
        };

      case "returned_after_7_days":
        // User returned after being away for 7+ days
        // This is tracked separately - only award if daysSinceLastActivity was >= 7
        // and they're now active again (which is why they're calling this endpoint)
        return {
          progress: metrics.daysSinceLastActivity >= 7 ? 1 : 0,
          target: 1,
        };

      case "founding_member":
        // User joined during beta period (Jan 27 - Mar 15, 2026)
        if (metrics.userCreatedAt) {
          const launchStart = new Date("2026-01-27T00:00:00Z");
          const launchEnd = new Date("2026-03-16T00:00:00Z");
          const isFoundingMember =
            metrics.userCreatedAt >= launchStart &&
            metrics.userCreatedAt < launchEnd;
          return {
            progress: isFoundingMember ? 1 : 0,
            target: 1,
          };
        }
        return { progress: 0, target: 1 };

      case "activity_after_midnight": {
        // Night Owl: Check if current activity is between midnight and 5am LOCAL time
        const localHour = getLocalHour(metrics.userTimezone);
        const isNightOwl = localHour >= 0 && localHour < 5;
        return {
          progress: isNightOwl ? 1 : 0,
          target: 1,
        };
      }

      case "activity_before_6am": {
        // Early Bird: Check if current activity is between 5am and 6am LOCAL time
        const localHour = getLocalHour(metrics.userTimezone);
        const isEarlyBird = localHour >= 5 && localHour < 6;
        return {
          progress: isEarlyBird ? 1 : 0,
          target: 1,
        };
      }

      case "perfect_week":
        // Perfect Week: 7 consecutive quests completed (uses existing streak)
        return {
          progress: metrics.currentQuestStreak >= 7 ? 1 : 0,
          target: 1,
        };

      default:
        return { progress: 0, target: null };
    }
  }

  // Unknown badge type
  return { progress: 0, target: null };
}

// Level calculation (matches database function)
function calculateLevel(totalXp: number): number {
  return Math.max(1, Math.floor(Math.sqrt(totalXp / 50)) + 1);
}

function totalXpForLevel(level: number): number {
  return 50 * (level - 1) * (level - 1);
}

// Get current hour in user's local timezone
function getLocalHour(timezone: string): number {
  try {
    const now = new Date();
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "numeric",
      hour12: false,
    });
    const hourStr = formatter.format(now);
    return parseInt(hourStr, 10);
  } catch {
    // Fallback to UTC if timezone is invalid
    return new Date().getUTCHours();
  }
}
