// Boundary & Needs Planner: Get Templates
// Endpoint: GET /functions/v1/get-templates?boundaryType=time&relationshipType=manager&locale=en
// Retrieves script templates based on filters

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
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

    // Extract query parameters
    const url = new URL(req.url);
    const boundaryType = url.searchParams.get("boundaryType");
    const relationshipType = url.searchParams.get("relationshipType");
    const locale = url.searchParams.get("locale") || "en";

    // Build query
    let query = supabase.from("boundary_script_templates").select("*");

    // Apply filters if provided
    if (boundaryType) {
      query = query.eq("boundary_type", boundaryType);
    }

    if (relationshipType) {
      query = query.eq("relationship_type", relationshipType);
    }

    query = query.eq("locale", locale);

    // Execute query
    const { data: templates, error: fetchError } = await query;

    if (fetchError) {
      console.error("Database query error:", fetchError);
      return new Response(JSON.stringify({ error: "Database error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        templates:
          templates?.map((t) => ({
            id: t.id,
            variation: t.template_variation,
            templateText: t.template_text,
            toneDescription: t.tone_description,
            exampleContext: t.example_context,
            isPremium: t.is_premium,
          })) || [],
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error fetching templates:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
