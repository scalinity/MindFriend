import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  CalculateCapacityRequest,
  CalculateCapacityResponse,
  CapacityInput,
  CapacityOverrideRow,
  Mood,
  MoodData,
  SleepData,
  SleepLog,
  UserCapacityRow,
  CompletionData,
} from "./types.ts";
import {
  calculateSleepScore,
  calculateMoodScore,
  calculateStreakScore,
  calculateCompletionScore,
  calculateCompositeScore,
  smoothCapacity,
  scoreToLevel,
} from "./algorithms.ts";

// SECURITY FIX: Restrict CORS to specific origins in production
const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") || "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client with service role for DB writes
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Authenticate user from JWT
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

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", message: authError?.message }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const userId = user.id;

    // Parse and validate request
    const requestData: CalculateCapacityRequest = await req.json();
    const { localDate, timezone } = requestData;

    // INPUT VALIDATION: Prevent injection and bad data
    if (!localDate || !/^\d{4}-\d{2}-\d{2}$/.test(localDate)) {
      return new Response(
        JSON.stringify({ error: "Invalid localDate format. Expected YYYY-MM-DD" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!timezone || typeof timezone !== "string" || timezone.length > 50) {
      return new Response(
        JSON.stringify({ error: "Invalid timezone parameter" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for cached capacity (valid for today)
    const { data: existingCapacity } = await supabase
      .from("user_capacity")
      .select("*")
      .eq("user_id", userId)
      .eq("local_date", localDate)
      .single();

    if (
      existingCapacity &&
      new Date(existingCapacity.expires_at) > new Date()
    ) {
      // Return cached result
      const response: CalculateCapacityResponse = {
        score: existingCapacity.score,
        level: existingCapacity.level,
        components: existingCapacity.components,
        calculated_at: existingCapacity.calculated_at,
        expires_at: existingCapacity.expires_at,
        has_override: existingCapacity.has_override,
      };
      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check for active override
    const { data: activeOverride } = await supabase
      .from("capacity_overrides")
      .select("*")
      .eq("user_id", userId)
      .eq("is_active", true)
      .gt("expires_at", new Date().toISOString())
      .single();

    if (activeOverride) {
      // User has manual override active - use override score
      const overrideScore = getOverrideScore(activeOverride.override_level);
      const level = scoreToLevel(overrideScore);

      const result = await persistCapacity(
        supabase,
        userId,
        overrideScore,
        level,
        {
          sleep: { score: 50, weight: 0.30, contribution: 15.0 },
          mood: { score: 50, weight: 0.35, contribution: 17.5 },
          streak: { score: 50, weight: 0.20, contribution: 10.0 },
          completion: { score: 50, weight: 0.15, contribution: 7.5 },
        },
        localDate,
        timezone,
        true, // has_override
      );

      return new Response(JSON.stringify(result), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch data in parallel for performance
    const [sleepData, moodData, streakData, completionData, previousCapacity] =
      await Promise.all([
        fetchSleepData(supabase, userId),
        fetchMoodData(supabase, userId),
        fetchStreakData(supabase, userId),
        fetchCompletionData(supabase, userId),
        fetchPreviousCapacity(supabase, userId, localDate),
      ]);

    // Calculate component scores
    const sleepScore = calculateSleepScore(sleepData ? [sleepData] : []);
    const moodScore = calculateMoodScore(moodData ? [moodData] : []);
    const streakScore = calculateStreakScore(streakData);
    const completionScore = calculateCompletionScore(
      completionData.recentCompletionRate,
      completionData.questsCompleted,
    );

    // Calculate composite score
    const rawScore = calculateCompositeScore({
      sleep: sleepScore,
      mood: moodScore,
      streak: streakScore,
      completion: completionScore,
    });

    // Apply smoothing
    const smoothedScore = smoothCapacity(rawScore, previousCapacity);
    const level = scoreToLevel(smoothedScore);

    // Persist result
    const response = await persistCapacity(
      supabase,
      userId,
      smoothedScore,
      level,
      {
        sleep: {
          score: sleepScore,
          weight: 0.30,
          contribution: sleepScore * 0.30,
        },
        mood: {
          score: moodScore,
          weight: 0.35,
          contribution: moodScore * 0.35,
        },
        streak: {
          score: streakScore,
          weight: 0.20,
          contribution: streakScore * 0.20,
        },
        completion: {
          score: completionScore,
          weight: 0.15,
          contribution: completionScore * 0.15,
        },
      },
      localDate,
      timezone,
      false, // has_override
    );

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    // SECURITY FIX: Don't leak sensitive data in error logs
    console.error("Error calculating capacity:", {
      message: (error as any).message,
      name: (error as any).name,
      // Omit stack trace and full error object to prevent PII leakage
    });
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        // Don't expose internal error details to client
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Helper functions

async function fetchSleepData(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<SleepData | null> {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const { data: sleepLogs, error } = await supabase
    .from("sleep_logs")
    .select("fell_asleep_at, woke_up_at, quality_score, logged_at")
    .eq("user_id", userId)
    .gte("logged_at", sevenDaysAgo.toISOString())
    .order("logged_at", { ascending: false });

  if (error || !sleepLogs || sleepLogs.length === 0) {
    return null;
  }

  // Calculate metrics
  const sleepHours = sleepLogs.map((log: SleepLog) => {
    const asleep = new Date(log.fell_asleep_at);
    const awake = new Date(log.woke_up_at);
    return (awake.getTime() - asleep.getTime()) / (1000 * 60 * 60);
  });

  const averageHours =
    sleepHours.reduce((a, b) => a + b, 0) / sleepHours.length;
  const lastNightHours = sleepLogs[0] ? sleepHours[0] : null;
  const quality = sleepLogs[0]?.quality_score ?? null;

  // Calculate sleep deficit (cumulative hours below 7)
  const deficit7d = sleepHours.reduce((deficit, hours) => {
    return deficit + Math.max(0, 7 - hours);
  }, 0);

  return {
    averageHours,
    lastNightHours,
    quality,
    deficit7d,
  };
}

async function fetchMoodData(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<MoodData | null> {
  const threeDaysAgo = new Date();
  threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);

  const { data: moods, error } = await supabase
    .from("moods")
    .select("mood_score, logged_at")
    .eq("user_id", userId)
    .gte("logged_at", threeDaysAgo.toISOString())
    .order("logged_at", { ascending: false });

  if (error || !moods || moods.length === 0) {
    return null;
  }

  const moodScores = moods.map((m: Mood) => m.mood_score);
  const averageMood3d =
    moodScores.reduce((a, b) => a + b, 0) / moodScores.length;
  const todayMood = moods[0]?.mood_score ?? null;

  // Calculate trend (simple delta)
  let trend3d = 0;
  if (moodScores.length >= 3) {
    const latest = moodScores[0];
    const oldest = moodScores[moodScores.length - 1];
    trend3d = (latest - oldest) / 2;
  }

  return {
    todayMood,
    averageMood3d,
    trend3d,
  };
}

async function fetchStreakData(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<{ current_streak: number; longest_streak: number; streakDays: number; completedToday: boolean }> {
  // CORRECTNESS FIX: Query profiles.current_streak_days instead of user_settings
  const { data: profile } = await supabase
    .from("profiles")
    .select("current_streak_days, longest_streak")
    .eq("id", userId)
    .single();

  if (!profile) {
    return { current_streak: 0, longest_streak: 0, streakDays: 0, completedToday: false };
  }

  // Check if quest completed today (query quests table)
  const today = new Date().toISOString().split('T')[0];
  const { data: todayQuest } = await supabase
    .from("quests")
    .select("completed")
    .eq("user_id", userId)
    .eq("assigned_date", today)
    .single();

  return {
    current_streak: profile.current_streak_days ?? 0,
    longest_streak: profile.longest_streak ?? 0,
    streakDays: profile.current_streak_days ?? 0,
    completedToday: todayQuest?.completed ?? false,
  };
}

async function fetchCompletionData(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<CompletionData> {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  // Get recent quests (last 7 days)
  const { data: recentQuests } = await supabase
    .from("quests")
    .select("completed")
    .eq("user_id", userId)
    .gte("assigned_date", sevenDaysAgo.toISOString().split('T')[0])
    .order("assigned_date", { ascending: false });

  // Get total completed quests
  const { count: totalCompleted } = await supabase
    .from("quests")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("completed", true);

  const completedCount = recentQuests?.filter(q => q.completed).length ?? 0;
  const totalCount = recentQuests?.length ?? 1; // Avoid division by zero

  return {
    recentCompletionRate: totalCount > 0 ? completedCount / totalCount : 0,
    questsCompleted: totalCompleted ?? 0,
  };
}

async function fetchPreviousCapacity(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  currentDate: string,
): Promise<number | null> {
  const { data } = await supabase
    .from("user_capacity")
    .select("score")
    .eq("user_id", userId)
    .lt("local_date", currentDate)
    .order("local_date", { ascending: false })
    .limit(1)
    .single();

  return data?.score ?? null;
}

async function persistCapacity(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  score: number,
  level: string,
  components: CalculateCapacityResponse["components"],
  localDate: string,
  timezone: string,
  hasOverride: boolean,
): Promise<CalculateCapacityResponse> {
  const now = new Date();

  // Calculate expiration (midnight in user's timezone)
  const expiresAt = getNextMidnight(timezone);

  const capacityRow: Partial<UserCapacityRow> = {
    user_id: userId,
    score,
    level,
    components,
    local_date: localDate,
    calculated_at: now.toISOString(),
    expires_at: expiresAt.toISOString(),
    has_override: hasOverride,
    previous_score: null,
  };

  // Upsert (insert or update)
  const { error } = await supabase
    .from("user_capacity")
    .upsert(capacityRow, { onConflict: "user_id,local_date" });

  if (error) {
    // SECURITY FIX: Sanitized logging
    console.error("Error persisting capacity:", {
      message: (error as any).message,
      code: (error as any).code,
      // Omit details that might contain PII
    });
    throw error;
  }

  return {
    score,
    level: level as "low" | "moderate" | "high",
    components,
    calculated_at: now.toISOString(),
    expires_at: expiresAt.toISOString(),
    has_override: hasOverride,
  };
}

function getOverrideScore(overrideLevel: string): number {
  switch (overrideLevel) {
    case "rest":
      return 25;
    case "normal":
      return 50;
    case "challenge":
      return 75;
    default:
      return 50;
  }
}

function getNextMidnight(timezone: string): Date {
  // BUG FIX: Properly calculate midnight in user's timezone using Temporal API polyfill
  // For now, use a simple offset-based approach
  
  try {
    // Parse timezone offset (e.g., "America/New_York" or "UTC-5")
    const now = new Date();
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });
    
    const parts = formatter.formatToParts(now);
    const dateParts: Record<string, string> = {};
    parts.forEach(part => {
      dateParts[part.type] = part.value;
    });
    
    // Create date for tomorrow at midnight in the target timezone
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const tomorrowFormatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    
    const tomorrowParts = tomorrowFormatter.formatToParts(tomorrow);
    const tomorrowDate: Record<string, string> = {};
    tomorrowParts.forEach(part => {
      tomorrowDate[part.type] = part.value;
    });
    
    // Construct midnight timestamp in target timezone
    const midnightString = `${tomorrowDate.year}-${tomorrowDate.month}-${tomorrowDate.day}T00:00:00`;
    const midnightInTz = new Date(midnightString);
    
    // Calculate offset between UTC and target timezone
    const utcDate = new Date(midnightString + 'Z');
    const tzDate = new Date(formatter.format(new Date(midnightString)));
    const offset = utcDate.getTime() - tzDate.getTime();
    
    // Return midnight in target timezone as UTC Date object
    return new Date(midnightInTz.getTime() - offset);
  } catch (error) {
    // Fallback: Use UTC midnight if timezone parsing fails
    console.error("Timezone calculation failed, using UTC:", { timezone, error: (error as any).message });
    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(0, 0, 0, 0);
    return tomorrow;
  }
}
