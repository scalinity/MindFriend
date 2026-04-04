import { getCorsHeaders } from "../_shared/cors.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// ✅ MAINTAINABILITY FIX: Extract validation constants
const MAX_RESPONSES = 50; // Max number of question responses
const MAX_RESPONSE_KEY_LENGTH = 100; // Max question ID length
const MAX_RESPONSE_VALUE_LENGTH = 5000; // Max response length
const MAX_ENCRYPTED_FIELD_LENGTH = 100_000; // Max ~75KB original text (Base64 expands 33%)


interface CheckInRequest {
  userPathwayId: string;
  checkInData: {
    mood: number;
    energy: number;
    notes?: string; // Deprecated - use encryptedNotes
    encryptedNotes?: string; // Base64-encoded encrypted notes
    responses?: Record<string, string>;
  };
  exercisesCompleted?: string[];
  journalEntry?: string; // Deprecated - use encryptedJournalEntry
  encryptedJournalEntry?: string; // Base64-encoded encrypted journal
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);
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

    // ✅ FIX: Wrap auth in try/catch to handle malformed JWT exceptions
    let user;
    try {
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
      const { data, error: authError } =
        await supabaseClient.auth.getUser(token);

      if (authError || !data.user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      user = data.user;
    } catch (authException) {
      // Catch exceptions from malformed JWT or other auth failures
      console.error("Auth exception:", authException);
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

    // ✅ INPUT VALIDATION FIX: Validate responses dictionary
    if (body.checkInData.responses) {
      const responses = body.checkInData.responses;

      const responseCount = Object.keys(responses).length;
      if (responseCount > MAX_RESPONSES) {
        return new Response(
          JSON.stringify({
            error: `Too many responses (max ${MAX_RESPONSES})`,
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      for (const [key, value] of Object.entries(responses)) {
        if (key.length > MAX_RESPONSE_KEY_LENGTH) {
          return new Response(
            JSON.stringify({
              error: `Response key too long (max ${MAX_RESPONSE_KEY_LENGTH} characters)`,
            }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        if (
          typeof value !== "string" ||
          value.length > MAX_RESPONSE_VALUE_LENGTH
        ) {
          return new Response(
            JSON.stringify({
              error: `Response value too long (max ${MAX_RESPONSE_VALUE_LENGTH} characters)`,
            }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // ✅ SECURITY FIX: Validate encrypted field lengths (prevent DoS/storage exhaustion)
    if (
      body.checkInData.encryptedNotes &&
      body.checkInData.encryptedNotes.length > MAX_ENCRYPTED_FIELD_LENGTH
    ) {
      return new Response(
        JSON.stringify({
          error: "Encrypted notes too large (max 75KB)",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (
      body.encryptedJournalEntry &&
      body.encryptedJournalEntry.length > MAX_ENCRYPTED_FIELD_LENGTH
    ) {
      return new Response(
        JSON.stringify({
          error: "Encrypted journal too large (max 75KB)",
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
      return new Response(JSON.stringify({ error: "Pathway is not active" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check for duplicate check-in (only reject if already completed, not just existing)
    const { data: existingCheckIn } = await supabaseClient
      .from("pathway_progress")
      .select("id, check_in_completed")
      .eq("user_pathway_id", body.userPathwayId)
      .eq("day_number", userPathway.current_day)
      .maybeSingle();

    if (existingCheckIn?.check_in_completed) {
      return new Response(
        JSON.stringify({ error: "CHECK_IN_ALREADY_COMPLETED" }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Call stored procedure for atomic check-in (includes: pathway_progress insert, user_pathways update, phase advancement)
    const { data: result, error: checkInError } = await supabaseClient.rpc(
      "submit_pathway_checkin",
      {
        p_user_pathway_id: body.userPathwayId,
        p_check_in_data: body.checkInData,
        p_exercises_completed: body.exercisesCompleted || [],
        p_journal_entry: body.journalEntry || null,
        p_encrypted_journal_entry: body.encryptedJournalEntry || null,
        p_encrypted_notes: body.checkInData.encryptedNotes || null,
      },
    );

    if (checkInError) {
      console.error("Check-in error:", JSON.stringify(checkInError));
      return new Response(
        JSON.stringify({
          error: "Failed to save check-in",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error submitting check-in:", error);
    return new Response(
      JSON.stringify({
        error: "An unexpected error occurred",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
