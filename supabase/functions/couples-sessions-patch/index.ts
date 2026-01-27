// PATCH /functions/v1/couples/couples-sessions-patch/{id}
// Update exercise session (join, rate, add notes, abandon)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { COUPLES_MODE_CONSTANTS } from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";
import { sendPartnerNotification } from "../_shared/couples-notifications.ts";

serve(async (req) => {
  try {
    // Only accept PATCH method
    if (req.method !== "PATCH") {
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

    // Parse request body
    let body;
    try {
      body = await req.json();
    } catch {
      return CouplesErrors.invalidJson();
    }

    const { action, rating, notes } = body;

    // Validate action is provided
    if (!action || typeof action !== "string") {
      return CouplesErrors.missingField("action");
    }

    // Validate action is valid
    if (!["join", "rate", "notes", "abandon"].includes(action)) {
      return CouplesErrors.invalidFieldValue(
        "action",
        "must be one of: join, rate, notes, abandon",
      );
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

    // Determine which user is making the request
    const isUser1 = session.user_id_1 === userId;

    // Prepare update fields
    const updateFields: Record<string, any> = {};

    // Handle each action
    switch (action) {
      case "join":
        // Validate state: can only join if session is pending and user hasn't joined yet
        if (session.status !== "pending") {
          return CouplesErrors.invalidFieldValue(
            "action",
            `Cannot join a session that is ${session.status}. Only pending sessions can be joined.`,
          );
        }
        
        // Only user_2 can join (user_1 already joined when creating session)
        if (isUser1) {
          return CouplesErrors.invalidFieldValue(
            "action",
            "Session creator has already joined",
          );
        }
        
        if (session.user_2_joined_at !== null) {
          return CouplesErrors.invalidFieldValue(
            "action",
            "You have already joined this session",
          );
        }
        
        updateFields.user_2_joined_at = new Date().toISOString();
        updateFields.status = "in_progress";
        break;

      case "rate":
        // Validate state: can only rate if session is in_progress or pending (joined)
        if (session.status === "abandoned" || session.status === "completed") {
          return CouplesErrors.invalidFieldValue(
            "action",
            `Cannot rate a ${session.status} session.`,
          );
        }
        
        // Validate that both users have joined before allowing rating
        if (session.user_1_joined_at === null || session.user_2_joined_at === null) {
          return CouplesErrors.invalidFieldValue(
            "action",
            "Both partners must join the session before rating.",
          );
        }
        
        // Check if user already rated
        const userAlreadyRated = isUser1 ? session.user_1_rating !== null : session.user_2_rating !== null;
        if (userAlreadyRated) {
          return CouplesErrors.invalidFieldValue(
            "action",
            "You have already rated this session.",
          );
        }
        
        // Validate rating is provided and is a number
        if (rating === undefined || typeof rating !== "number") {
          return CouplesErrors.missingField("rating");
        }

        // Validate rating is between 1 and 10
        if (
          rating < COUPLES_MODE_CONSTANTS.SESSION_RATING_MIN ||
          rating > COUPLES_MODE_CONSTANTS.SESSION_RATING_MAX
        ) {
          return CouplesErrors.invalidFieldValue(
            "rating",
            `must be between ${COUPLES_MODE_CONSTANTS.SESSION_RATING_MIN} and ${COUPLES_MODE_CONSTANTS.SESSION_RATING_MAX}`,
          );
        }

        // Set rating for the user
        if (isUser1) {
          updateFields.user_1_rating = rating;
        } else {
          updateFields.user_2_rating = rating;
        }

        // Check if both users have now rated
        const user1Rating = isUser1 ? rating : session.user_1_rating;
        const user2Rating = isUser1 ? session.user_2_rating : rating;

        if (user1Rating !== null && user2Rating !== null) {
          updateFields.status = "completed";
          updateFields.completed_at = new Date().toISOString();
        }
        break;

      case "notes":
        // Validate state: can add notes to any non-abandoned session
        if (session.status === "abandoned") {
          return CouplesErrors.invalidFieldValue(
            "action",
            "Cannot add notes to an abandoned session.",
          );
        }
        
        // Validate notes is provided
        if (!notes || typeof notes !== "string") {
          return CouplesErrors.missingField("notes");
        }

        // Set notes for the user
        if (isUser1) {
          updateFields.user_1_notes = notes;
        } else {
          updateFields.user_2_notes = notes;
        }
        break;

      case "abandon":
        // Validate state: cannot abandon already completed or abandoned sessions
        if (session.status === "completed") {
          return CouplesErrors.invalidFieldValue(
            "action",
            "Cannot abandon a completed session.",
          );
        }
        
        if (session.status === "abandoned") {
          return CouplesErrors.invalidFieldValue(
            "action",
            "This session has already been abandoned.",
          );
        }
        
        updateFields.status = "abandoned";
        break;
    }

    // Update session in database
    const { data: updatedSession, error: updateError } = await supabase
      .from("couples_exercise_sessions")
      .update(updateFields)
      .eq("id", sessionId)
      .select()
      .single();

    if (updateError) {
      console.error("Failed to update session:", updateError);
      return CouplesErrors.databaseError(updateError);
    }

    // Send notification to partner based on action and state change
    const partnerId = isUser1 ? session.user_id_2 : session.user_id_1;
    if (partnerId) {
      try {
        if (action === "join") {
          await sendPartnerNotification(supabase, {
            recipientUserId: partnerId,
            type: "exercise_session_started",
            data: {
              sessionId: updatedSession.id,
              exerciseId: updatedSession.exercise_id,
            },
          });
        } else if (action === "rate" && updatedSession.status === "completed") {
          // Notify partner when session is completed (both have rated)
          await sendPartnerNotification(supabase, {
            recipientUserId: partnerId,
            type: "exercise_session_completed",
            data: {
              sessionId: updatedSession.id,
              exerciseId: updatedSession.exercise_id,
            },
          });
        }
        // Note: No notification for abandon - user will see in app
      } catch (notificationError) {
        // Log notification error but don't fail the session update
        console.error("Failed to send notification:", notificationError);
      }
    }

    // Return success with updated session details
    return formatSuccess(
      {
        sessionId: updatedSession.id,
        status: updatedSession.status,
        user1Rating: updatedSession.user_1_rating,
        user2Rating: updatedSession.user_2_rating,
        user1Notes: updatedSession.user_1_notes,
        user2Notes: updatedSession.user_2_notes,
        completedAt: updatedSession.completed_at,
        message: getActionMessage(
          action,
          updatedSession.status,
          updatedSession.user_1_rating,
          updatedSession.user_2_rating,
        ),
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in couples-sessions-patch:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});

/**
 * Get appropriate message based on action and session state
 */
function getActionMessage(
  action: string,
  status: string,
  user1Rating: number | null,
  user2Rating: number | null,
): string {
  switch (action) {
    case "join":
      return "You've joined the session. Both partners are now active!";
    case "rate":
      if (status === "completed") {
        return `Session completed! Both partners rated it ${user1Rating}/5 and ${user2Rating}/5.`;
      }
      return "Thank you for rating! Waiting for your partner to rate.";
    case "notes":
      return "Notes saved successfully.";
    case "abandon":
      return "Session has been abandoned.";
    default:
      return "Session updated successfully.";
  }
}
