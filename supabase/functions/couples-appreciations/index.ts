// POST /functions/v1/couples/appreciations
// Send an appreciation message to partner

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  getPartnerId,
  COUPLES_MODE_CONSTANTS,
} from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";
import {
  canSendAppreciation,
  logRateLimitAttempt,
} from "../_shared/couples-rate-limit.ts";
import { sendPartnerNotification } from "../_shared/couples-notifications.ts";

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
      return CouplesErrors.unexpectedError(
        new Error("Server configuration error"),
      );
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

    const { message } = body;

    // Validate message is provided
    if (!message || typeof message !== "string") {
      return CouplesErrors.missingField("message");
    }

    // Trim message for validation
    const trimmedMessage = message.trim();

    // Validate message length (min 10, max 500 characters)
    if (trimmedMessage.length < 10) {
      return CouplesErrors.invalidFieldValue(
        "message",
        "must be at least 10 characters",
      );
    }

    if (
      trimmedMessage.length > COUPLES_MODE_CONSTANTS.APPRECIATION_MAX_LENGTH
    ) {
      return CouplesErrors.invalidFieldValue(
        "message",
        `must be under ${COUPLES_MODE_CONSTANTS.APPRECIATION_MAX_LENGTH} characters. Current: ${trimmedMessage.length}`,
      );
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

    // Check rate limit (10 appreciations per 24 hours)
    const canSend = await canSendAppreciation(supabase, userId);
    if (!canSend) {
      return CouplesErrors.tooManyAppreciations();
    }

    // Insert appreciation message
    const { data: appreciation, error: insertError } = await supabase
      .from("appreciations")
      .insert({
        from_user_id: userId,
        to_user_id: partnerId,
        message: trimmedMessage,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Failed to insert appreciation:", insertError);
      return CouplesErrors.databaseError(insertError);
    }

    // Log rate limit attempt (successful)
    await logRateLimitAttempt(supabase, userId, "appreciation");

    // Send push notification to partner (best effort, don't fail if it errors)
    await sendPartnerNotification(supabase, {
      type: "appreciation_received",
      recipientUserId: partnerId,
      senderUserId: userId,
      data: {
        appreciationId: appreciation.id,
        message: trimmedMessage,
      },
    });

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
        messageId: appreciation.id,
        message: appreciation.message,
        sentAt: appreciation.created_at,
        sentTo: partnerName,
        status: "delivered",
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in appreciations POST:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
