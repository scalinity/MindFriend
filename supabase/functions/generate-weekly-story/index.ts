// MindFriend Progress Stories Generator
// Generates 3-5 visual story cards from weekly data for progress recaps
// See: kimispecs/07-progress-stories-spec.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import {
  getCorsHeaders,
  validateContentType,
  parseJsonBody,
} from "../_shared/cors.ts";

// Story card types
type CardType =
  | "streak"
  | "mood"
  | "exercise"
  | "quest"
  | "insight"
  | "minimal"
  | "milestone";
type CardVariant = "default" | "celebration" | "encouragement" | "milestone";

interface StoryCard {
  id: string;
  cardType: CardType;
  variant: CardVariant;
  data: Record<string, unknown>;
  generatedAt: string;
}

interface GenerateStoryRequest {
  weekStart: string; // YYYY-MM-DD format, must be a Monday
}

interface WeeklyStats {
  checkinCount: number;
  questCount: number;
  exerciseCount: number;
  avgMood: number | null;
  moodTrend: "improving" | "stable" | "declining" | null;
  moodMin: number | null;
  moodMax: number | null;
  exerciseMinutes: number;
  streakDays: number;
}

interface UserProfile {
  id: string;
  displayName: string | null;
  wellnessFocus: string | null;
  currentStreakDays: number;
}

// Streak milestone thresholds
const STREAK_MILESTONES = [7, 14, 30, 50, 100, 365];

// Supportive messages by context
const MESSAGES = {
  streak: {
    start: "Every journey begins with a single step. Start logging today!",
    short: "You're building momentum! Keep the streak alive.",
    medium: "Consistency is key, and you've got it! Keep going.",
    long: "You're unstoppable! This dedication is paying off.",
    milestone: "Incredible milestone! Your commitment is truly inspiring.",
  },
  mood: {
    improving: "Your mood is trending up! Small steps lead to big changes.",
    stable: "Steady and grounded. Consistency is a strength.",
    declining:
      "It's been a challenging week. Remember: every day is a fresh start.",
    noData: "Start logging your mood to see your patterns emerge.",
  },
  exercise: {
    active: "You've been moving your body! Exercise is self-care.",
    light: "Every minute counts. Keep incorporating movement.",
    none: "Movement is medicine. Try adding a short exercise this week.",
  },
  quest: {
    completed:
      "You crushed your quests! Each one builds your wellness foundation.",
    partial: "Progress over perfection. You're doing great!",
    none: "Quests help build healthy habits. Try one this week!",
  },
  minimal: {
    encourage: "This week is a fresh canvas. What will you create?",
    welcome:
      "Welcome to your weekly story! Log activities to see your progress.",
  },
};

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  // Validate Content-Type
  const contentTypeError = validateContentType(req, corsHeaders);
  if (contentTypeError) return contentTypeError;

  // Must be POST
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({
        error: "Method not allowed",
        code: "METHOD_NOT_ALLOWED",
      }),
      { status: 405, headers },
    );
  }

  // Authenticate user via JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ error: "Unauthorized", code: "UNAUTHORIZED" }),
      { status: 401, headers },
    );
  }

  const token = authHeader.replace("Bearer ", "");

  // Initialize Supabase clients
  const supabaseAuth = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const {
    data: { user },
    error: authError,
  } = await supabaseAuth.auth.getUser(token);

  if (authError || !user) {
    console.error("Auth error:", authError?.message);
    return new Response(
      JSON.stringify({ error: "Invalid token", code: "INVALID_TOKEN" }),
      { status: 401, headers },
    );
  }

  try {
    // Parse request body
    const body = await parseJsonBody<GenerateStoryRequest>(req);
    if (!body?.weekStart) {
      return new Response(
        JSON.stringify({
          error: "weekStart is required",
          code: "MISSING_WEEK_START",
        }),
        { status: 400, headers },
      );
    }

    // Validate weekStart format (YYYY-MM-DD)
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(body.weekStart)) {
      return new Response(
        JSON.stringify({
          error: "Invalid weekStart format. Use YYYY-MM-DD.",
          code: "INVALID_DATE_FORMAT",
        }),
        { status: 400, headers },
      );
    }

    // Validate weekStart is a Monday
    const weekStartDate = new Date(body.weekStart + "T00:00:00Z");
    if (weekStartDate.getUTCDay() !== 1) {
      // 1 = Monday
      return new Response(
        JSON.stringify({
          error: "weekStart must be a Monday",
          code: "NOT_MONDAY",
        }),
        { status: 400, headers },
      );
    }

    // Validate weekStart is not in the future
    const now = new Date();
    const currentMonday = getWeekStart(now);
    if (weekStartDate > currentMonday) {
      return new Response(
        JSON.stringify({
          error: "weekStart cannot be in the future",
          code: "FUTURE_DATE",
        }),
        { status: 400, headers },
      );
    }

    // Read user preferences
    const { data: preferencesData } = await supabaseAuth
      .from("narrative_preferences")
      .select("preferred_tone, preferred_length, include_metrics")
      .eq("user_id", user.id)
      .single();

    const preferences = {
      tone: preferencesData?.preferred_tone || "warm",
      length: preferencesData?.preferred_length || "standard",
      includeMetrics: preferencesData?.include_metrics ?? true,
    };

    // Generate story cards
    const cards = await generateStoryCards(
      supabaseAuth,
      user.id,
      body.weekStart,
      preferences,
    );

    // Upsert to weekly_stories table
    const { error: upsertError } = await supabaseAuth
      .from("weekly_stories")
      .upsert(
        {
          user_id: user.id,
          week_start: body.weekStart,
          cards: cards,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id,week_start" },
      );

    if (upsertError) {
      console.error("Upsert error:", upsertError);
      // For transient errors, warn but return cards anyway
      // For permanent errors, throw
      if (
        upsertError.message?.includes("permission denied") ||
        upsertError.message?.includes("violates foreign key")
      ) {
        // Permanent error
        return new Response(
          JSON.stringify({
            error: "Unable to persist story",
            code: "PERSIST_FAILED",
          }),
          { status: 500, headers },
        );
      }
      // Transient error - log but continue
      console.warn("Upsert failed (transient), but returning cards");
    }

    return new Response(
      JSON.stringify({
        success: true,
        userId: user.id,
        weekStart: body.weekStart,
        cards,
        generatedAt: new Date().toISOString(),
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Story generation error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        code: "INTERNAL_ERROR",
      }),
      { status: 500, headers },
    );
  }
});

/**
 * Get Monday of the week for a given date
 */
function getWeekStart(date: Date): Date {
  const d = new Date(date);
  const day = d.getUTCDay();
  const diff = day === 0 ? 6 : day - 1; // Sunday = 6 days back, otherwise day - 1
  d.setUTCDate(d.getUTCDate() - diff);
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

/**
 * Generate a UUID v4
 */
function generateUUID(): string {
  return crypto.randomUUID();
}

/**
 * Generate 3-5 story cards based on user's weekly data
 */
interface NarrativePreferences {
  tone: "warm" | "professional" | "playful";
  length: "brief" | "standard" | "detailed";
  includeMetrics: boolean;
}

async function generateStoryCards(
  supabase: SupabaseClient,
  userId: string,
  weekStart: string,
  preferences: NarrativePreferences,
): Promise<StoryCard[]> {
  const cards: StoryCard[] = [];
  const now = new Date().toISOString();

  // Fetch user profile
  const { data: profileData, error: profileError } = await supabase
    .from("profiles")
    .select("id, display_name, wellness_focus, current_streak_days")
    .eq("id", userId)
    .single();

  if (profileError) {
    console.error("Profile query error:", profileError);
    // Use defaults if profile not found
  }

  const profile: UserProfile = {
    id: userId,
    displayName: profileData?.display_name ?? null,
    wellnessFocus: profileData?.wellness_focus ?? null,
    currentStreakDays: profileData?.current_streak_days ?? 0,
  };

  // Calculate week end date
  const weekEnd = new Date(weekStart + "T00:00:00Z");
  weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);
  const weekEndStr = weekEnd.toISOString().split("T")[0];

  // Fetch weekly stats
  const stats = await fetchWeeklyStats(
    supabase,
    userId,
    weekStart,
    weekEndStr,
    profile.currentStreakDays,
  );

  // Determine which cards to generate based on available data
  const hasSignificantData =
    stats.checkinCount >= 3 ||
    stats.questCount >= 1 ||
    stats.exerciseCount >= 1;

  if (!hasSignificantData) {
    // Generate minimal 2-card story for insufficient data
    return generateMinimalStory(now);
  }

  // 1. Always add streak card (or minimal if no streak)
  if (stats.streakDays > 0) {
    cards.push(generateStreakCard(stats.streakDays, now));
  }

  // 2. Add mood card if enough check-ins
  if (stats.checkinCount >= 3 && stats.avgMood !== null) {
    cards.push(generateMoodCard(stats, now));
  }

  // 3. Add exercise card if any exercises
  if (stats.exerciseCount > 0) {
    cards.push(generateExerciseCard(stats, now));
  }

  // 4. Add quest card if any quests completed
  if (stats.questCount > 0) {
    cards.push(generateQuestCard(stats, now));
  }

  // 5. Check for milestones
  const milestone = detectMilestone(stats);
  if (milestone) {
    cards.push(generateMilestoneCard(milestone, now));
  }

  // 6. Try to get AI insight from weekly_summaries if available
  const { data: summaryData } = await supabase
    .from("weekly_summaries")
    .select("ai_insight")
    .eq("user_id", userId)
    .eq("week_start", weekStart)
    .single();

  if (summaryData?.ai_insight && cards.length < 5) {
    cards.push(generateInsightCard(summaryData.ai_insight, now));
  }

  // Apply length preference
  const cardLimits = {
    brief: { min: 2, max: 3 },
    standard: { min: 3, max: 5 },
    detailed: { min: 5, max: 7 },
  };

  const { min, max } = cardLimits[preferences.length];

  // Ensure we have at least min cards
  while (cards.length < min) {
    cards.push(generateEncouragementCard(cards.length, now));
  }

  // Apply tone preference to card messages (update messages based on tone)
  const updatedCards = cards.map((card) =>
    applyToneToCard(card, preferences.tone),
  );

  // Apply metrics preference (conditionally include/exclude numeric data)
  const finalCards = preferences.includeMetrics
    ? updatedCards
    : updatedCards.map((card) => removeMetricsFromCard(card));

  // Limit to max cards based on length preference
  return finalCards.slice(0, max);
}

/**
 * Fetch weekly statistics
 */
async function fetchWeeklyStats(
  supabase: SupabaseClient,
  userId: string,
  weekStart: string,
  weekEnd: string,
  currentStreakDays: number,
): Promise<WeeklyStats> {
  // Fetch mood check-ins (limit to 100 entries per week for performance)
  const {
    data: moods,
    count: moodCount,
    error: moodError,
  } = await supabase
    .from("moods")
    .select("mood_score", { count: "exact" })
    .eq("user_id", userId)
    .gte("local_date", weekStart)
    .lt("local_date", weekEnd)
    .order("local_date", { ascending: true })
    .limit(100);

  if (moodError) {
    console.error("Mood query error:", moodError);
    return {
      checkinCount: 0,
      questCount: 0,
      exerciseCount: 0,
      avgMood: null,
      moodTrend: null,
      moodMin: null,
      moodMax: null,
      exerciseMinutes: 0,
      streakDays: currentStreakDays,
    };
  }

  // Calculate mood stats
  let avgMood: number | null = null;
  let moodMin: number | null = null;
  let moodMax: number | null = null;
  let moodTrend: "improving" | "stable" | "declining" | null = null;

  if (moods && moods.length > 0) {
    const scores = moods
      .map((m) => m.mood_score)
      .filter((s) => s !== null) as number[];
    if (scores.length > 0) {
      avgMood = scores.reduce((a, b) => a + b, 0) / scores.length;
      moodMin = Math.min(...scores);
      moodMax = Math.max(...scores);

      // Simple trend detection (first half vs second half)
      if (scores.length >= 4) {
        const midpoint = Math.floor(scores.length / 2);
        const firstHalf = scores.slice(0, midpoint);
        const secondHalf = scores.slice(midpoint);
        const firstAvg =
          firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length;
        const secondAvg =
          secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length;

        if (secondAvg - firstAvg > 0.5) moodTrend = "improving";
        else if (firstAvg - secondAvg > 0.5) moodTrend = "declining";
        else moodTrend = "stable";
      }
    }
  }

  // Fetch quest completions (count only, limit prevents full scan)
  const { count: questCount, error: questError } = await supabase
    .from("quests")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", "completed")
    .gte("completed_at", weekStart + "T00:00:00Z")
    .lt("completed_at", weekEnd + "T00:00:00Z");

  if (questError) {
    console.error("Quest query error:", questError);
    return {
      checkinCount: moodCount ?? 0,
      questCount: 0,
      exerciseCount: 0,
      avgMood,
      moodTrend,
      moodMin,
      moodMax,
      exerciseMinutes: 0,
      streakDays: currentStreakDays,
    };
  }

  // Fetch exercise sessions (limit to 100 entries per week for performance)
  const {
    data: exercises,
    count: exerciseCount,
    error: exerciseError,
  } = await supabase
    .from("exercise_sessions")
    .select("duration_seconds", { count: "exact" })
    .eq("user_id", userId)
    .gte("completed_at", weekStart + "T00:00:00Z")
    .lt("completed_at", weekEnd + "T00:00:00Z")
    .order("completed_at", { ascending: true })
    .limit(100);

  if (exerciseError) {
    console.error("Exercise query error:", exerciseError);
    return {
      checkinCount: moodCount ?? 0,
      questCount: questCount ?? 0,
      exerciseCount: 0,
      avgMood,
      moodTrend,
      moodMin,
      moodMax,
      exerciseMinutes: 0,
      streakDays: currentStreakDays,
    };
  }

  // Calculate exercise minutes
  let exerciseMinutes = 0;
  if (exercises) {
    exerciseMinutes = exercises.reduce((total, e) => {
      return total + Math.round((e.duration_seconds || 0) / 60);
    }, 0);
  }

  return {
    checkinCount: moodCount ?? 0,
    questCount: questCount ?? 0,
    exerciseCount: exerciseCount ?? 0,
    avgMood,
    moodTrend,
    moodMin,
    moodMax,
    exerciseMinutes,
    streakDays: currentStreakDays,
  };
}

/**
 * Generate minimal 2-card story for insufficient data
 */
function generateMinimalStory(generatedAt: string): StoryCard[] {
  return [
    {
      id: generateUUID(),
      cardType: "minimal",
      variant: "encouragement",
      data: {
        headline: "Start Your Journey",
        message: MESSAGES.minimal.welcome,
        icon: "sparkles",
      },
      generatedAt,
    },
    {
      id: generateUUID(),
      cardType: "minimal",
      variant: "encouragement",
      data: {
        headline: "This Week's Opportunity",
        message: MESSAGES.minimal.encourage,
        icon: "leaf",
        callToAction: "Log Your First Mood",
      },
      generatedAt,
    },
  ];
}

/**
 * Generate streak card
 */
function generateStreakCard(
  streakDays: number,
  generatedAt: string,
): StoryCard {
  let message: string;
  let variant: CardVariant = "default";
  let headline = "Keep Going!";

  // Check for milestone
  const isMilestone = STREAK_MILESTONES.includes(streakDays);

  if (isMilestone) {
    variant = "milestone";
    headline =
      streakDays === 100 ? "Century Streak!" : `${streakDays} Day Milestone!`;
    message = MESSAGES.streak.milestone;
  } else if (streakDays >= 30) {
    variant = "celebration";
    headline = "Unstoppable!";
    message = MESSAGES.streak.long;
  } else if (streakDays >= 7) {
    headline = "On Fire!";
    message = MESSAGES.streak.medium;
  } else {
    message = MESSAGES.streak.short;
  }

  return {
    id: generateUUID(),
    cardType: "streak",
    variant,
    data: {
      headline,
      stat: String(streakDays),
      statLabel: streakDays === 1 ? "Day Streak" : "Day Streak",
      message,
      streakDays,
    },
    generatedAt,
  };
}

/**
 * Generate mood card
 */
function generateMoodCard(stats: WeeklyStats, generatedAt: string): StoryCard {
  let message: string;
  let variant: CardVariant = "default";
  let headline = "Your Mood This Week";

  switch (stats.moodTrend) {
    case "improving":
      headline = "Rising Up!";
      message = MESSAGES.mood.improving;
      variant = "celebration";
      break;
    case "declining":
      headline = "Staying Strong";
      message = MESSAGES.mood.declining;
      variant = "encouragement";
      break;
    case "stable":
    default:
      headline = "Steady Progress";
      message = MESSAGES.mood.stable;
      break;
  }

  return {
    id: generateUUID(),
    cardType: "mood",
    variant,
    data: {
      headline,
      stat: stats.avgMood?.toFixed(1) ?? "—",
      statLabel: "Average Mood",
      message,
      trend: stats.moodTrend ?? "stable",
      checkinCount: stats.checkinCount,
      moodMin: stats.moodMin,
      moodMax: stats.moodMax,
    },
    generatedAt,
  };
}

/**
 * Generate exercise card
 */
function generateExerciseCard(
  stats: WeeklyStats,
  generatedAt: string,
): StoryCard {
  let message: string;
  let variant: CardVariant = "default";
  let headline = "Movement Matters";

  if (stats.exerciseMinutes >= 150) {
    // CDC recommended weekly exercise
    headline = "Fitness Champion!";
    message = MESSAGES.exercise.active;
    variant = "celebration";
  } else if (stats.exerciseMinutes >= 60) {
    headline = "Active Week!";
    message = MESSAGES.exercise.active;
  } else {
    headline = "Getting Moving";
    message = MESSAGES.exercise.light;
    variant = "encouragement";
  }

  return {
    id: generateUUID(),
    cardType: "exercise",
    variant,
    data: {
      headline,
      stat: String(stats.exerciseMinutes),
      statLabel: "Minutes Active",
      message,
      exerciseCount: stats.exerciseCount,
      exerciseMinutes: stats.exerciseMinutes,
    },
    generatedAt,
  };
}

/**
 * Generate quest card
 */
function generateQuestCard(stats: WeeklyStats, generatedAt: string): StoryCard {
  let message: string;
  let variant: CardVariant = "default";
  let headline = "Quest Progress";

  if (stats.questCount >= 7) {
    headline = "Quest Master!";
    message = MESSAGES.quest.completed;
    variant = "celebration";
  } else if (stats.questCount >= 3) {
    headline = "Quests Conquered!";
    message = MESSAGES.quest.completed;
  } else {
    headline = "Making Progress";
    message = MESSAGES.quest.partial;
    variant = "encouragement";
  }

  return {
    id: generateUUID(),
    cardType: "quest",
    variant,
    data: {
      headline,
      stat: String(stats.questCount),
      statLabel:
        stats.questCount === 1 ? "Quest Completed" : "Quests Completed",
      message,
      questCount: stats.questCount,
    },
    generatedAt,
  };
}

/**
 * Generate insight card from AI insight
 */
function generateInsightCard(insight: string, generatedAt: string): StoryCard {
  // Truncate insight if too long
  const maxLength = 200;
  const truncatedInsight =
    insight.length > maxLength
      ? insight.substring(0, maxLength - 3) + "..."
      : insight;

  return {
    id: generateUUID(),
    cardType: "insight",
    variant: "default",
    data: {
      headline: "Your Weekly Insight",
      message: truncatedInsight,
      aiGenerated: true,
    },
    generatedAt,
  };
}

/**
 * Generate milestone card
 */
function generateMilestoneCard(
  milestone: {
    type: string;
    value: number;
    title: string;
    description: string;
  },
  generatedAt: string,
): StoryCard {
  return {
    id: generateUUID(),
    cardType: "milestone",
    variant: "milestone",
    data: {
      headline: milestone.title,
      stat: String(milestone.value),
      statLabel: milestone.type,
      message: milestone.description,
      milestoneType: milestone.type,
    },
    generatedAt,
  };
}

/**
 * Generate generic encouragement card (filler for minimum 3 cards)
 */
function generateEncouragementCard(
  index: number,
  generatedAt: string,
): StoryCard {
  const encouragements = [
    {
      headline: "Keep It Up!",
      message:
        "Every step forward counts. You're building something meaningful.",
      icon: "heart",
    },
    {
      headline: "Small Steps, Big Impact",
      message: "Consistency beats intensity. Keep showing up for yourself.",
      icon: "sparkles",
    },
    {
      headline: "You've Got This",
      message: "Progress isn't always visible, but it's always happening.",
      icon: "sun",
    },
  ];

  const encouragement = encouragements[index % encouragements.length];

  return {
    id: generateUUID(),
    cardType: "minimal",
    variant: "encouragement",
    data: {
      ...encouragement,
    },
    generatedAt,
  };
}

/**
 * Detect achievements/milestones
 */
function detectMilestone(
  stats: WeeklyStats,
): { type: string; value: number; title: string; description: string } | null {
  // Check for first-time achievements
  if (
    stats.exerciseMinutes >= 150 &&
    stats.questCount >= 7 &&
    stats.checkinCount >= 7
  ) {
    return {
      type: "Perfect Week",
      value: 1,
      title: "Perfect Week!",
      description:
        "You hit all your targets this week. That's incredible commitment!",
    };
  }

  // Check for specific milestones
  if (stats.questCount === 7) {
    return {
      type: "Quest Streak",
      value: 7,
      title: "Daily Quest Warrior",
      description: "You completed a quest every single day this week!",
    };
  }

  if (stats.exerciseMinutes >= 300) {
    return {
      type: "Exercise Minutes",
      value: stats.exerciseMinutes,
      title: "Fitness Powerhouse",
      description: "Over 5 hours of exercise this week! Your body thanks you.",
    };
  }

  return null;
}

/**
 * Apply tone preference to a card's message
 */
function applyToneToCard(
  card: StoryCard,
  tone: "warm" | "professional" | "playful",
): StoryCard {
  // Define tone-specific message variations
  const toneMessages: Record<string, Record<string, string>> = {
    warm: {
      "You're blooming beautifully": "You're blooming beautifully! 🌸",
      "Strong progress this week": "You're making wonderful progress this week",
      "You crushed it this week": "You're doing amazing this week!",
    },
    professional: {
      "You're blooming beautifully": "Significant progress observed this week",
      "Strong progress this week": "Strong progress this week",
      "You crushed it this week": "Excellent performance this week",
    },
    playful: {
      "You're blooming beautifully": "Look at you go! 🎉",
      "Strong progress this week": "You're on fire this week! 🔥",
      "You crushed it this week": "You absolutely crushed it this week! 💪",
    },
  };

  // Apply tone to message if it exists in the mapping
  const message = card.data.message || "";
  const toneMap = toneMessages[tone] || {};

  // Check if we have a tone variation for this message
  for (const [original, replacement] of Object.entries(toneMap)) {
    if (message.includes(original)) {
      return {
        ...card,
        data: {
          ...card.data,
          message: message.replace(original, replacement),
        },
      };
    }
  }

  // Return card unchanged if no tone mapping found
  return card;
}

/**
 * Remove metrics from card data (for users who prefer qualitative insights only)
 */
function removeMetricsFromCard(card: StoryCard): StoryCard {
  return {
    ...card,
    data: {
      ...card.data,
      stat: undefined,
      statLabel: undefined,
      // Keep other fields like headline and message
    },
  };
}
