// MindFriend Check Badge Progress Edge Function
// Checks user progress against badge requirements and awards earned badges

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
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

    // Fetch all active badges
    const { data: badges, error: badgesError } = await supabase
      .from("badges_v2")
      .select("*")
      .eq("is_active", true)
      .in("requirement_type", ["count", "streak", "time"]); // Only check auto-trackable badges

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
  ] = await Promise.all([
    // Quests completed
    supabase
      .from("quests")
      .select("id", { count: "exact" })
      .eq("user_id", userId)
      .eq("completed", true),

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

  // Manual badges return 0 progress
  return { progress: 0, target: null };
}

// Level calculation (matches database function)
function calculateLevel(totalXp: number): number {
  return Math.max(1, Math.floor(Math.sqrt(totalXp / 50)) + 1);
}

function totalXpForLevel(level: number): number {
  return 50 * (level - 1) * (level - 1);
}
