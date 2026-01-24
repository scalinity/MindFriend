import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface CheckInRequest {
  userPathwayId: string;
  checkInData: {
    mood: number;
    energy: number;
    notes?: string;
    responses?: Record<string, string>;
  };
  exercisesCompleted?: string[];
  journalEntry?: string;
}

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

    const body: CheckInRequest = await req.json();

    // Validate required fields
    if (!body.userPathwayId || !body.checkInData) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate check-in data
    const { mood, energy } = body.checkInData;
    if (
      mood === undefined ||
      energy === undefined ||
      mood < 1 ||
      mood > 10 ||
      energy < 1 ||
      energy > 10
    ) {
      return new Response(
        JSON.stringify({
          error: "Invalid mood or energy values (must be 1-10)",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch user pathway with authorization check
    const { data: userPathway, error: pathwayError } = await supabaseClient
      .from("user_pathways")
      .select("*, pathway:transition_pathways(*)")
      .eq("id", body.userPathwayId)
      .eq("user_id", user.id) // Verify ownership
      .single();

    if (pathwayError || !userPathway) {
      return new Response(JSON.stringify({ error: "User pathway not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (userPathway.status !== "active") {
      return new Response(
        JSON.stringify({ error: "Pathway is not active" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for duplicate check-in
    const { data: existingCheckIn } = await supabaseClient
      .from("pathway_progress")
      .select("id")
      .eq("user_pathway_id", body.userPathwayId)
      .eq("day_number", userPathway.current_day)
      .maybeSingle();

    if (existingCheckIn) {
      return new Response(
        JSON.stringify({ error: "CHECK_IN_ALREADY_COMPLETED" }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Call stored procedure for atomic check-in (includes: pathway_progress insert, user_pathways update, phase advancement)
    const { data: result, error: checkInError } = await supabaseClient
      .rpc("submit_pathway_checkin", {
        p_user_pathway_id: body.userPathwayId,
        p_check_in_data: body.checkInData,
        p_exercises_completed: body.exercisesCompleted || [],
        p_journal_entry: body.journalEntry || null,
      });

    if (checkInError) {
      console.error("Check-in error:", checkInError);
      return new Response(
        JSON.stringify({
          error: "Failed to save check-in",
          details: checkInError.message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify(result),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error submitting check-in:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
