// Boundary & Needs Planner: Create Assessment
// Endpoint: POST /functions/v1/create-assessment
// Creates a new needs assessment and returns top needs + recommendations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

// Types
interface AssessmentRequest {
  assessmentType: "work" | "relationships" | "family" | "friends";
  responses: {
    step1_drain_triggers: string[];
    step2_importance_ratings: Record<string, "high" | "medium" | "low">;
    step3_currently_met: Record<string, "yes" | "sometimes" | "no">;
    step4_priority_needs: string[];
  };
}

interface RecommendedBoundary {
  type: "time" | "emotional" | "digital" | "physical" | "financial";
  suggestion: string;
  priority: "high" | "medium" | "low";
}

// Gap score calculation matrix
const GAP_SCORE_MATRIX: Record<string, Record<string, number>> = {
  high: { no: 9, sometimes: 7, yes: 3 },
  medium: { no: 6, sometimes: 4, yes: 2 },
  low: { no: 3, sometimes: 2, yes: 1 },
};

// Recommended boundaries mapping
const BOUNDARY_RECOMMENDATIONS: Record<
  string,
  Record<string, { type: string; priority: string }>
> = {
  work: {
    personal_time: { type: "time", priority: "high" },
    autonomy: { type: "emotional", priority: "high" },
    respect: { type: "emotional", priority: "medium" },
  },
  relationships: {
    emotional_safety: { type: "emotional", priority: "high" },
    respect: { type: "emotional", priority: "high" },
    personal_space: { type: "physical", priority: "medium" },
  },
  family: {
    personal_time: { type: "time", priority: "high" },
    autonomy: { type: "emotional", priority: "high" },
    boundaries: { type: "physical", priority: "medium" },
  },
  friends: {
    personal_time: { type: "time", priority: "medium" },
    emotional_safety: { type: "emotional", priority: "high" },
    digital_boundaries: { type: "digital", priority: "low" },
  },
};

/**
 * Calculate top needs based on importance and currently met ratings
 */
function calculateTopNeeds(
  importanceRatings: Record<string, string>,
  currentlyMet: Record<string, string>,
): string[] {
  const needsWithScores = Object.keys(importanceRatings).map((need) => {
    const importance = importanceRatings[need];
    const met = currentlyMet[need] || "yes";
    const gapScore = GAP_SCORE_MATRIX[importance]?.[met] || 0;

    return { need, gapScore };
  });

  // Sort by gap score descending, then alphabetically
  needsWithScores.sort((a, b) => {
    if (b.gapScore !== a.gapScore) {
      return b.gapScore - a.gapScore;
    }
    return a.need.localeCompare(b.need);
  });

  // Return top 3 or all with gap_score >= 6
  const topNeeds = needsWithScores
    .filter((item) => item.gapScore >= 6)
    .map((item) => item.need);

  return topNeeds.slice(0, Math.max(3, topNeeds.length));
}

/**
 * Generate boundary recommendations based on assessment type and top needs
 */
function generateRecommendations(
  assessmentType: string,
  topNeeds: string[],
): RecommendedBoundary[] {
  const recommendations: RecommendedBoundary[] = [];
  const typeMap = BOUNDARY_RECOMMENDATIONS[assessmentType] || {};

  for (const need of topNeeds) {
    const recommendation = typeMap[need];
    if (recommendation) {
      recommendations.push({
        type: recommendation.type as any,
        suggestion: `Consider setting a ${recommendation.type} boundary to address ${need}`,
        priority: recommendation.priority as any,
      });
    }
  }

  // Sort by priority (high > medium > low)
  const priorityOrder = { high: 3, medium: 2, low: 1 };
  recommendations.sort(
    (a, b) => priorityOrder[b.priority] - priorityOrder[a.priority],
  );

  return recommendations.slice(0, 3);
}

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

    // Parse request body
    const body: AssessmentRequest = await req.json();

    // Validate request
    const validTypes = ["work", "relationships", "family", "friends"];
    if (!validTypes.includes(body.assessmentType)) {
      return new Response(
        JSON.stringify({ error: "Invalid assessment_type" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!body.responses) {
      return new Response(JSON.stringify({ error: "Missing responses" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Calculate top needs
    const topNeeds = calculateTopNeeds(
      body.responses.step2_importance_ratings,
      body.responses.step3_currently_met,
    );

    // Insert assessment into database
    const { data: assessment, error: insertError } = await supabase
      .from("needs_assessments")
      .insert({
        user_id: user.id,
        assessment_type: body.assessmentType,
        responses: body.responses,
        top_needs: topNeeds,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Database insert error:", insertError);
      return new Response(JSON.stringify({ error: "Database error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Generate recommendations
    const recommendedBoundaries = generateRecommendations(
      body.assessmentType,
      topNeeds,
    );

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        assessmentId: assessment.id,
        topNeeds,
        recommendedBoundaries,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error creating assessment:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
