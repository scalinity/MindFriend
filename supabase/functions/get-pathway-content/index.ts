import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Get user from JWT
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
    } = await supabaseClient.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { userPathwayId } = await req.json();

    if (!userPathwayId) {
      return new Response(JSON.stringify({ error: "Missing userPathwayId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Fetch user pathway with pathway details
    const { data: userPathway, error: pathwayError } = await supabaseClient
      .from("user_pathways")
      .select("*, pathway:transition_pathways(*)")
      .eq("id", userPathwayId)
      .eq("user_id", user.id) // Verify ownership
      .single();

    if (pathwayError || !userPathway) {
      return new Response(JSON.stringify({ error: "PATHWAY_NOT_FOUND" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Get current phase details
    const { data: phase } = await supabaseClient
      .from("pathway_phases")
      .select("*")
      .eq("pathway_id", userPathway.pathway_id)
      .eq("phase_number", userPathway.current_phase)
      .single();

    if (!phase) {
      return new Response(JSON.stringify({ error: "PHASE_NOT_FOUND" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 3. Use denormalized current_phase_day (no calculation needed!)
    const dayInPhase = userPathway.current_phase_day || 1;

    // 4. Get daily theme (fallback if index out of bounds)
    const dailyTheme = phase.daily_themes[dayInPhase - 1] || {
      day: dayInPhase,
      title: `${phase.name} - Day ${dayInPhase}`,
      message: `Continue your journey through ${phase.name}.`,
      focus_area: phase.name.toLowerCase(),
    };

    // 5. Select exercises for this phase
    const exerciseIds = phase.exercises || [];
    const { data: exercises } = await supabaseClient
      .from("exercises")
      .select("*")
      .in("id", exerciseIds)
      .limit(5);

    // 6. Get journal prompt (rotate through available)
    const journalPrompt =
      phase.journal_prompts?.length > 0
        ? phase.journal_prompts[(dayInPhase - 1) % phase.journal_prompts.length]
        : null;

    // 7. Get check-in prompt from database
    const checkInPrompt = await getCheckInPrompt(
      supabaseClient,
      phase.name,
      dayInPhase,
    );

    // 8. Get affirmation from database
    const affirmation = await getAffirmation(
      supabaseClient,
      userPathway.pathway.key,
      phase.name,
    );

    // 9. Check for upcoming milestone
    const upcomingMilestone = findUpcomingMilestone(
      phase.milestones,
      dayInPhase,
      phase.duration_days,
    );

    const content = {
      dayNumber: userPathway.current_day,
      phaseNumber: userPathway.current_phase,
      theme: dailyTheme,
      checkInPrompt,
      exercises: exercises || [],
      journalPrompt,
      affirmation,
      upcomingMilestone,
    };

    return new Response(JSON.stringify(content), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error getting pathway content:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Helper functions

async function getCheckInPrompt(
  supabase: any,
  phaseName: string,
  dayInPhase: number,
): Promise<string> {
  const { data } = await supabase
    .from("pathway_content_templates")
    .select("content")
    .eq("category", "checkin_prompt")
    .eq("phase_name", phaseName)
    .maybeSingle();

  if (!data || !data.content || data.content.length === 0) {
    return "How are you feeling today?";
  }

  return data.content[(dayInPhase - 1) % data.content.length];
}

async function getAffirmation(
  supabase: any,
  pathwayKey: string,
  phaseName: string,
): Promise<string> {
  // Try pathway-specific affirmation first
  const { data: specificData } = await supabase
    .from("pathway_content_templates")
    .select("content")
    .eq("category", "affirmation")
    .eq("phase_name", phaseName)
    .eq("pathway_key", pathwayKey)
    .maybeSingle();

  if (specificData && specificData.content && specificData.content.length > 0) {
    return specificData.content[0];
  }

  // Fall back to default affirmation
  const { data: defaultData } = await supabase
    .from("pathway_content_templates")
    .select("content")
    .eq("category", "affirmation")
    .eq("phase_name", "default")
    .maybeSingle();

  if (defaultData && defaultData.content && defaultData.content.length > 0) {
    return defaultData.content[0];
  }

  return "You are taking important steps toward healing and growth.";
}

function findUpcomingMilestone(
  milestones: any[],
  dayInPhase: number,
  phaseDurationDays: number,
): any | null {
  if (!milestones || milestones.length === 0) return null;

  // Simple milestone logic: check for week completions
  const daysUntilNextWeek = 7 - (dayInPhase % 7);
  if (daysUntilNextWeek <= 3 && daysUntilNextWeek > 0) {
    return {
      key: `week_${Math.ceil(dayInPhase / 7) + 1}`,
      name: `Week ${Math.ceil(dayInPhase / 7) + 1} Complete`,
      daysAway: daysUntilNextWeek,
    };
  }

  return null;
}
