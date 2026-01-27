// MindFriend Redeem Gift Edge Function
// Handles gift subscription redemption

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import { CommonErrors } from "../_shared/errors.ts";

const log = createLogger("redeem-gift");

interface RedeemGiftRequest {
  redemptionCode: string;
}

interface RedeemGiftResponse {
  success: boolean;
  subscription?: {
    id: string;
    status: string;
    expiresAt: string;
  };
  giftFrom?: {
    name: string;
    message?: string;
  };
  error?: string;
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

    const requestBody: RedeemGiftRequest = await req.json();
    const { redemptionCode } = requestBody;

    // Validate required field
    if (!redemptionCode) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Missing required field: redemptionCode",
      );
    }

    // Look up gift subscription by redemption code
    const { data: gift, error: giftError } = await supabaseAdmin
      .from("gift_subscriptions_v2")
      .select("*")
      .eq("redemption_code", redemptionCode)
      .single();

    if (giftError || !gift) {
      log.warn("Gift not found", {
        code: redemptionCode,
        error: giftError?.message,
      });
      return CommonErrors.notFound(corsHeaders, "Gift subscription");
    }

    // Validate gift hasn't been redeemed
    if (gift.status === "redeemed") {
      log.warn("Attempted to redeem already-redeemed gift", {
        giftId: gift.id,
        userId: user.id.slice(0, 8),
      });
      return CommonErrors.badRequest(
        corsHeaders,
        "This gift has already been redeemed",
      );
    }

    // Validate gift hasn't expired
    if (gift.expires_at && new Date(gift.expires_at) < new Date()) {
      log.warn("Attempted to redeem expired gift", {
        giftId: gift.id,
        expiresAt: gift.expires_at,
      });
      return CommonErrors.badRequest(corsHeaders, "This gift has expired");
    }

    // Validate recipient email matches logged-in user
    const { data: authUser } = await supabaseAdmin.auth.admin.getUserById(
      user.id,
    );
    const userEmail = authUser?.user?.email;

    if (userEmail !== gift.recipient_email) {
      log.warn("Gift redemption email mismatch", {
        giftId: gift.id,
        expectedEmail: gift.recipient_email,
        attemptedEmail: userEmail,
      });
      return CommonErrors.forbidden(
        corsHeaders,
        "This gift was not sent to your email address",
      );
    }

    // Get plan details
    const { data: plan, error: planError } = await supabaseAdmin
      .from("subscription_plans")
      .select("*")
      .eq("id", gift.plan_id)
      .single();

    if (planError || !plan) {
      log.error("Plan not found for gift redemption", {
        planId: gift.plan_id,
        giftId: gift.id,
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Plan not found",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate subscription expiry based on gift duration
    const now = new Date();
    const expiresAt = new Date(
      now.getTime() + gift.duration_months * 30 * 24 * 60 * 60 * 1000,
    );

    // Create subscription for the user
    const { data: subscription, error: subError } = await supabaseAdmin
      .from("subscriptions")
      .insert({
        user_id: user.id,
        product_id: plan.app_store_product_id || `gift-${plan.id}`,
        status: "active",
        plan_type: plan.plan_type,
        billing_period: plan.billing_period || "custom",
        expires_at: expiresAt.toISOString(),
        seats_used: 1,
        seats_total: plan.max_seats || 1,
      })
      .select()
      .single();

    if (subError) {
      log.error("Failed to create subscription from gift", {
        error: subError.message,
        userId: user.id.slice(0, 8),
        giftId: gift.id,
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to activate subscription",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update gift status to redeemed
    const { error: updateError } = await supabaseAdmin
      .from("gift_subscriptions_v2")
      .update({
        status: "redeemed",
        redeemed_at: new Date().toISOString(),
        redeemed_by_user_id: user.id,
      })
      .eq("id", gift.id);

    if (updateError) {
      log.error("Failed to update gift status", {
        error: updateError.message,
        giftId: gift.id,
      });
    }

    // Update user profile to premium
    await supabaseAdmin
      .from("profiles")
      .update({
        subscription_tier: "premium",
        daily_ai_quota: -1, // Unlimited
      })
      .eq("id", user.id);

    // Log revenue event for gift redeemed
    await supabaseAdmin.from("revenue_events").insert({
      user_id: user.id,
      subscription_id: subscription.id,
      event_type: "gift_redeemed",
      event_date: new Date().toISOString().split("T")[0],
      amount_cents: plan.price_cents,
      currency: plan.currency || "USD",
      amount_usd_cents: plan.price_cents,
      source: "gift",
      payment_provider: "gift",
      external_transaction_id: gift.id,
    });

    log.info("Gift redeemed successfully", {
      giftId: gift.id,
      userId: user.id.slice(0, 8),
      subscriptionId: subscription.id,
      expiresAt: expiresAt.toISOString(),
    });

    const response: RedeemGiftResponse = {
      success: true,
      subscription: {
        id: subscription.id,
        status: subscription.status,
        expiresAt: subscription.expires_at,
      },
      giftFrom: {
        name: gift.recipient_name || "A generous friend",
        message: gift.personal_message || undefined,
      },
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    log.error("Redeem gift error", { error: String(error) });
    return CommonErrors.internalError(corsHeaders);
  }
});
