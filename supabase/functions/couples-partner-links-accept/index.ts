// POST /functions/v1/couples/partner-links-accept
// Accept a pending partner invite using invite code

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { sha256Hash } from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";
import {
  tooManyFailedAttempts,
  logRateLimitAttempt,
} from "../_shared/couples-rate-limit.ts";

Deno.serve(async (req) => {
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
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Authenticate user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ") || !authHeader.slice(7).trim()) {
      return CouplesErrors.missingAuth();
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.slice(7));

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

    // Keep the Base58 code case-sensitive and bound before hashing.
    if (!/^[1-9A-HJ-NP-Za-km-z]{8}$/.test(inviteCode)) {
      return CouplesErrors.invalidFieldValue("inviteCode", "Expected an 8-character invitation code");
    }
    if (await tooManyFailedAttempts(supabase, userId)) {
      return CouplesErrors.tooManyFailedAttempts();
    }

    // The transaction rechecks expiry, both accounts' active partnerships and
    // the pending row under locks, then preserves consent when sorting UUIDs.
    const { data: result, error: acceptError } = await supabase.rpc("accept_partner_invite", {
      p_user_id: userId,
      p_invite_code_hash: await sha256Hash(inviteCode),
    });
    if (acceptError || !result) {
      return CouplesErrors.databaseError(acceptError ?? undefined);
    }
    if (!result.success) {
      await logRateLimitAttempt(supabase, userId, "failed_invite_attempt");
      switch (result.code) {
        case "NOT_FOUND": return CouplesErrors.partnerLinkNotFound();
        case "EXPIRED": return CouplesErrors.inviteExpired();
        case "ALREADY_ACCEPTED": return CouplesErrors.inviteAlreadyAccepted();
        case "ACTIVE_PARTNERSHIP": return CouplesErrors.activePartnershipExists();
        case "SELF_INVITE": return CouplesErrors.invalidFieldValue("inviteCode", "You cannot partner with yourself");
        default: return CouplesErrors.unexpectedError();
      }
    }
    const updatedLink = result.partner_link;
    const partnerId = result.partner_id;

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
        partnerLinkId: updatedLink.id,
        partnerId,
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
