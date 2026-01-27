import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// ✅ MAINTAINABILITY FIX: Extract validation constants
const MAX_PERSONALIZATION_SIZE = 10000; // 10KB max for personalization JSONB
const MAX_SPECIFIC_CONTEXT_LENGTH = 500; // Max context description length
const MAX_SUPPORT_PEOPLE = 10; // Max number of support people
const MAX_SUPPORT_PERSON_NAME_LENGTH = 100; // Max length for each name
const MAX_GOALS = 5; // Max number of goals
const MAX_GOAL_LENGTH = 200; // Max length for each goal

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

    const { pathwayKey, personalization } = await req.json();

    // Validate required fields
    if (!pathwayKey) {
      return new Response(JSON.stringify({ error: "Missing pathwayKey" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate pathwayKey format (should be snake_case identifier)
    if (!/^[a-z_]+$/.test(pathwayKey)) {
      return new Response(JSON.stringify({ error: "Invalid pathwayKey format" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate personalization JSONB size and structure
    if (personalization) {
      const personalizationStr = JSON.stringify(personalization);
      if (personalizationStr.length > MAX_PERSONALIZATION_SIZE) {
        return new Response(
          JSON.stringify({ error: "Personalization data too large (max 10KB)" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Validate personalization structure
      const allowedFields = ["transitionDate", "specificContext", "supportPeople", "goals"];
      const invalidFields = Object.keys(personalization).filter(
        (key) => !allowedFields.includes(key),
      );
      if (invalidFields.length > 0) {
        return new Response(
          JSON.stringify({
            error: `Invalid personalization fields: ${invalidFields.join(", ")}`,
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Validate specificContext length
      if (personalization.specificContext && typeof personalization.specificContext === "string") {
        if (personalization.specificContext.length > MAX_SPECIFIC_CONTEXT_LENGTH) {
          return new Response(
            JSON.stringify({ error: "specificContext too long (max 500 chars)" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }

      // Validate supportPeople array
      if (personalization.supportPeople && Array.isArray(personalization.supportPeople)) {
        if (personalization.supportPeople.length > MAX_SUPPORT_PEOPLE) {
          return new Response(
            JSON.stringify({ error: "Too many supportPeople (max 10)" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        // ✅ INPUT VALIDATION FIX: Validate individual element lengths
        for (const person of personalization.supportPeople) {
          if (typeof person !== "string" || person.length > MAX_SUPPORT_PERSON_NAME_LENGTH) {
            return new Response(
              JSON.stringify({ error: "Support person name too long (max 100 chars)" }),
              {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }
        }
      }

      // Validate goals array
      if (personalization.goals && Array.isArray(personalization.goals)) {
        if (personalization.goals.length > MAX_GOALS) {
          return new Response(
            JSON.stringify({ error: "Too many goals (max 5)" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        // ✅ INPUT VALIDATION FIX: Validate individual element lengths
        for (const goal of personalization.goals) {
          if (typeof goal !== "string" || goal.length > MAX_GOAL_LENGTH) {
            return new Response(
              JSON.stringify({ error: "Goal text too long (max 200 chars)" }),
              {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }
        }
      }
    }

    // 1. Fetch pathway definition
    const { data: pathway, error: pathwayError } = await supabaseClient
      .from("transition_pathways")
      .select("*")
      .eq("key", pathwayKey)
      .single();

    if (pathwayError || !pathway) {
      return new Response(JSON.stringify({ error: "PATHWAY_NOT_FOUND" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Check if premium pathway and user has entitlement
    if (pathway.is_premium) {
      const { data: profile } = await supabaseClient
        .from("profiles")
        .select("subscription_tier")
        .eq("id", user.id)
        .single();

      const hasSubscription = profile?.subscription_tier === "premium";

      if (!hasSubscription) {
        return new Response(
          JSON.stringify({ error: "SUBSCRIPTION_REQUIRED" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // 3. Check for existing active pathway of same type
    const { data: existingPathway } = await supabaseClient
      .from("user_pathways")
      .select("id")
      .eq("user_id", user.id)
      .eq("pathway_id", pathway.id)
      .eq("status", "active")
      .maybeSingle();

    if (existingPathway) {
      return new Response(
        JSON.stringify({
          error: "ALREADY_ENROLLED",
          existingPathwayId: existingPathway.id,
        }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 4. Create user_pathways record
    // Build context content for companion memory
    const contextContent =
      `User is going through: ${pathway.name}. ` +
      `Context: ${personalization?.specificContext || "Not specified"}. ` +
      `Started: ${new Date().toISOString().split("T")[0]}. ` +
      `Goals: ${personalization?.goals?.join(", ") || "Not specified"}.`;

    // Call stored procedure for atomic enrollment (includes: user_pathways, companion_memory, profiles, pathway_progress)
    const { data: enrollmentResult, error: enrollError } = await supabaseClient
      .rpc("enroll_user_in_pathway", {
        p_user_id: user.id,
        p_pathway_id: pathway.id,
        p_personalization: personalization || {},
        p_context_content: contextContent,
      });

    if (enrollError) {
      console.error("Enrollment error:", enrollError);
      // ✅ SECURITY FIX: Don't expose internal error details
      return new Response(
        JSON.stringify({
          error: "ENROLLMENT_FAILED",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const userPathwayId = enrollmentResult.user_pathway_id;

    // Fetch the created user pathway with pathway details
    const { data: userPathway } = await supabaseClient
      .from("user_pathways")
      .select("*, pathway:transition_pathways(*)")
      .eq("id", userPathwayId)
      .single();

    // Get Phase 1 details for today's content
    const { data: phase1 } = await supabaseClient
      .from("pathway_phases")
      .select("*")
      .eq("pathway_id", pathway.id)
      .eq("phase_number", 1)
      .single();

    const dailyTheme = phase1?.daily_themes?.[0] || {
      day: 1,
      title: "Welcome",
      message: "Begin your journey",
      focusArea: "introduction",
    };

    // Get exercises for phase 1
    const exerciseIds = phase1?.exercises || [];
    const { data: exercises } = await supabaseClient
      .from("exercises")
      .select("*")
      .in("id", exerciseIds)
      .limit(3);

    const todayContent = {
      dayNumber: 1,
      phaseNumber: 1,
      theme: dailyTheme,
      checkInPrompt: "How are you feeling today?",
      exercises: exercises || [],
      journalPrompt: phase1?.journal_prompts?.[0] || null,
      affirmation:
        "You are taking an important step toward healing and growth.",
      upcomingMilestone: null,
    };

    return new Response(
      JSON.stringify({
        userPathway,
        todayContent,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error enrolling in pathway:", error);
    // ✅ SECURITY FIX: Don't expose internal error details
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
