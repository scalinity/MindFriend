// Intervention Efficacy Engine: Get Efficacy Dashboard Edge Function
// Returns dashboard data with top exercises, recent sessions, and insights

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

    // Fetch top exercises
    const { data: topExercises, error: topError } = await supabaseClient
      .from("user_efficacy_profiles")
      .select(\`
        *,
        exercises:exercise_id (
          id,
          name,
          type
        )
      \`)
      .eq("user_id", user.id)
      .order("overall_efficacy_score", { ascending: false })
      .limit(5);

    if (topError) {
      console.error("Failed to fetch top exercises:", topError);
    }

    // Fetch recent sessions
    const { data: recentSessions, error: sessionsError } = await supabaseClient
      .from("intervention_efficacy")
      .select(\`
        *,
        exercises:exercise_id (
          name
        )
      \`)
      .eq("user_id", user.id)
      .order("completed_at", { ascending: false })
      .limit(10);

    if (sessionsError) {
      console.error("Failed to fetch recent sessions:", sessionsError);
    }

    // Calculate insights
    const insights: string[] = [];
    let totalBreakthroughs = 0;
    let averageEfficacy = 0;
    let mostEffectiveContext = "";

    if (recentSessions && recentSessions.length > 0) {
      totalBreakthroughs = recentSessions.filter((s: any) => s.breakthrough_detected).length;
      averageEfficacy = recentSessions.reduce((sum: number, s: any) => sum + s.efficacy_score, 0) / recentSessions.length;

      // Find most effective context (time of day with highest avg efficacy)
      const efficacyByTime: Record<string, number[]> = {};
      recentSessions.forEach((s: any) => {
        if (!efficacyByTime[s.time_of_day]) {
          efficacyByTime[s.time_of_day] = [];
        }
        efficacyByTime[s.time_of_day].push(s.efficacy_score);
      });

      let maxAvg = 0;
      Object.entries(efficacyByTime).forEach(([time, scores]) => {
        const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
        if (avg > maxAvg) {
          maxAvg = avg;
          mostEffectiveContext = time;
        }
      });

      // Generate insight messages
      if (totalBreakthroughs > 0) {
        insights.push(\`You've had \${totalBreakthroughs} breakthrough moment\${totalBreakthroughs > 1 ? 's' : ''} recently\`);
      }

      if (mostEffectiveContext && efficacyByTime[mostEffectiveContext].length >= 3) {
        insights.push(\`Exercises work better for you in the \${mostEffectiveContext}\`);
      }

      if (topExercises && topExercises.length > 0 && topExercises[0].trend === 'improving') {
        insights.push(\`Your efficacy with \${(topExercises[0].exercises as any).name} is improving over time\`);
      }
    }

    return new Response(
      JSON.stringify({
        topExercises: topExercises?.map((profile: any) => ({
          exerciseId: profile.exercise_id,
          exerciseName: (profile.exercises as any).name,
          efficacyScore: profile.overall_efficacy_score,
          completionCount: profile.completion_count,
          bestContext: profile.best_context,
          trend: profile.trend,
        })) || [],
        recentSessions: recentSessions?.map((session: any) => ({
          sessionId: session.session_id,
          exerciseId: session.exercise_id,
          exerciseName: (session.exercises as any).name,
          completedAt: session.completed_at,
          efficacyScore: session.efficacy_score,
          netChange: session.net_emotional_change,
          breakthroughDetected: session.breakthrough_detected,
        })) || [],
        insights: {
          totalBreakthroughs,
          averageEfficacy: Math.round(averageEfficacy * 10) / 10,
          mostEffectiveContext,
          messages: insights,
        },
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in get-efficacy-dashboard:", error);
    return new Response(
      JSON.stringify({
        error: "DASHBOARD_FAILED",
        message: error.message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
