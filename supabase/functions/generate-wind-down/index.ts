import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface WindDownRequest {
  targetBedtime: string; // ISO 8601 date
  availableMinutes: number; // 10-120
  preferences: string[]; // ["breathing", "meditation", "journaling", etc.]
}

interface WindDownActivity {
  id: string;
  type: string;
  exerciseId: string | null;
  name: string;
  durationMinutes: number;
  completed: boolean;
}

interface WindDownSession {
  id: string;
  userId: string;
  startedAt: string;
  routine: WindDownActivity[];
  durationPlannedMinutes: number;
  completed: boolean;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
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

    // Parse request body
    const body: WindDownRequest = await req.json();

    // Validate input
    if (
      !body.availableMinutes ||
      body.availableMinutes < 10 ||
      body.availableMinutes > 120
    ) {
      return new Response(
        JSON.stringify({
          error: "Available minutes must be between 10 and 120",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get user's exercise history for personalization
    const { data: exerciseHistory } = await supabase
      .from("exercise_sessions")
      .select("exercise_id, feedback_rating")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(50);

    // Get exercises suitable for wind-down
    const { data: exercises } = await supabase
      .from("exercises")
      .select("*")
      .in("type", body.preferences || ["breathing", "meditation"])
      .order("sort_order", { ascending: true });

    // Build personalized routine
    const routine = buildRoutine(
      exercises || [],
      exerciseHistory || [],
      body.preferences || ["breathing", "meditation"],
      body.availableMinutes,
    );

    // Create wind-down session
    const session: Partial<WindDownSession> = {
      user_id: user.id,
      started_at: new Date().toISOString(),
      routine: routine,
      duration_planned_minutes: body.availableMinutes,
      completed: false,
    };

    const { data: createdSession, error: sessionError } = await supabase
      .from("wind_down_sessions")
      .insert(session)
      .select()
      .single();

    if (sessionError) {
      throw sessionError;
    }

    // Generate personalized tips
    const tips = await generateTips(supabase, user.id);

    return new Response(
      JSON.stringify({
        session: createdSession,
        tips: tips,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error generating wind-down:", error);

    return new Response(
      JSON.stringify({
        error: "Failed to generate wind-down routine",
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Build a personalized wind-down routine based on preferences and time
 */
function buildRoutine(
  exercises: any[],
  history: any[],
  preferences: string[],
  totalMinutes: number,
): WindDownActivity[] {
  const routine: WindDownActivity[] = [];
  let remaining = totalMinutes;

  // 1. Always start with breathing (5 min) - calming effect
  const breathingExercise = exercises.find((e) => e.type === "breathing");
  if (breathingExercise && remaining >= 5) {
    routine.push({
      id: crypto.randomUUID(),
      type: "breathing",
      exerciseId: breathingExercise.id,
      name: breathingExercise.name || "Deep Breathing",
      durationMinutes: Math.min(5, remaining),
      completed: false,
    });
    remaining -= 5;
  }

  // 2. Add meditation if time permits (10-15 min)
  if (preferences.includes("meditation") && remaining >= 10) {
    const meditationExercise = findBestExercise(
      exercises,
      history,
      "meditation",
    );
    if (meditationExercise) {
      const duration = Math.min(15, remaining - 5); // Leave 5 min for closing
      routine.push({
        id: crypto.randomUUID(),
        type: "meditation",
        exerciseId: meditationExercise.id,
        name: meditationExercise.name || "Guided Meditation",
        durationMinutes: duration,
        completed: false,
      });
      remaining -= duration;
    }
  }

  // 3. Add stretching if preferred and time permits (5-10 min)
  if (preferences.includes("stretching") && remaining >= 5) {
    const stretchingExercise = findBestExercise(
      exercises,
      history,
      "stretching",
    );
    if (stretchingExercise) {
      const duration = Math.min(10, remaining - 5);
      routine.push({
        id: crypto.randomUUID(),
        type: "stretching",
        exerciseId: stretchingExercise.id,
        name: stretchingExercise.name || "Gentle Stretching",
        durationMinutes: duration,
        completed: false,
      });
      remaining -= duration;
    }
  }

  // 4. Fill remaining time with journaling (always available, no exercise required)
  if (remaining >= 5) {
    routine.push({
      id: crypto.randomUUID(),
      type: "journaling",
      exerciseId: null,
      name: "Gratitude Reflection",
      durationMinutes: remaining,
      completed: false,
    });
  }

  return routine;
}

/**
 * Find the best exercise based on user history and ratings
 */
function findBestExercise(
  exercises: any[],
  history: any[],
  type: string,
): any | null {
  const typeExercises = exercises.filter((e) => e.type === type);

  if (typeExercises.length === 0) return null;

  // If no history, return first exercise
  if (history.length === 0) return typeExercises[0];

  // Score exercises based on history
  const scored = typeExercises.map((exercise) => {
    const sessionHistory = history.filter((h) => h.exercise_id === exercise.id);

    if (sessionHistory.length === 0) {
      return { exercise, score: 0 }; // Not tried yet
    }

    // Average rating
    const avgRating =
      sessionHistory.reduce((sum, h) => sum + (h.feedback_rating || 3), 0) /
      sessionHistory.length;

    return { exercise, score: avgRating };
  });

  // Sort by score (highest first), then return top exercise
  scored.sort((a, b) => b.score - a.score);

  return scored[0].exercise;
}

/**
 * Generate personalized tips based on recent sleep data
 */
async function generateTips(supabase: any, userId: string): Promise<string[]> {
  const tips: string[] = [];

  // Fetch last 7 days of sleep entries
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const { data: entries } = await supabase
    .from("sleep_entries")
    .select("*")
    .eq("user_id", userId)
    .gte("date", sevenDaysAgo.toISOString().split("T")[0])
    .order("date", { ascending: false });

  if (!entries || entries.length === 0) {
    tips.push("Start tracking your sleep to get personalized insights");
    return tips;
  }

  // Check average sleep score
  const avgScore =
    entries.reduce((sum: number, e: any) => sum + (e.sleep_score || 0), 0) /
    entries.length;

  if (avgScore < 70) {
    tips.push(
      "Your sleep quality has been below optimal this week - tonight's routine can help",
    );
  }

  // Check for late bedtimes
  const avgBedtimeMinutes =
    entries.reduce((sum: number, e: any) => {
      const bedtime = new Date(e.bedtime);
      return sum + (bedtime.getHours() * 60 + bedtime.getMinutes());
    }, 0) / entries.length;

  if (avgBedtimeMinutes > 23 * 60 + 30) {
    // After 11:30 PM
    tips.push(
      "You've been going to bed late this week - try starting your wind-down earlier tonight",
    );
  }

  // Check for low deep sleep (if available)
  const entriesWithStages = entries.filter(
    (e: any) => e.deep_sleep_minutes !== null,
  );
  if (entriesWithStages.length > 0) {
    const avgDeepSleep =
      entriesWithStages.reduce(
        (sum: number, e: any) => sum + (e.deep_sleep_minutes || 0),
        0,
      ) / entriesWithStages.length;
    const avgTotalSleep =
      entriesWithStages.reduce(
        (sum: number, e: any) => sum + (e.time_asleep_minutes || 0),
        0,
      ) / entriesWithStages.length;
    const deepSleepPercent = (avgDeepSleep / avgTotalSleep) * 100;

    if (deepSleepPercent < 15) {
      tips.push(
        "Your deep sleep has been low - try the Deep Sleep meditation tonight",
      );
    }
  }

  // If no tips generated, add an encouraging one
  if (tips.length === 0) {
    tips.push("You're doing great with your sleep routine - keep it up!");
  }

  return tips;
}
