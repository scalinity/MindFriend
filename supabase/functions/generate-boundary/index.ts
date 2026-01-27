// Boundary & Needs Planner: Generate Boundary
// Endpoint: POST /functions/v1/generate-boundary
// Creates a defined boundary with initial draft status

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders } from "../_shared/cors.ts";

// Types
interface GenerateBoundaryRequest {
  assessmentId?: string;
  boundaryType: "time" | "emotional" | "digital" | "physical" | "financial";
  statement: string;
  whyMatters: string;
  stakeholder?: string;
}

/**
 * Validate boundary statement (10-500 characters)
 */
function validateStatement(statement: string): string | null {
  if (!statement || statement.trim().length < 10) {
    return "Boundary statement must be at least 10 characters";
  }
  if (statement.length > 500) {
    return "Boundary statement must be less than 500 characters";
  }
  return null;
}

/**
 * Validate whyMatters (10-500 characters)
 */
function validateWhyMatters(whyMatters: string): string | null {
  if (!whyMatters || whyMatters.trim().length < 10) {
    return "Why this matters must be at least 10 characters";
  }
  if (whyMatters.length > 500) {
    return "Why this matters must be less than 500 characters";
  }
  return null;
}

/**
 * Check if user has reached free tier limit (3 boundaries max)
 */
async function checkTierLimit(
  supabase: any,
  userId: string,
): Promise<{ allowed: boolean; count: number }> {
  // Check subscription tier
  const { data: subscription } = await supabase
    .from("subscriptions")
    .select("subscription_tier")
    .eq("user_id", userId)
    .single();

  const tier = subscription?.subscription_tier || "free";

  // Premium users have unlimited boundaries
  if (tier === "premium") {
    return { allowed: true, count: 0 };
  }

  // Count non-archived boundaries for free tier users
  const { count, error } = await supabase
    .from("defined_boundaries")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .neq("status", "archived");

  if (error) {
    console.error("Error counting boundaries:", error);
    // Fail closed - deny access if we can't verify tier
    throw new Error("Unable to verify tier limits. Please try again.");
  }

  const currentCount = count || 0;
  return { allowed: currentCount < 3, count: currentCount };
}

/**
 * Generate expected impact based on boundary type
 */
function generateExpectedImpact(
  boundaryType: string,
  whyMatters: string,
): string {
  const impactTemplates: Record<string, string> = {
    time: "Better work-life balance and more time for yourself",
    emotional:
      "Improved emotional well-being and healthier relationship dynamics",
    digital: "Reduced digital overwhelm and better mental clarity",
    physical: "Greater sense of personal safety and comfort",
    financial: "Improved financial health and reduced stress",
  };

  return impactTemplates[boundaryType] || "Improved well-being and clarity";
}

/**
 * Generate next steps based on boundary type
 */
function generateNextSteps(boundaryType: string): string[] {
  return [
    "Review and refine your boundary statement",
    "Generate scripts for different conversation styles",
    "Practice your boundary with the Conversation Rehearsal Studio",
    "Set a follow-up check-in to track your progress",
  ];
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
    const body: GenerateBoundaryRequest = await req.json();

    // Validate request
    const validTypes = [
      "time",
      "emotional",
      "digital",
      "physical",
      "financial",
    ];
    if (!validTypes.includes(body.boundaryType)) {
      return new Response(JSON.stringify({ error: "Invalid boundary type" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate statement
    const statementError = validateStatement(body.statement);
    if (statementError) {
      return new Response(JSON.stringify({ error: statementError }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate whyMatters
    const whyMattersError = validateWhyMatters(body.whyMatters);
    if (whyMattersError) {
      return new Response(JSON.stringify({ error: whyMattersError }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check tier limit
    const { allowed, count } = await checkTierLimit(supabase, user.id);
    if (!allowed) {
      return new Response(
        JSON.stringify({
          error: "Free tier limit reached (3 boundaries max)",
          currentCount: count,
        }),
        {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate expected impact
    const expectedImpact = generateExpectedImpact(
      body.boundaryType,
      body.whyMatters,
    );

    // Insert boundary into database
    const { data: boundary, error: insertError } = await supabase
      .from("defined_boundaries")
      .insert({
        user_id: user.id,
        needs_assessment_id: body.assessmentId || null,
        boundary_type: body.boundaryType,
        statement_text: body.statement.trim(),
        why_matters: body.whyMatters.trim(),
        stakeholder: body.stakeholder?.trim() || null,
        expected_impact: expectedImpact,
        status: "draft",
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

    // Generate next steps
    const nextSteps = generateNextSteps(body.boundaryType);

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        boundary: {
          id: boundary.id,
          type: boundary.boundary_type,
          statement: boundary.statement_text,
          whyMatters: boundary.why_matters,
          stakeholder: boundary.stakeholder,
          expectedImpact: boundary.expected_impact,
          status: boundary.status,
        },
        nextSteps,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error generating boundary:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
