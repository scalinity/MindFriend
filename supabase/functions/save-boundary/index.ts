// Boundary & Needs Planner: Save Boundary
// Endpoint: POST /functions/v1/save-boundary
// Updates boundary status with state machine validation

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

// Types
interface SaveBoundaryRequest {
  boundaryId: string;
  status: "draft" | "ready" | "practiced" | "set" | "adjusted" | "archived";
}

interface Boundary {
  id: string;
  status: string;
  scripts: any;
  practice_count: number;
  statement_text: string;
}

/**
 * Validate state transition according to state machine rules
 * See formal spec section 6.1 for complete state machine definition
 */
function validateTransition(
  currentStatus: string,
  newStatus: string,
  boundary: any,
): { valid: boolean; error?: string; allowedStates?: string[] } {
  // Allow archiving from any state
  if (newStatus === "archived") {
    return { valid: true };
  }

  // Draft → Ready: requires scripts
  if (currentStatus === "draft" && newStatus === "ready") {
    if (!boundary.scripts || boundary.scripts.length === 0) {
      return {
        valid: false,
        error: "Cannot transition to 'ready' without scripts",
        allowedStates: ["draft", "archived"],
      };
    }
    return { valid: true };
  }

  // Ready → Practiced: requires practice_count >= 3
  if (currentStatus === "ready" && newStatus === "practiced") {
    if (boundary.practice_count < 3) {
      return {
        valid: false,
        error: "Boundary must be practiced at least 3 times",
        allowedStates: ["ready", "archived"],
      };
    }
    return { valid: true };
  }

  // Practiced → Set: always allowed (user action)
  if (currentStatus === "practiced" && newStatus === "set") {
    return { valid: true };
  }

  // Set → Adjusted: always allowed (user edits)
  if (currentStatus === "set" && newStatus === "adjusted") {
    return { valid: true };
  }

  // Adjusted → Set: always allowed (user re-sets)
  if (currentStatus === "adjusted" && newStatus === "set") {
    return { valid: true };
  }

  // No backward transitions allowed (except adjusted → set)
  // All other transitions are invalid
  const allowedFromCurrent: Record<string, string[]> = {
    draft: ["ready", "archived"],
    ready: ["practiced", "archived"],
    practiced: ["set", "archived"],
    set: ["adjusted", "archived"],
    adjusted: ["set", "archived"],
    archived: [],
  };

  return {
    valid: false,
    error: "Invalid state transition",
    allowedStates: allowedFromCurrent[currentStatus] || [],
  };
}

/**
 * Auto-transition to practiced if conditions are met
 */
function shouldAutoTransitionToPracticed(boundary: Boundary): boolean {
  return boundary.status === "ready" && boundary.practice_count >= 3;
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
    const body: SaveBoundaryRequest = await req.json();

    // Validate request
    if (!body.boundaryId) {
      return new Response(JSON.stringify({ error: "Missing boundaryId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const validStatuses = [
      "draft",
      "ready",
      "practiced",
      "set",
      "adjusted",
      "archived",
    ];
    if (!validStatuses.includes(body.status)) {
      return new Response(JSON.stringify({ error: "Invalid status" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch current boundary
    const { data: boundary, error: fetchError } = await supabase
      .from("defined_boundaries")
      .select("*")
      .eq("id", body.boundaryId)
      .eq("user_id", user.id)
      .single();

    if (fetchError || !boundary) {
      return new Response(JSON.stringify({ error: "Boundary not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const originalStatus = boundary.status;

    // Check if auto-transition is eligible (but don't apply yet)
    const canAutoTransition = shouldAutoTransitionToPracticed(boundary);

    // If user explicitly requests practiced and auto-transition is ready, allow it
    if (canAutoTransition && body.status === "practiced") {
      const { data: updatedBoundary, error: updateError } = await supabase
        .from("defined_boundaries")
        .update({ status: "practiced" })
        .eq("id", body.boundaryId)
        .eq("status", "ready")
        .select()
        .single();

      if (!updateError && updatedBoundary) {
        return new Response(
          JSON.stringify({
            success: true,
            boundary: {
              id: updatedBoundary.id,
              status: updatedBoundary.status,
              updated_at: updatedBoundary.updated_at,
            },
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // Validate transition from ORIGINAL status (not auto-transitioned)
    const validation = validateTransition(originalStatus, body.status, boundary);

    if (!validation.valid) {
      const allowedStates = validation.allowedStates || [];
      if (canAutoTransition && !allowedStates.includes("practiced")) {
        allowedStates.push("practiced");
      }

      return new Response(
        JSON.stringify({
          error: validation.error,
          current: originalStatus,
          requested: body.status,
          allowed: allowedStates,
          autoTransitionAvailable: canAutoTransition,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Apply user-requested transition with defensive WHERE clause
    const { data: updatedBoundary, error: updateError } = await supabase
      .from("defined_boundaries")
      .update({ status: body.status })
      .eq("id", body.boundaryId)
      .eq("status", originalStatus)
      .select()
      .single();

    if (updateError) {
      console.error("Database update error:", updateError);
      return new Response(JSON.stringify({ error: "Database error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        boundary: {
          id: updatedBoundary.id,
          status: updatedBoundary.status,
          updatedAt: updatedBoundary.updated_at,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error saving boundary:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
