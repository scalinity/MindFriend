import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  sanitizeInput,
  validateUUID,
  validateIntroductionMessage,
} from "../_shared/validation.ts";

interface RequestMentorshipBody {
  mentor_id: string;
  introduction_message: string;
}

interface MentorshipRequestResponse {
  success: boolean;
  match_id?: string;
  status?: string;
  error?: string;
  message?: string;
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

    // Parse and validate request body
    const body: RequestMentorshipBody = await req.json();
    const { mentor_id, introduction_message } = body;

    // Validate mentor_id is a valid UUID
    if (!validateUUID(mentor_id)) {
      return new Response(
        JSON.stringify({ error: "Invalid mentor_id format" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Validate introduction message
    const messageValidation = validateIntroductionMessage(introduction_message);
    if (!messageValidation.valid) {
      return new Response(
        JSON.stringify({
          error: "Invalid introduction message",
          details: messageValidation.errors,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Prevent self-mentorship
    if (user.id === mentor_id) {
      return new Response(
        JSON.stringify({ error: "Cannot request mentorship from yourself" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if mentor exists and is available
    const { data: mentorProfile, error: mentorError } = await supabase
      .from("mentorship_profiles")
      .select("is_mentor_available, user_id")
      .eq("user_id", mentor_id)
      .single();

    if (mentorError || !mentorProfile) {
      return new Response(
        JSON.stringify({ error: "Mentor not found or profile incomplete" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!mentorProfile.is_mentor_available) {
      return new Response(
        JSON.stringify({
          error: "Mentor is not currently available",
          message: "This mentor is not accepting new mentees at the moment",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if a pending request already exists
    const { data: existingRequest } = await supabase
      .from("mentorship_matches")
      .select("id, status")
      .eq("mentee_id", user.id)
      .eq("mentor_id", mentor_id)
      .eq("status", "pending")
      .single();

    if (existingRequest) {
      return new Response(
        JSON.stringify({
          error: "Request already pending",
          message: "You have already sent a mentorship request to this mentor",
          match_id: existingRequest.id,
        }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }

    // Create mentorship match with pending status
    const { data: match, error: createError } = await supabase
      .from("mentorship_matches")
      .insert({
        mentor_id,
        mentee_id: user.id,
        status: "pending",
        introduction_message: sanitizeInput(introduction_message),
        compatibility_score: null,
        match_reason: null,
        created_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString(), // 72 hours
      })
      .select("id, status, created_at")
      .single();

    if (createError) {
      console.error("Error creating mentorship request:", createError);
      return new Response(
        JSON.stringify({
          error: "Failed to create mentorship request",
          details: createError.message,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Send notification to mentor (via send-notification function)
    try {
      const mentorNotificationResp = await supabase.functions.invoke(
        "send-notification",
        {
          body: {
            user_id: mentor_id,
            title: "New Mentorship Request",
            body: "Someone is interested in being your mentee",
            type: "mentorship_request",
            data: {
              match_id: match.id,
              mentee_id: user.id,
            },
          },
        }
      );

      if (mentorNotificationResp.error) {
        console.error(
          "Error sending notification to mentor:",
          mentorNotificationResp.error
        );
        // Don't fail the request if notification fails
      }
    } catch (notificationError) {
      console.error("Notification service error:", notificationError);
      // Continue - notification is best-effort
    }

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        match_id: match.id,
        status: match.status,
        message:
          "Mentorship request sent! The mentor will review your request within 24 hours.",
        timestamp: match.created_at,
      }),
      {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Unexpected error in request-mentorship:", error);
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
