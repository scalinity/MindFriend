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
} from "./types.ts";
import { calculateCapacity } from "./algorithms.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
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

    // Parse request
    const requestData: CalculateCapacityRequest = await req.json();
    const { localDate, timezone } = requestData;

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
      const level = getLevel(overrideScore);

      const result = await persistCapacity(
        supabase,
        userId,
        overrideScore,
        level,
        {
          sleep: { score: 50, weight: 0.35, contribution: 17.5 },
          mood: { score: 50, weight: 0.4, contribution: 20.0 },
          streak: { score: 50, weight: 0.25, contribution: 12.5 },
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
    const [sleepData, moodData, streakData, previousCapacity] =
      await Promise.all([
        fetchSleepData(supabase, userId),
        fetchMoodData(supabase, userId),
        fetchStreakData(supabase, userId),
        fetchPreviousCapacity(supabase, userId, localDate),
      ]);

    // Build capacity input
    const input: CapacityInput = {
      sleep: sleepData,
      mood: moodData,
      streak: streakData,
      previous: previousCapacity,
    };

    // Calculate capacity
    const capacityResult = calculateCapacity(input);

    // Persist result
    const response = await persistCapacity(
      supabase,
      userId,
      capacityResult.score,
      capacityResult.level,
      {
        sleep: {
          score: capacityResult.components.sleep,
          weight: 0.35,
          contribution: capacityResult.components.sleep * 0.35,
        },
        mood: {
          score: capacityResult.components.mood,
          weight: 0.4,
          contribution: capacityResult.components.mood * 0.4,
        },
        streak: {
          score: capacityResult.components.streak,
          weight: 0.25,
          contribution: capacityResult.components.streak * 0.25,
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
    console.error("Error calculating capacity:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error.message,
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
): Promise<{ streakDays: number; completedToday: boolean }> {
  // Fetch from user_settings or quests table (assuming streak stored in user_settings)
  const { data: settings } = await supabase
    .from("user_settings")
    .select("streak_days, completed_today")
    .eq("user_id", userId)
    .single();

  if (!settings) {
    return { streakDays: 0, completedToday: false };
  }

  return {
    streakDays: settings.streak_days ?? 0,
    completedToday: settings.completed_today ?? false,
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
    previous_score: null, // TODO: Set from previous fetch if needed
  };

  // Upsert (insert or update)
  const { error } = await supabase
    .from("user_capacity")
    .upsert(capacityRow, { onConflict: "user_id,local_date" });

  if (error) {
    console.error("Error persisting capacity:", error);
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

function getLevel(score: number): string {
  if (score <= 40) return "low";
  if (score <= 70) return "moderate";
  return "high";
}

function getNextMidnight(timezone: string): Date {
  // Calculate next midnight in user's timezone
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);

  // Simple approach: set to start of next day UTC, adjust for timezone later
  // For MVP, use UTC midnight + 1 day
  tomorrow.setUTCHours(0, 0, 0, 0);

  return tomorrow;
}
