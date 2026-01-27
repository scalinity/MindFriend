// GET /functions/v1/couples/couples-sessions-get/{id}
// Get details of a specific exercise session

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";

serve(async (req) => {
  try {
    // Only accept GET method
    if (req.method !== "GET") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("Missing required environment variables");
      return CouplesErrors.unexpectedError(new Error("Server configuration error"));
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: { Authorization: req.headers.get("Authorization")! },
      },
    });

    // Authenticate user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return CouplesErrors.missingAuth();
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return CouplesErrors.missingAuth();
    }

    const userId = user.id;

    // Extract session ID from URL path
    const url = new URL(req.url);
    const pathSegments = url.pathname.split("/");
    const sessionId = pathSegments[pathSegments.length - 1];

    if (!sessionId) {
      return CouplesErrors.missingField("sessionId");
    }

    // Fetch session by ID
    const { data: session, error: sessionError } = await supabase
      .from("couples_exercise_sessions")
      .select("*")
      .eq("id", sessionId)
      .maybeSingle();

    if (sessionError) {
      console.error("Failed to fetch session:", sessionError);
      return CouplesErrors.databaseError(sessionError);
    }

    if (!session) {
      return CouplesErrors.sessionNotFound();
    }

    // Validate user is part of the session
    if (session.user_id_1 !== userId && session.user_id_2 !== userId) {
      return CouplesErrors.accessDenied();
    }

    // Fetch exercise details
    const { data: exercise, error: exerciseError } = await supabase
      .from("couples_exercises")
      .select("*")
      .eq("id", session.exercise_id)
      .single();

    if (exerciseError) {
      console.error("Failed to fetch exercise:", exerciseError);
      return CouplesErrors.databaseError(exerciseError);
    }

    // Determine which user is making the request
    const isUser1 = session.user_id_1 === userId;

    // Return session details
    return formatSuccess(
      {
        sessionId: session.id,
        exerciseName: exercise.name,
        exerciseInstructions: exercise.instructions,
        status: session.status,
        startedAt: session.user_1_joined_at,
        user1Rating: session.user_1_rating,
        user2Rating: session.user_2_rating,
        user1Notes: session.user_1_notes,
        user2Notes: session.user_2_notes,
        completedAt: session.completed_at,
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in couples-sessions-get:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
