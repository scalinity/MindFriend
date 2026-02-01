// Intervention Efficacy Engine: Get Recommendations Edge Function
// Returns context-aware exercise recommendations based on efficacy profiles

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  createLogger,
  generateRequestId,
  getUserIdFromRequest,
} from "../_shared/logger.ts";

interface GetRecommendationsRequest {
  currentState: string;
  currentEmotion: string;
  timeOfDay: string;
  limit?: number;
}

interface ExerciseRecommendation {
  contentId: string;
  contentType: string;
  contentName: string;
  durationMinutes: number;
  score: number;
  reasons: string[];
}

serve(async (req) => {
  const startTime = performance.now();
  const requestId = generateRequestId();
  const logger = createLogger("get-recommendations", { requestId });

  try {
    logger.logRequest(req.method, "/get-recommendations");

    // Validate authentication
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      logger.warn("Missing authorization header");

      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      logger.warn("Authentication failed", { error: authError?.message });
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Invalid or expired authentication token",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    logger.addContext({ userId: user.id });
    logger.info("User authenticated");

    // Parse parameters from POST body or query params (supports both)
    const url = new URL(req.url);
    const body = req.method === "POST" ? await req.json() : {};

    // Support both direct params and nested context object (iOS sends context.currentMood)
    const context = body.context || {};
    const currentState =
      body.state || context.state || url.searchParams.get("state") || "rest";
    const currentEmotion =
      body.emotion ||
      context.currentMood ||
      url.searchParams.get("emotion") ||
      "neutral";
    const timeOfDay =
      body.timeOfDay ||
      context.timeOfDay ||
      url.searchParams.get("timeOfDay") ||
      "morning";
    const limit = parseInt(body.limit || url.searchParams.get("limit") || "5");

    logger.addContext({ currentState, currentEmotion, timeOfDay, limit });
    logger.info("Request parameters parsed");

    // Fetch user efficacy profiles
    logger.debug("Fetching user efficacy profiles");
    const { data: profiles, error: profilesError } = await supabaseAdmin
      .from("user_efficacy_profiles")
      .select(
        `
        *,
        exercises:exercise_id (
          id,
          title,
          type,
          duration_minutes
        )
      `,
      )
      .eq("user_id", user.id)
      .gte("completion_count", 5); // Minimum 5 sessions for reliable data

    if (profilesError) {
      logger.error(
        "Failed to fetch profiles",
        profilesError instanceof Error
          ? profilesError
          : new Error(String(profilesError)),
      );
      return new Response(
        JSON.stringify({
          error: "DATABASE_ERROR",
          message: "Failed to fetch efficacy profiles",
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    logger.info("Efficacy profiles fetched", {
      profileCount: profiles?.length || 0,
    });

    let recommendations: ExerciseRecommendation[] = [];

    if (profiles && profiles.length > 0) {
      logger.debug("Calculating contextual scores for profiles");
      // Calculate contextual scores for each profile
      recommendations = profiles
        .filter((profile) => profile.exercises) // Filter out profiles with deleted exercises
        .map((profile) => {
          const exercise = profile.exercises as any;
          const contextualScore = calculateContextualScore(
            profile,
            currentState,
            currentEmotion,
            timeOfDay,
          );

          const reason = generateReason(
            profile,
            contextualScore,
            currentState,
            timeOfDay,
          );
          return {
            contentId: profile.exercise_id,
            contentType: exercise.type,
            contentName: exercise.title,
            durationMinutes: exercise.duration_minutes,
            score: contextualScore / 100, // Convert 0-100 to 0-1
            reasons: [reason],
          };
        });

      // Sort by score
      recommendations.sort((a, b) => b.score - a.score);

      // Return top N
      recommendations = recommendations.slice(0, limit);
      logger.info("Personalized recommendations generated", {
        count: recommendations.length,
      });
    }

    // If no proven exercises (< 3 recommendations), blend with generic recommendations
    if (recommendations.length < 3) {
      logger.debug("Fetching generic recommendations", {
        needed: limit - recommendations.length,
      });
      const genericRecs = await getGenericRecommendations(
        supabaseAdmin,
        currentState,
        currentEmotion,
        limit - recommendations.length,
        timeOfDay,
      );

      recommendations = [...recommendations, ...genericRecs];
      logger.info("Generic recommendations added", {
        genericCount: genericRecs.length,
        totalCount: recommendations.length,
      });
    }

    const duration = performance.now() - startTime;
    logger.logResponse("POST", "/get-recommendations", 200, duration);

    return new Response(
      JSON.stringify({
        recommendations,
        fallbackReason:
          profiles && profiles.length >= 3
            ? null
            : "Showing popular exercises (complete 5 sessions per exercise for personalized recommendations)",
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const duration = performance.now() - startTime;
    logger.error(
      "Unhandled error in get-recommendations",
      error instanceof Error ? error : new Error(String(error)),
    );
    logger.logResponse("POST", "/get-recommendations", 500, duration);

    return new Response(
      JSON.stringify({
        error: "RECOMMENDATION_FAILED",
        message: (error as Error).message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});

function calculateContextualScore(
  profile: any,
  state: string,
  emotion: string,
  timeOfDay: string,
): number {
  let score = profile.overall_efficacy_score;
  let count = 1;

  // Adjust for current state match
  const efficacyByState = profile.efficacy_by_state || {};
  if (efficacyByState[state] !== undefined) {
    score += efficacyByState[state];
    count++;
  }

  // Adjust for time of day
  const efficacyByTime = profile.efficacy_by_time_of_day || {};
  if (efficacyByTime[timeOfDay] !== undefined) {
    score += efficacyByTime[timeOfDay];
    count++;
  }

  // Adjust for emotion
  const efficacyByEmotion = profile.efficacy_by_emotion || {};
  if (efficacyByEmotion[emotion] !== undefined) {
    score += efficacyByEmotion[emotion];
    count++;
  }

  return score / count;
}

function generateReason(
  profile: any,
  score: number,
  state: string,
  timeOfDay: string,
): string {
  const percentage = Math.round(score);
  const contextParts: string[] = [];

  const efficacyByState = profile.efficacy_by_state || {};
  const efficacyByTime = profile.efficacy_by_time_of_day || {};

  if (efficacyByState[state] && efficacyByState[state] > score * 0.9) {
    contextParts.push(`when you're in ${state} state`);
  }

  if (efficacyByTime[timeOfDay] && efficacyByTime[timeOfDay] > score * 0.9) {
    contextParts.push(`in the ${timeOfDay}`);
  }

  const context = contextParts.length > 0 ? ` ${contextParts.join(", ")}` : "";

  return `Works ${percentage}% of the time${context}`;
}

// Mapping of emotions/moods to ideal exercise types
const MOOD_TO_EXERCISE_TYPES: Record<string, string[]> = {
  stressed: ["breathing", "meditation", "grounding"],
  anxious: ["breathing", "grounding", "movement"],
  low: ["movement", "journaling", "grounding"],
  sad: ["journaling", "movement", "meditation"],
  angry: ["breathing", "movement", "grounding"],
  overwhelmed: ["breathing", "grounding", "meditation"],
  calm: ["meditation", "journaling", "movement"],
  good: ["meditation", "journaling", "movement"],
  great: ["movement", "meditation", "journaling"],
  okay: ["breathing", "meditation", "grounding"],
  neutral: ["breathing", "meditation", "grounding"],
};

// Time of day preferences
const TIME_TO_EXERCISE_TYPES: Record<string, string[]> = {
  morning: ["breathing", "movement", "meditation"],
  afternoon: ["grounding", "movement", "journaling"],
  evening: ["meditation", "journaling", "breathing"],
  night: ["meditation", "breathing", "journaling"],
};

async function getGenericRecommendations(
  supabaseClient: any,
  currentState: string,
  currentEmotion: string,
  limit: number,
  timeOfDay: string = "morning",
): Promise<ExerciseRecommendation[]> {
  // Fetch all exercises to score them
  const { data: exercises, error } = await supabaseClient
    .from("exercises")
    .select("*");

  if (error || !exercises) {
    return [];
  }

  // Get preferred types for mood and time
  const moodTypes = MOOD_TO_EXERCISE_TYPES[currentEmotion] || [
    "breathing",
    "meditation",
    "grounding",
  ];
  const timeTypes = TIME_TO_EXERCISE_TYPES[timeOfDay] || [
    "breathing",
    "meditation",
    "grounding",
  ];

  // Score each exercise
  const scoredExercises = exercises.map((exercise: any) => {
    let score = 0.5; // Base score
    const reasons: string[] = [];

    // Boost for mood match (primary factor)
    const moodRank = moodTypes.indexOf(exercise.type);
    if (moodRank === 0) {
      score += 0.35;
      reasons.push(`Perfect for feeling ${currentEmotion}`);
    } else if (moodRank === 1) {
      score += 0.25;
      reasons.push(`Great choice when ${currentEmotion}`);
    } else if (moodRank === 2) {
      score += 0.15;
      reasons.push(`Good option for your mood`);
    }

    // Boost for time of day match
    const timeRank = timeTypes.indexOf(exercise.type);
    if (timeRank === 0) {
      score += 0.1;
      if (reasons.length === 0) reasons.push(`Ideal for ${timeOfDay}`);
    } else if (timeRank === 1) {
      score += 0.05;
    }

    // Slight boost for shorter exercises (more accessible)
    if (exercise.duration_minutes <= 5) {
      score += 0.05;
    }

    // Cap at 0.95
    score = Math.min(score, 0.95);

    // Default reason if none set
    if (reasons.length === 0) {
      reasons.push(`Try this ${exercise.type} exercise`);
    }

    return {
      contentId: exercise.id,
      contentType: exercise.type,
      contentName: exercise.title,
      durationMinutes: exercise.duration_minutes,
      score,
      reasons,
    };
  });

  // Sort by score descending
  scoredExercises.sort(
    (a: ExerciseRecommendation, b: ExerciseRecommendation) => b.score - a.score,
  );

  // Return top N with variety (don't return all of the same type)
  const result: ExerciseRecommendation[] = [];
  const typeCounts: Record<string, number> = {};

  for (const exercise of scoredExercises) {
    if (result.length >= limit) break;

    // Limit to 2 exercises per type for variety
    const typeCount = typeCounts[exercise.contentType] || 0;
    if (typeCount < 2) {
      result.push(exercise);
      typeCounts[exercise.contentType] = typeCount + 1;
    }
  }

  return result;
}
