import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  detectPII,
  sanitizeInput,
  validateUUID,
  validatePagination,
} from "../_shared/validation.ts";

interface MatchResult {
  mentor_id: string;
  mentor_name: string;
  mentor_alias: string;
  expertise_areas: string[];
  availability_hours_week: number;
  languages: string[];
  timezone: string;
  compatibility_score: number;
  match_reasons: string[];
  is_verified: boolean;
}

serve(async (req: Request) => {
  // Only allow POST
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Extract JWT from Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Get user from JWT
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body = await req.json();
    const { limit = 5, offset = 0 } = body;

    // Validate pagination
    const paginationCheck = validatePagination(limit, offset);
    if (!paginationCheck.valid) {
      return new Response(
        JSON.stringify({
          error: "Invalid pagination parameters",
          details: paginationCheck.errors,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Call Supabase function to find matches
    const { data: matches, error: matchError } = await supabase
      .rpc("find_mentor_matches", {
        p_user_id: user.id,
        p_limit: paginationCheck.safeLimit,
        p_offset: paginationCheck.safeOffset,
      });

    if (matchError) {
      console.error("Error finding mentor matches:", matchError);
      return new Response(
        JSON.stringify({
          error: "Failed to find mentor matches",
          details: matchError.message,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Validate and format results
    const formattedMatches: MatchResult[] = (matches || []).map(
      (match: any) => ({
        mentor_id: match.mentor_id,
        mentor_name: sanitizeInput(match.mentor_name || ""),
        mentor_alias: sanitizeInput(match.mentor_alias || ""),
        expertise_areas: (match.expertise_areas || []).map((area: string) =>
          sanitizeInput(area)
        ),
        availability_hours_week: match.availability_hours_week || 0,
        languages: match.languages || [],
        timezone: match.timezone || "UTC",
        compatibility_score: Math.round((match.compatibility_score || 0) * 100) / 100,
        match_reasons: (match.match_reasons || []).map((reason: string) =>
          sanitizeInput(reason)
        ),
        is_verified: match.is_verified || false,
      })
    );

    // Return successful response
    return new Response(
      JSON.stringify({
        success: true,
        matches: formattedMatches,
        count: formattedMatches.length,
        timestamp: new Date().toISOString(),
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Unexpected error in find-mentor-matches:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
