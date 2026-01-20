// POST /functions/v1/couples/couples-sessions
// Start a new couples exercise session

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  getPartnerId,
  userHasPremiumAccess,
} from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";

serve(async (req) => {
  try {
    // Only accept POST method
    if (req.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("Missing required environment variables");
      return CouplesErrors.unexpectedError(new Error("Server configuration error"));
    }

    // Initialize Supabase client with service role
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

    // Parse request body
    let body;
    try {
      body = await req.json();
    } catch {
      return CouplesErrors.invalidJson();
    }

    const { exerciseId } = body;

    // Validate exerciseId is provided
    if (!exerciseId || typeof exerciseId !== "string") {
      return CouplesErrors.missingField("exerciseId");
    }

    // Get partner ID
    let partnerId: string | null;
    try {
      partnerId = await getPartnerId(supabase, userId);
    } catch (error) {
      console.error("Error getting partner ID:", error);
      return CouplesErrors.databaseError(error as Error);
    }

    if (!partnerId) {
      return CouplesErrors.notPartner();
    }

    // Fetch exercise by ID
    const { data: exercise, error: exerciseError } = await supabase
      .from("couples_exercises")
      .select("*")
      .eq("id", exerciseId)
      .maybeSingle();

    if (exerciseError) {
      console.error("Failed to fetch exercise:", exerciseError);
      return CouplesErrors.databaseError(exerciseError);
    }

    if (!exercise) {
      return CouplesErrors.exerciseNotFound();
    }

    // Check if exercise requires premium and user has premium access
    if (exercise.requires_premium) {
      let hasPremium: boolean;
      try {
        hasPremium = await userHasPremiumAccess(supabase, userId);
      } catch (error) {
        console.error("Error checking premium access:", error);
        return CouplesErrors.databaseError(error as Error);
      }

      if (!hasPremium) {
        return CouplesErrors.premiumRequired();
      }
    }

    // Check if user already has an active session
    const { data: activeSessions } = await supabase
      .from("couples_exercise_sessions")
      .select("id")
      .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
      .in("status", ["pending", "in_progress"]);

    if (activeSessions && activeSessions.length > 0) {
      return CouplesErrors.invalidFieldValue(
        "session",
        "You already have an active session. Complete or abandon it first.",
      );
    }

    // Fetch active partner link
    const { data: partnerLink, error: partnerLinkError } = await supabase
      .from("partner_links")
      .select("id, user_id_1, user_id_2")
      .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
      .eq("status", "active")
      .single();

    if (partnerLinkError || !partnerLink) {
      return CouplesErrors.notPartner();
    }

    // Insert new exercise session with partner_link_id
    // Note: Unique constraint on (partner_link_id, status='pending') prevents duplicates
    const expiresAt = new Date(Date.now() + 24 * 3600 * 1000); // 24 hours from now

    const { data: session, error: insertError } = await supabase
      .from("couples_exercise_sessions")
      .insert({
        partner_link_id: partnerLink.id,
        exercise_id: exerciseId,
        user_id_1: userId,
        user_id_2: partnerId,
        status: "pending",
        user_1_joined_at: new Date().toISOString(),
        user_2_joined_at: null,
      })
      .select()
      .single();

    if (insertError) {
      // Check if insert failed due to duplicate session (race condition)
      if (insertError.message.includes("duplicate") || insertError.code === "23505") {
        return CouplesErrors.invalidFieldValue(
          "session",
          "Session already exists. You may have a pending session with this partner.",
        );
      }
      console.error("Failed to create exercise session:", insertError);
      return CouplesErrors.databaseError(insertError);
    }

    // Get partner's profile for name
    const { data: partnerProfile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", partnerId)
      .single();

    const partnerName = partnerProfile?.display_name || "Your partner";

    // Return success response
    return formatSuccess(
      {
        sessionId: session.id,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        status: "pending",
        invitedPartnerId: partnerId,
        invitedPartnerName: partnerName,
        expiresAt: expiresAt.toISOString(),
        message: `Invitation sent to ${partnerName}. You'll start when they join.`,
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in couples-sessions:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
