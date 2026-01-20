// Boundary & Needs Planner: Get Assessment
// Endpoint: GET /functions/v1/get-assessment/:assessmentId
// Retrieves a specific needs assessment by ID

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization")!;
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Extract assessment ID from URL
    const url = new URL(req.url);
    const assessmentId = url.pathname.split("/").pop();

    if (!assessmentId) {
      return new Response(JSON.stringify({ error: "Missing assessment ID" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch assessment from database
    const { data: assessment, error: fetchError } = await supabase
      .from("needs_assessments")
      .select("*")
      .eq("id", assessmentId)
      .eq("user_id", user.id)
      .single();

    if (fetchError || !assessment) {
      return new Response(JSON.stringify({ error: "Assessment not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        assessment: {
          id: assessment.id,
          assessmentType: assessment.assessment_type,
          responses: assessment.responses,
          topNeeds: assessment.top_needs,
          createdAt: assessment.created_at,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error fetching assessment:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
