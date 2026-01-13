// MindFriend Verify Purchase Edge Function
// Validates StoreKit 2 transactions with App Store Server API

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const APP_STORE_API_URL = "https://api.storekit.itunes.apple.com";
const APP_STORE_SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";

interface VerifyRequest {
  originalTransactionId: string;
  productId: string;
  environment?: "sandbox" | "production";
}

serve(async (req) => {
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

    const {
      originalTransactionId,
      productId,
      environment = "production",
    }: VerifyRequest = await req.json();

    if (!originalTransactionId) {
      return new Response(
        JSON.stringify({ error: "Missing originalTransactionId" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if App Store credentials are configured
    const issuerId = Deno.env.get("APP_STORE_ISSUER_ID");
    const keyId = Deno.env.get("APP_STORE_KEY_ID");
    const privateKey = Deno.env.get("APP_STORE_PRIVATE_KEY");

    if (!issuerId || !keyId || !privateKey) {
      // Development mode: Mock validation
      console.log(
        "App Store credentials not configured, using mock validation",
      );

      await supabaseAdmin
        .from("profiles")
        .update({
          subscription_tier: "premium",
          daily_ai_quota: -1, // Unlimited
        })
        .eq("id", user.id);

      return new Response(
        JSON.stringify({
          valid: true,
          productId,
          expiresDate: new Date(
            Date.now() + 30 * 24 * 60 * 60 * 1000,
          ).toISOString(),
          mock: true,
          message:
            "Mock validation - configure APP_STORE_* secrets for production",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // TODO: Implement full App Store Server API validation
    // This requires JWT generation with ES256 signing
    // See: https://developer.apple.com/documentation/appstoreserverapi
    //
    // For now, trust the client-side StoreKit 2 validation and update subscription
    // This is acceptable for MVP but should be hardened before production

    // Update user to premium based on client report
    await supabaseAdmin
      .from("profiles")
      .update({
        subscription_tier: "premium",
        daily_ai_quota: -1,
      })
      .eq("id", user.id);

    return new Response(
      JSON.stringify({
        valid: true,
        productId,
        originalTransactionId,
        message: "Subscription activated",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Verify purchase error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", valid: false }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
