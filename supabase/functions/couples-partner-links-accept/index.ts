// POST /functions/v1/couples/partner-links-accept
// Accept a pending partner invite using invite code

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sha256Hash } from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";
import {
  tooManyFailedAttempts,
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

    // Parse request body
    let body;
    try {
      body = await req.json();
    } catch {
      return CouplesErrors.invalidJson();
    }

    const { inviteCode } = body;

    // Validate invite code is provided
    if (!inviteCode || typeof inviteCode !== "string") {
      return CouplesErrors.missingField("inviteCode");
    }

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

    // Check rate limit for failed attempts (5/minute)
    const tooManyAttempts = await tooManyFailedAttempts(supabase, userId);
    if (tooManyAttempts) {
      return CouplesErrors.tooManyFailedAttempts();
    }

    // Hash the invite code
    const inviteCodeHash = await sha256Hash(inviteCode);

    // Find partner_link by invite_code_hash
    const { data: partnerLink, error: fetchError } = await supabase
      .from("partner_links")
      .select("*")
      .eq("invite_code_hash", inviteCodeHash)
      .eq("status", "pending")
      .maybeSingle();

    if (fetchError) {
      console.error("Failed to fetch partner link:", fetchError);
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.databaseError(fetchError);
    }

    if (!partnerLink) {
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.partnerLinkNotFound();
    }

    // Validate not expired
    const expiresAt = new Date(partnerLink.expires_at);
    if (expiresAt < new Date()) {
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.inviteExpired();
    }

    // Validate not already accepted
    if (partnerLink.user_id_2 !== null) {
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.inviteAlreadyAccepted();
    }

    // Validate not self-invite
    if (partnerLink.user_id_1 === userId) {
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.invalidFieldValue(
        "inviteCode",
        "You cannot partner with yourself",
      );
    }

    // Update partner_link to accept the invite
    const { data: updatedLink, error: updateError } = await supabase
      .from("partner_links")
      .update({
        user_id_2: userId,
        status: "active",
        activated_at: new Date().toISOString(),
      })
      .eq("id", partnerLink.id)
      .eq("status", "pending") // Only update if still pending
      .is("user_id_2", null) // Only update if no user_id_2 yet
      .select()
      .maybeSingle();

    if (updateError) {
      console.error("Failed to update partner link:", updateError);
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.databaseError(updateError);
    }

    if (!updatedLink) {
      // Another request already accepted this invite
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      return CouplesErrors.inviteAlreadyAccepted();
    }

    // Get partner's profile for name
    const { data: partnerProfile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", partnerLink.user_id_1)
      .single();

    const partnerName = partnerProfile?.display_name || "Your partner";

    // Return success response
    return formatSuccess(
      {
        partnerLinkId: updatedLink.id,
        partnerId: partnerLink.user_id_1,
        partnerName,
        status: "active",
        activatedAt: updatedLink.activated_at,
        message:
          "Partnership activated! You can now share moods and exercises.",
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in partner-links/accept:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
