// ============================================================================
// Create Organization (B2B)
// Creates an organization record and returns Stripe metadata placeholder
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { authenticateRequest, errorResponse } from "../_shared/auth.ts";

interface CreateOrganizationRequest {
  name: string;
  adminEmail: string;
  seatCount: number;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as CreateOrganizationRequest;

    if (!body?.name || !body?.adminEmail || !body?.seatCount) {
      return errorResponse(
        "VALIDATION_ERROR",
        "Missing required fields",
        400,
        corsHeaders,
      );
    }

    // Validate seat count limits
    const MAX_SEATS = 100;
    if (body.seatCount < 1 || body.seatCount > MAX_SEATS) {
      return errorResponse(
        "VALIDATION_ERROR",
        `Seat count must be between 1 and ${MAX_SEATS}`,
        400,
        corsHeaders,
      );
    }

    // Validate name length
    if (body.name.length < 2 || body.name.length > 255) {
      return errorResponse(
        "VALIDATION_ERROR",
        "Organization name must be 2-255 characters",
        400,
        corsHeaders,
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Use shared auth utility for consistent security
    const auth = await authenticateRequest(req);

    // Type guard: check if result is an AuthError
    if ("response" in auth) {
      return auth.response;
    }

    const user = auth.user;

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
      return new Response(
        JSON.stringify({ error: "Failed to create organization" }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({
        stripeCustomerId:
          organization.stripe_customer_id ?? "test_stripe_customer",
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
