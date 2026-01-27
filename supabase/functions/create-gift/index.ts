// MindFriend Create Gift Edge Function
// Handles gift subscription creation via Stripe payment

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import { CommonErrors, ErrorCodes } from "../_shared/errors.ts";

const log = createLogger("create-gift");

interface CreateGiftRequest {
  planId: string;
  recipientEmail: string;
  recipientName: string;
  personalMessage?: string;
  deliveryDate: string; // ISO date
  paymentMethodId?: string;
  durationMonths?: number;
}

interface CreateGiftResponse {
  success: boolean;
  gift?: {
    id: string;
    recipientEmail: string;
    deliveryDate: string;
    redemptionCode: string;
    status: string;
  };
  error?: string;
}

// Generate gift redemption code: MF-XXXX-XXXX-XXXX
function generateRedemptionCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "MF";

  for (let section = 0; section < 3; section++) {
    code += "-";
    for (let i = 0; i < 4; i++) {
      const randomByte = new Uint8Array(1);
      crypto.getRandomValues(randomByte);
      code += chars.charAt(randomByte[0] % chars.length);
    }
  }

  return code;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return CommonErrors.unauthorized(corsHeaders);
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return CommonErrors.invalidToken(corsHeaders);
    }

    const requestBody: CreateGiftRequest = await req.json();
    const {
      planId,
      recipientEmail,
      recipientName,
      personalMessage,
      deliveryDate,
      durationMonths = 12,
    } = requestBody;

    // Validate required fields
    if (!planId || !recipientEmail || !deliveryDate) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Missing required fields: planId, recipientEmail, deliveryDate",
      );
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(recipientEmail)) {
      return CommonErrors.badRequest(corsHeaders, "Invalid recipient email");
    }

    // Validate delivery date is in future
    const deliveryDateTime = new Date(deliveryDate).getTime();
    if (deliveryDateTime < Date.now()) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Delivery date must be in the future",
      );
    }

    // Get plan details
    const { data: plan, error: planError } = await supabaseAdmin
      .from("subscription_plans")
      .select("*")
      .eq("id", planId)
      .single();

    if (planError || !plan) {
      log.error("Plan not found", { planId, error: planError?.message });
      return CommonErrors.notFound(corsHeaders, "Subscription plan");
    }

    // Get user email for purchaser_email
    const { data: authUser } = await supabaseAdmin.auth.admin.getUserById(
      user.id,
    );
    const purchaserEmail = authUser?.user?.email || "unknown@mindfriend.app";

    // Calculate expiry (1 year from creation)
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);

    // Generate redemption code
    const redemptionCode = generateRedemptionCode();

    // Create gift subscription record
    const { data: gift, error: giftError } = await supabaseAdmin
      .from("gift_subscriptions_v2")
      .insert({
        purchaser_user_id: user.id,
        purchaser_email: purchaserEmail,
        plan_id: planId,
        duration_months: durationMonths,
        price_cents: plan.price_cents,
        recipient_email: recipientEmail,
        recipient_name: recipientName || null,
        personal_message: personalMessage || null,
        delivery_date: deliveryDate.split("T")[0], // ISO date only
        redemption_code: redemptionCode,
        status: "pending",
        expires_at: expiresAt.toISOString(),
      })
      .select()
      .single();

    if (giftError) {
      log.error("Failed to create gift subscription", {
        error: giftError.message,
        code: giftError.code,
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to create gift subscription",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Log revenue event for gift purchase
    await supabaseAdmin.from("revenue_events").insert({
      user_id: user.id,
      subscription_id: null,
      event_type: "gift_purchase",
      event_date: new Date().toISOString().split("T")[0],
      amount_cents: plan.price_cents,
      currency: plan.currency || "USD",
      amount_usd_cents: plan.price_cents,
      source: "gift",
      payment_provider: "stripe",
      external_transaction_id: gift.id,
    });

    log.info("Gift subscription created", {
      giftId: gift.id,
      recipientEmail,
      redemptionCode,
      purchaserId: user.id.slice(0, 8),
    });

    const response: CreateGiftResponse = {
      success: true,
      gift: {
        id: gift.id,
        recipientEmail: gift.recipient_email,
        deliveryDate: gift.delivery_date,
        redemptionCode: gift.redemption_code,
        status: gift.status,
      },
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    log.error("Create gift error", { error: String(error) });
    return CommonErrors.internalError(corsHeaders);
  }
});
