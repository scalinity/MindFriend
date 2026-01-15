// MindFriend Verify Purchase Edge Function
// Validates StoreKit 2 transactions using Apple's JWS signature verification

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.2.4";
import { getCorsHeaders } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import {
  getPlanDetails,
  isFamilyPlan,
  calculateExpiryDate,
  generateInviteCode,
  isValidProductId,
} from "../_shared/billing-types.ts";

const log = createLogger("verify-purchase");

// Apple's StoreKit JWS verification endpoints
const STOREKIT_JWKS = {
  production: "https://appleid.apple.com/auth/keys",
  sandbox: "https://appleid.apple.com/auth/keys",
} as const;

interface VerifyRequest {
  signedTransaction: string; // StoreKit 2 JWS from Transaction.jwsRepresentation
  environment?: "sandbox" | "production";
  // Legacy fields for backward compatibility during transition (will be removed)
  originalTransactionId?: string;
  productId?: string;
}

// Apple's StoreKit 2 transaction payload structure
interface AppleTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number; // milliseconds since epoch
  originalPurchaseDate: number;
  expiresDate?: number;
  quantity: number;
  type:
    | "Auto-Renewable Subscription"
    | "Non-Consumable"
    | "Consumable"
    | "Non-Renewing Subscription";
  inAppOwnershipType: "PURCHASED" | "FAMILY_SHARED";
  signedDate: number;
  environment: "Production" | "Sandbox";
  transactionReason?: "PURCHASE" | "RENEWAL";
  storefront: string;
  storefrontId: string;
  price?: number;
  currency?: string;
}

interface VerifyResponse {
  valid: boolean;
  productId: string;
  planType: string;
  billingPeriod: string;
  familyId?: string;
  circleId?: string;
  expiresAt?: string;
  message?: string;
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
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const requestBody: VerifyRequest = await req.json();
    const { signedTransaction, environment = "production" } = requestBody;

    // Require signedTransaction for proper JWS verification
    if (!signedTransaction) {
      return new Response(
        JSON.stringify({
          error: "Missing signedTransaction",
          code: "MISSING_SIGNED_TRANSACTION",
          message:
            "Client must send Transaction.jwsRepresentation from StoreKit 2",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Determine environment for JWS verification
    const env: "sandbox" | "production" =
      environment === "sandbox" ? "sandbox" : "production";

    // Verify the JWS signature using Apple's public keys
    let transactionPayload: AppleTransactionPayload;
    try {
      // Create a JWKS client for Apple's keys
      const jwks = createRemoteJWKSet(new URL(STOREKIT_JWKS[env]));

      // Verify the JWS signature
      const { payload } = await jwtVerify(signedTransaction, jwks, {
        // Apple's StoreKit JWS doesn't have standard issuer/audience claims
        // The signature verification itself is the key security check
      });

      transactionPayload = payload as unknown as AppleTransactionPayload;

      log.info("JWS verification successful", {
        transactionId: transactionPayload.transactionId,
        productId: transactionPayload.productId,
        environment: transactionPayload.environment,
      });
    } catch (jwsError) {
      log.error("JWS verification failed", { error: String(jwsError) });
      return new Response(
        JSON.stringify({
          error: "Invalid transaction signature",
          code: "JWS_VERIFICATION_FAILED",
          valid: false,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Extract verified transaction data
    const { productId, originalTransactionId, expiresDate } =
      transactionPayload;

    // Validate product ID from verified payload
    if (!productId || !isValidProductId(productId)) {
      return new Response(
        JSON.stringify({
          error: "Invalid product ID in transaction",
          code: "INVALID_PRODUCT_ID",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Idempotency check - return existing subscription if already processed
    const { data: existingSubscription } = await supabaseAdmin
      .from("subscriptions")
      .select("*")
      .eq("original_transaction_id", originalTransactionId)
      .single();

    if (existingSubscription && existingSubscription.status === "active") {
      // Already processed this transaction
      return new Response(
        JSON.stringify({
          valid: true,
          productId: existingSubscription.product_id,
          planType: existingSubscription.plan_type,
          billingPeriod: existingSubscription.billing_period,
          expiresAt: existingSubscription.expires_at,
          familyId: existingSubscription.family_id,
          message: "Subscription already active (idempotent)",
          idempotent: true,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get plan details from verified product ID
    const planDetails = getPlanDetails(productId);

    // Use expiry from Apple's verified payload, or calculate if not present
    const expiresAt = expiresDate
      ? new Date(expiresDate)
      : calculateExpiryDate(planDetails.billingPeriod);

    let familyId: string | undefined;
    let circleId: string | undefined;

    // Handle family/couples plans
    if (isFamilyPlan(planDetails.planType)) {
      // Check if user already has a family group
      const { data: existingGroup } = await supabaseAdmin
        .from("family_groups")
        .select("id, circle_id")
        .eq("admin_user_id", user.id)
        .single();

      if (existingGroup) {
        // User already has a family group, update it
        familyId = existingGroup.id;
        circleId = existingGroup.circle_id;
      } else {
        // Create new family group with auto-created circle

        // 1. Create the Family Circle
        const circleName =
          planDetails.planType === "couples" ? "Our Circle" : "Family Circle";
        const circleInviteCode = generateInviteCode();

        const { data: newCircle, error: circleError } = await supabaseAdmin
          .from("circles")
          .insert({
            name: circleName,
            description: `Shared circle for your ${planDetails.planType} plan`,
            invite_code: circleInviteCode,
            max_members: planDetails.seatsTotal,
            owner_id: user.id,
          })
          .select()
          .single();

        if (circleError) {
          log.error("Error creating family circle", {
            error: circleError.message,
          });
          // Continue without circle, not a blocking error
        } else {
          circleId = newCircle.id;

          // Add admin to circle
          await supabaseAdmin.from("circle_members").insert({
            circle_id: circleId,
            user_id: user.id,
            role: "owner",
          });
        }

        // 2. Create family group
        const { data: newGroup, error: groupError } = await supabaseAdmin
          .from("family_groups")
          .insert({
            name:
              planDetails.planType === "couples" ? "Our Plan" : "Family Plan",
            admin_user_id: user.id,
            circle_id: circleId,
          })
          .select()
          .single();

        if (groupError) {
          log.error("Error creating family group", {
            error: groupError.message,
          });
          return new Response(
            JSON.stringify({ error: "Failed to create family group" }),
            {
              status: 500,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        familyId = newGroup.id;

        // 3. Add admin as first family member
        await supabaseAdmin.from("family_members").insert({
          family_id: familyId,
          user_id: user.id,
          status: "active",
          joined_at: new Date().toISOString(),
        });
      }
    }

    // Update profile to premium
    await supabaseAdmin
      .from("profiles")
      .update({
        subscription_tier: "premium",
        daily_ai_quota: -1, // Unlimited
        premium_badge: planDetails.badgeCode,
      })
      .eq("id", user.id);

    // Create or update subscription record
    const subscriptionData = {
      user_id: user.id,
      product_id: productId,
      original_transaction_id: originalTransactionId,
      status: "active" as const,
      plan_type: planDetails.planType,
      billing_period: planDetails.billingPeriod,
      family_id: familyId || null,
      is_family_admin: familyId ? true : false,
      seats_used: 1,
      seats_total: planDetails.seatsTotal,
      expires_at: expiresAt.toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { error: subError } = await supabaseAdmin
      .from("subscriptions")
      .upsert(subscriptionData, {
        onConflict: "user_id",
      });

    if (subError) {
      log.error("Error upserting subscription", { error: subError.message });
    }

    // Award premium badge
    const { data: badge } = await supabaseAdmin
      .from("badges")
      .select("id")
      .eq("code", planDetails.badgeCode)
      .single();

    if (badge) {
      await supabaseAdmin.from("user_badges").upsert(
        {
          user_id: user.id,
          badge_id: badge.id,
        },
        { onConflict: "user_id,badge_id" },
      );
    }

    // Award Family Champion badge for family admins
    if (planDetails.planType === "family") {
      const { data: familyBadge } = await supabaseAdmin
        .from("badges")
        .select("id")
        .eq("code", "family_champion")
        .single();

      if (familyBadge) {
        await supabaseAdmin.from("user_badges").upsert(
          {
            user_id: user.id,
            badge_id: familyBadge.id,
          },
          { onConflict: "user_id,badge_id" },
        );
      }
    }

    const response: VerifyResponse = {
      valid: true,
      productId,
      planType: planDetails.planType,
      billingPeriod: planDetails.billingPeriod,
      expiresAt: expiresAt.toISOString(),
      message: "Subscription activated successfully",
    };

    if (familyId) {
      response.familyId = familyId;
    }
    if (circleId) {
      response.circleId = circleId;
    }

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    log.error("Verify purchase error", { error: String(error) });
    return new Response(
      JSON.stringify({ error: "Internal server error", valid: false }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
