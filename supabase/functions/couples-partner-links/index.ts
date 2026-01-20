// POST /functions/v1/couples/partner-links
// Generate a unique invite code to invite a partner

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  generateInviteCode,
  sha256Hash,
  COUPLES_MODE_CONSTANTS,
} from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";
import {
  canSendInvite,
  logRateLimitAttempt,
} from "../_shared/couples-rate-limit.ts";

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

    // Check if user already has active partner
    const { data: existingPartnership } = await supabase
      .from("partner_links")
      .select("id")
      .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
      .eq("status", "active")
      .maybeSingle();

    if (existingPartnership) {
      return CouplesErrors.activePartnershipExists();
    }

    // Check rate limit (3 invites per 24 hours)
    const canSend = await canSendInvite(supabase, userId);
    if (!canSend) {
      return CouplesErrors.tooManyInvites();
    }

    // Generate unique Base58 invite code (8 characters)
    const inviteCode = await generateInviteCode();
    const inviteCodeHash = await sha256Hash(inviteCode);

    // Calculate expiration (72 hours from now)
    const expiresAt = new Date(
      Date.now() + COUPLES_MODE_CONSTANTS.INVITE_EXPIRY_HOURS * 3600 * 1000,
    );

    // Insert into partner_links table
    const { data: partnerLink, error: insertError } = await supabase
      .from("partner_links")
      .insert({
        user_id_1: userId,
        user_id_2: null,
        invite_code_hash: inviteCodeHash,
        created_by: userId,
        status: "pending",
        expires_at: expiresAt.toISOString(),
      })
      .select()
      .single();

    if (insertError) {
      console.error("Failed to insert partner link:", insertError);
      return CouplesErrors.databaseError(insertError);
    }

    // Log rate limit attempt (successful)
    await logRateLimitAttempt(supabase, userId, "invite_code");

    // Construct deep link and web link
    const deepLink = `mindfriend://partner-invite?code=${inviteCode}`;
    const webLink = `https://getmindfriend.app/partner-invite?code=${inviteCode}`;

    // Return success response
    return formatSuccess(
      {
        inviteCode,
        expiresAt: expiresAt.toISOString(),
        deepLink,
        webLink,
        message: "Send this code to your partner to link accounts",
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in partner-links/invite:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
