import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

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

    // Fetch user pathway
    const { data: userPathway } = await supabaseClient
      .from("user_pathways")
      .select("*, pathway:transition_pathways(*)")
      .eq("id", userPathwayId)
      .eq("user_id", user.id)
      .single();

    if (!userPathway) {
      return new Response(JSON.stringify({ error: "PATHWAY_NOT_FOUND" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check if already on final phase
    if (userPathway.current_phase >= 4) {
      return new Response(JSON.stringify({ error: "ALREADY_FINAL_PHASE" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const newPhase = userPathway.current_phase + 1;

    // Update user pathway
    await supabaseClient
      .from("user_pathways")
      .update({
        current_phase: newPhase,
        updated_at: new Date().toISOString(),
      })
      .eq("id", userPathwayId);

    // Create milestone for phase completion
    const milestoneKey = `phase_${userPathway.current_phase}_complete`;
    await supabaseClient.from("pathway_milestones").insert({
      user_pathway_id: userPathwayId,
      milestone_key: milestoneKey,
      phase_number: userPathway.current_phase,
      celebration_shown: false,
    });

    const phaseName =
      userPathway.pathway.phases.find((p: any) => p.number === newPhase)
        ?.name || `Phase ${newPhase}`;

    return new Response(
      JSON.stringify({
        success: true,
        newPhase,
        phaseName,
        celebration: {
          title: `Phase ${userPathway.current_phase} Complete!`,
          message: `You've completed the ${userPathway.pathway.phases.find((p: any) => p.number === userPathway.current_phase)?.name} phase. Great progress!`,
          milestones: [milestoneKey],
        },
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error advancing phase:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
