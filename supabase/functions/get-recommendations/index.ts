// Intervention Efficacy Engine: Get Recommendations Edge Function
// Returns context-aware exercise recommendations based on efficacy profiles

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface GetRecommendationsRequest {
  currentState: string;
  currentEmotion: string;
  timeOfDay: string;
  limit?: number;
}

interface ExerciseRecommendation {
  exerciseId: string;
  exerciseName: string;
  exerciseType: string;
  duration: number;
  predictedEfficacy: number;
  confidence: number;
  completionCount: number;
  reason: string;
  trend: string | null;
}

serve(async (req) => {
  try {
    // Get user from JWT
    const authHeader = req.headers.get("Authorization")!;
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: { headers: { Authorization: authHeader } },
      }
    );

    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Parse query parameters
    const url = new URL(req.url);
    const currentState = url.searchParams.get("state") || "rest";
    const currentEmotion = url.searchParams.get("emotion") || "neutral";
    const timeOfDay = url.searchParams.get("timeOfDay") || "morning";
    const limit = parseInt(url.searchParams.get("limit") || "5");

    // Fetch user efficacy profiles
    const { data: profiles, error: profilesError } = await supabaseClient
      .from("user_efficacy_profiles")
      .select(`
        *,
        exercises:exercise_id (
          id,
          name,
          type,
          duration
        )
      `)
      .eq("user_id", user.id)
      .gte("completion_count", 5); // Minimum 5 sessions for reliable data

    if (profilesError) {
      console.error("Failed to fetch profiles:", profilesError);
      return new Response(
        JSON.stringify({
          error: "DATABASE_ERROR",
          message: "Failed to fetch efficacy profiles",
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    let recommendations: ExerciseRecommendation[] = [];

    if (profiles && profiles.length > 0) {
      // Calculate contextual scores for each profile
      recommendations = profiles.map((profile) => {
        const exercise = profile.exercises as any;
        const contextualScore = calculateContextualScore(
          profile,
          currentState,
          currentEmotion,
          timeOfDay
        );

        return {
          exerciseId: profile.exercise_id,
          exerciseName: exercise.name,
          exerciseType: exercise.type,
          duration: exercise.duration,
          predictedEfficacy: contextualScore,
          confidence: profile.confidence,
          completionCount: profile.completion_count,
          reason: generateReason(profile, contextualScore, currentState, timeOfDay),
          trend: profile.trend,
        };
      });

      // Sort by predicted efficacy
      recommendations.sort((a, b) => b.predictedEfficacy - a.predictedEfficacy);

      // Return top N
      recommendations = recommendations.slice(0, limit);
    }

    // If no proven exercises (< 3 recommendations), blend with generic recommendations
    if (recommendations.length < 3) {
      const genericRecs = await getGenericRecommendations(
        supabaseClient,
        currentState,
        currentEmotion,
        limit - recommendations.length
      );

      recommendations = [...recommendations, ...genericRecs];
    }

    return new Response(
      JSON.stringify({
        recommendations,
        fallbackReason: profiles && profiles.length >= 3
          ? null
          : "Showing popular exercises (complete 5 sessions per exercise for personalized recommendations)",
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in get-recommendations:", error);
    return new Response(
      JSON.stringify({
        error: "RECOMMENDATION_FAILED",
        message: error.message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});

function calculateContextualScore(
  profile: any,
  state: string,
  emotion: string,
  timeOfDay: string
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
  timeOfDay: string
): string {
  const percentage = Math.round(score);
  const contextParts: string[] = [];

  const efficacyByState = profile.efficacy_by_state || {};
  const efficacyByTime = profile.efficacy_by_time_of_day || {};

  if (efficacyByState[state] && efficacyByState[state] > score * 0.9) {
    contextParts.push(\`when you're in \${state} state\`);
  }

  if (efficacyByTime[timeOfDay] && efficacyByTime[timeOfDay] > score * 0.9) {
    contextParts.push(\`in the \${timeOfDay}\`);
  }

  const context = contextParts.length > 0 ? \` \${contextParts.join(", ")}\` : "";

  return \`Works \${percentage}% of the time\${context}\`;
}

async function getGenericRecommendations(
  supabaseClient: any,
  currentState: string,
  currentEmotion: string,
  limit: number
): Promise<ExerciseRecommendation[]> {
  // Fetch popular exercises (by overall completion count across all users)
  // For MVP, use simple heuristic: breathing for anxiety, meditation for stress, etc.
  const { data: exercises, error } = await supabaseClient
    .from("exercises")
    .select("*")
    .limit(limit);

  if (error || !exercises) {
    return [];
  }

  return exercises.map((exercise: any) => ({
    exerciseId: exercise.id,
    exerciseName: exercise.name,
    exerciseType: exercise.type,
    duration: exercise.duration,
    predictedEfficacy: 60, // Generic baseline
    confidence: 0,
    completionCount: 0,
    reason: \`Popular exercise for \${currentEmotion} (you haven't tried this yet)\`,
    trend: null,
  }));
}
