// supabase/functions/generate-experiment-report/index.ts
// Generates outcome report for a completed experiment
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface ReportRequest {
  experimentId: string;
}

// UUID v4 format validation
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isValidUUID(value: string): boolean {
  return UUID_REGEX.test(value);
}

interface ExperimentDay {
  day_index: number;
  completed: boolean;
  completed_at: string | null;
  mood_score: number | null;
  energy_score: number | null;
}

interface Experiment {
  id: string;
  user_id: string;
  title: string;
  description: string;
  action_type: string;
  started_at: string;
  ended_at: string | null;
  status: string;
  baseline_mood_avg: number | null;
  baseline_energy_avg: number | null;
}

function generateRecommendation(
  adherenceDays: number,
  moodDelta: number | null,
  _energyDelta: number | null,
  hasBaseline: boolean,
  avgMoodScore: number,
  _avgEnergyScore: number,
): { text: string; nextSteps: string[] } {
  // Rule-based recommendation logic
  if (adherenceDays >= 5) {
    if (hasBaseline && moodDelta !== null) {
      if (moodDelta >= 0.5) {
        return {
          text: "Great results! Your mood improved significantly during this experiment. Consider making this habit permanent.",
          nextSteps: [
            "Continue this practice for another 7 days to solidify the habit",
            "Try combining it with another positive routine",
            "Share your success with your support circle",
          ],
        };
      } else if (moodDelta <= -0.5) {
        return {
          text: "This experiment showed a decline in mood. Consider trying a different approach or adjusting the routine.",
          nextSteps: [
            "Reflect on what aspects felt challenging",
            "Try a modified version of this experiment",
            "Consider a completely different experiment type",
          ],
        };
      } else {
        return {
          text: "No significant change detected. The routine may need more time or adjustment to show effects.",
          nextSteps: [
            "Extend the experiment to 14 days for clearer results",
            "Try adjusting the timing or intensity",
            "Consider combining with mood-boosting activities",
          ],
        };
      }
    } else {
      // Good adherence but no baseline
      return {
        text: `You completed ${adherenceDays} out of 7 days with an average mood of ${avgMoodScore.toFixed(1)}/5. Start logging mood daily to enable baseline comparisons for future experiments.`,
        nextSteps: [
          "Log your mood daily for a week before starting the next experiment",
          "Re-run this experiment with baseline data for meaningful comparison",
          "Track energy levels alongside mood for richer insights",
        ],
      };
    }
  } else if (adherenceDays >= 3) {
    return {
      text: "Experiment partially completed. Consider what barriers prevented full adherence and try again with adjustments.",
      nextSteps: [
        "Identify what made some days harder than others",
        "Set up better reminders or accountability",
        "Start with a simpler, easier-to-maintain routine",
      ],
    };
  } else {
    return {
      text: "Experiment incomplete - less than 3 days completed. Results may not be reliable. Consider trying a simpler routine that fits better into your schedule.",
      nextSteps: [
        "Choose an experiment requiring less time commitment",
        "Start with just 3 days instead of 7",
        "Find an accountability partner",
      ],
    };
  }
}

function generateInsights(
  adherenceDays: number,
  totalDays: number,
  avgMoodScore: number,
  avgEnergyScore: number,
  moodDelta: number | null,
  energyDelta: number | null,
  hasBaseline: boolean,
  days: ExperimentDay[],
): string[] {
  const insights: string[] = [];

  // Adherence insight
  const adherencePercent = Math.round((adherenceDays / totalDays) * 100);
  insights.push(
    `You completed ${adherenceDays} out of ${totalDays} days (${adherencePercent}% adherence)`,
  );

  // Mood insights
  if (hasBaseline && moodDelta !== null) {
    const direction =
      moodDelta > 0
        ? "improved"
        : moodDelta < 0
          ? "decreased"
          : "remained stable";
    const percentChange = Math.abs(Math.round(moodDelta * 20)); // Convert to percentage of 5-point scale
    insights.push(
      `Your mood ${direction} by ${Math.abs(moodDelta).toFixed(1)} points (${percentChange}%) during the experiment`,
    );
  } else {
    insights.push(
      `Average mood during experiment: ${avgMoodScore.toFixed(1)}/5`,
    );
  }

  // Energy insights
  if (hasBaseline && energyDelta !== null) {
    const direction =
      energyDelta > 0
        ? "increased"
        : energyDelta < 0
          ? "decreased"
          : "remained stable";
    insights.push(
      `Your energy ${direction} by ${Math.abs(energyDelta).toFixed(1)} points`,
    );
  } else if (avgEnergyScore > 0) {
    insights.push(
      `Average energy during experiment: ${avgEnergyScore.toFixed(1)}/5`,
    );
  }

  // Pattern insights from completed days
  const completedDays = days.filter(
    (d) => d.completed && d.mood_score !== null,
  );
  if (completedDays.length >= 3) {
    const moods = completedDays.map((d) => d.mood_score!);
    const maxMood = Math.max(...moods);
    const minMood = Math.min(...moods);
    if (maxMood - minMood >= 2) {
      insights.push(
        `Mood varied between ${minMood} and ${maxMood} during the experiment - some days were notably better than others`,
      );
    }
  }

  return insights;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const requestBody: ReportRequest = await req.json();
    const { experimentId } = requestBody;

    if (!experimentId) {
      return new Response(JSON.stringify({ error: "Missing experimentId" }), {
        status: 400,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate UUID format
    if (!isValidUUID(experimentId)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_EXPERIMENT_ID",
          message: "experimentId must be a valid UUID",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify experiment ownership and status
    const { data: experiment, error: expError } = (await supabaseAdmin
      .from("insight_experiments")
      .select("*")
      .eq("id", experimentId)
      .single()) as { data: Experiment | null; error: Error | null };

    if (expError || !experiment) {
      return new Response(
        JSON.stringify({
          error: "EXPERIMENT_NOT_FOUND",
          message: "Experiment not found or you don't have access to it",
        }),
        {
          status: 404,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (experiment.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    if (experiment.status !== "completed") {
      return new Response(
        JSON.stringify({
          error: "EXPERIMENT_NOT_COMPLETED",
          message: `Cannot generate report for ${experiment.status} experiment. Complete all 7 days first.`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get all days
    const { data: days, error: daysError } = (await supabaseAdmin
      .from("insight_experiment_days")
      .select("*")
      .eq("experiment_id", experimentId)
      .order("day_index")) as {
      data: ExperimentDay[] | null;
      error: Error | null;
    };

    if (daysError || !days || days.length === 0) {
      return new Response(
        JSON.stringify({
          error: "NO_DAYS_FOUND",
          message:
            "No experiment days found. This experiment may be corrupted.",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate metrics
    const completedDays = days.filter((d) => d.completed);
    const adherenceDays = completedDays.length;
    const totalDays = days.length;

    // Calculate averages from completed days with scores
    const daysWithMood = completedDays.filter((d) => d.mood_score !== null);
    const daysWithEnergy = completedDays.filter((d) => d.energy_score !== null);

    let avgMoodScore = 0;
    let avgEnergyScore = 0;

    if (daysWithMood.length > 0) {
      const moodSum = daysWithMood.reduce((sum, d) => sum + d.mood_score!, 0);
      avgMoodScore = parseFloat((moodSum / daysWithMood.length).toFixed(2));
    }

    if (daysWithEnergy.length > 0) {
      const energySum = daysWithEnergy.reduce(
        (sum, d) => sum + d.energy_score!,
        0,
      );
      avgEnergyScore = parseFloat(
        (energySum / daysWithEnergy.length).toFixed(2),
      );
    }

    // Calculate deltas
    const hasBaseline =
      experiment.baseline_mood_avg !== null ||
      experiment.baseline_energy_avg !== null;

    let moodDelta: number | null = null;
    let energyDelta: number | null = null;

    if (experiment.baseline_mood_avg !== null && avgMoodScore > 0) {
      moodDelta = parseFloat(
        (avgMoodScore - experiment.baseline_mood_avg).toFixed(2),
      );
    }

    if (experiment.baseline_energy_avg !== null && avgEnergyScore > 0) {
      energyDelta = parseFloat(
        (avgEnergyScore - experiment.baseline_energy_avg).toFixed(2),
      );
    }

    // Generate recommendation and insights
    const recommendation = generateRecommendation(
      adherenceDays,
      moodDelta,
      energyDelta,
      hasBaseline,
      avgMoodScore,
      avgEnergyScore,
    );

    const insights = generateInsights(
      adherenceDays,
      totalDays,
      avgMoodScore,
      avgEnergyScore,
      moodDelta,
      energyDelta,
      hasBaseline,
      days,
    );

    // Format date range
    const startDate = new Date(experiment.started_at);
    const endDate = experiment.ended_at
      ? new Date(experiment.ended_at)
      : new Date();

    return new Response(
      JSON.stringify({
        experimentId: experiment.id,
        title: experiment.title,
        description: experiment.description,
        actionType: experiment.action_type,
        dateRange: {
          start: startDate.toISOString().split("T")[0],
          end: endDate.toISOString().split("T")[0],
        },
        adherence: {
          rate: parseFloat((adherenceDays / totalDays).toFixed(2)),
          completedDays: adherenceDays,
          totalDays,
        },
        moodChange: {
          delta: moodDelta,
          baseline: experiment.baseline_mood_avg,
          experiment: avgMoodScore || null,
          hasBaseline: experiment.baseline_mood_avg !== null,
        },
        energyChange: {
          delta: energyDelta,
          baseline: experiment.baseline_energy_avg,
          experiment: avgEnergyScore || null,
          hasBaseline: experiment.baseline_energy_avg !== null,
        },
        recommendation,
        insights,
        days: days.map((d) => ({
          dayIndex: d.day_index,
          completed: d.completed,
          completedAt: d.completed_at,
          moodScore: d.mood_score,
          energyScore: d.energy_score,
        })),
        generatedAt: new Date().toISOString(),
      }),
      {
        status: 200,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error(
      "Generate report error:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
