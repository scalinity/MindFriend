// ============================================================================
// Create Organization (B2B)
// Creates an organization record and returns Stripe metadata placeholder
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface CreateOrganizationRequest {
  name: string;
  adminEmail: string;
  seatCount: number;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const body = (await req.json()) as CreateOrganizationRequest;

    if (!body?.name || !body?.adminEmail || !body?.seatCount) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: authData, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );

    if (authError || !authData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: organization, error } = await supabase
      .from("organizations")
      .insert({
        name: body.name,
        billing_email: body.adminEmail,
        seat_count: body.seatCount,
        max_seats: body.seatCount,
        plan: "business",
        status: "active",
      })
      .select()
      .single();

    if (error || !organization) {
      return new Response(JSON.stringify({ error: "Failed to create organization" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        stripeCustomerId: organization.stripe_customer_id ?? "test_stripe_customer",
        organization,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Create organization error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
