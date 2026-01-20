// Boundary & Needs Planner: Record Outcome
// Endpoint: POST /functions/v1/record-outcome
// Records the outcome of a boundary follow-up check-in

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

// Types
interface RecordOutcomeRequest {
  followUpId: string;
  outcome: "successful" | "partially_successful" | "challenged" | "ignored";
  notes?: string;
  reflection?: string;
  nextAction?: string;
}

/**
 * Generate encouragement message based on outcome
 */
function generateEncouragement(outcome: string): string {
  const encouragementMessages: Record<string, string> = {
    successful:
      "Excellent work! Setting and maintaining this boundary shows great self-awareness and strength.",
    partially_successful:
      "You're making progress! Even partial success is a step forward in honoring your needs.",
    challenged:
      "It's okay that this was challenging. Boundaries take practice, and you're learning what works for you.",
    ignored:
      "We understand this was difficult. Remember, setting boundaries is a process, and it's okay to adjust your approach.",
  };

  return encouragementMessages[outcome] || encouragementMessages.successful;
}

/**
 * Generate suggestions based on outcome
 */
function generateSuggestions(outcome: string): string[] {
  const suggestionsByOutcome: Record<string, string[]> = {
    successful: [
      "Continue reinforcing this boundary",
      "Consider applying this approach to other areas",
      "Share your success story in your journal",
    ],
    partially_successful: [
      "Reflect on what worked and what didn't",
      "Consider adjusting your script for clarity",
      "Practice the conversation again with the Rehearsal Studio",
    ],
    challenged: [
      "Review why the boundary was challenged",
      "Consider using a more assertive approach",
      "Seek support from a trusted friend or therapist",
      "Practice your response to pushback",
    ],
    ignored: [
      "Reassess if this boundary needs to be adjusted",
      "Consider having a follow-up conversation",
      "Explore why the boundary wasn't respected",
      "Reach out for professional support if needed",
    ],
  };

  return suggestionsByOutcome[outcome] || suggestionsByOutcome.successful;
}

/**
 * Determine if boundary status should be updated based on outcome
 */
function shouldAdjustBoundaryStatus(outcome: string): boolean {
  // Challenged or ignored outcomes suggest boundary may need adjustment
  return outcome === "challenged" || outcome === "ignored";
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
    const body: RecordOutcomeRequest = await req.json();

    // Validate request
    if (!body.followUpId) {
      return new Response(JSON.stringify({ error: "Missing followUpId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const validOutcomes = [
      "successful",
      "partially_successful",
      "challenged",
      "ignored",
    ];
    if (!validOutcomes.includes(body.outcome)) {
      return new Response(JSON.stringify({ error: "Invalid outcome" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch follow-up record
    const { data: followUp, error: followUpError } = await supabase
      .from("boundary_follow_ups")
      .select("*, defined_boundaries!inner(*)")
      .eq("id", body.followUpId)
      .single();

    if (followUpError || !followUp) {
      return new Response(JSON.stringify({ error: "Follow-up not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify boundary belongs to user
    const boundary = followUp.defined_boundaries;
    if (boundary.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Update follow-up record
    const { error: updateError } = await supabase
      .from("boundary_follow_ups")
      .update({
        outcome: body.outcome,
        notes: body.notes || null,
        user_reflection: body.reflection || null,
        next_action: body.nextAction || null,
        completed_at: new Date().toISOString(),
      })
      .eq("id", body.followUpId);

    if (updateError) {
      console.error("Error updating follow-up:", updateError);
      return new Response(JSON.stringify({ error: "Database error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Optionally update boundary status based on outcome
    let boundaryStatus = boundary.status;

    if (shouldAdjustBoundaryStatus(body.outcome) && boundary.status === "set") {
      // Suggest adjusting boundary
      const { data: updatedBoundary, error: boundaryUpdateError } =
        await supabase
          .from("defined_boundaries")
          .update({ status: "adjusted" })
          .eq("id", boundary.id)
          .select()
          .single();

      if (!boundaryUpdateError && updatedBoundary) {
        boundaryStatus = updatedBoundary.status;
      }
    }

    // Generate encouragement and suggestions
    const encouragement = generateEncouragement(body.outcome);
    const suggestions = generateSuggestions(body.outcome);

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        boundaryUpdated: {
          id: boundary.id,
          status: boundaryStatus,
        },
        encouragement,
        suggestions,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error recording outcome:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
