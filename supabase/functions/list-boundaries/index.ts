// Boundary & Needs Planner: List Boundaries
// Endpoint: GET /functions/v1/list-boundaries?status=all&limit=20&offset=0
// Lists all boundaries for the authenticated user with filtering and pagination

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
    const status = url.searchParams.get("status") || "all";
    const limit = parseInt(url.searchParams.get("limit") || "20");
    const offset = parseInt(url.searchParams.get("offset") || "0");

    // Build query
    let query = supabase
      .from("defined_boundaries")
      .select("*", { count: "exact" })
      .eq("user_id", user.id);

    // Apply status filter
    if (status !== "all") {
      query = query.eq("status", status);
    } else {
      // Exclude archived by default when showing "all"
      query = query.neq("status", "archived");
    }

    // Order by created_at descending (most recent first)
    query = query.order("created_at", { ascending: false });

    // Apply pagination
    query = query.range(offset, offset + limit - 1);

    // Execute query
    const { data: boundaries, count, error: fetchError } = await query;

    if (fetchError) {
      console.error("Database query error:", fetchError);
      return new Response(JSON.stringify({ error: "Database error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // For each boundary, check if it has a pending follow-up
    const boundariesWithFollowUp = await Promise.all(
      (boundaries || []).map(async (boundary) => {
        const { count: followUpCount } = await supabase
          .from("boundary_follow_ups")
          .select("*", { count: "exact", head: true })
          .eq("boundary_id", boundary.id)
          .is("completed_at", null);

        return {
          id: boundary.id,
          boundaryType: boundary.boundary_type,
          statementText: boundary.statement_text,
          status: boundary.status,
          practiceCount: boundary.practice_count,
          createdAt: boundary.created_at,
          updatedAt: boundary.updated_at,
          hasFollowUp: (followUpCount || 0) > 0,
        };
      }),
    );

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        boundaries: boundariesWithFollowUp,
        total: count || 0,
        limit,
        offset,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error listing boundaries:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
