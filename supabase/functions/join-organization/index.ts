import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

interface JoinOrganizationRequest {
  inviteCode: string;
}

interface JoinOrganizationResponse {
  success: boolean;
  member?: {
    id: string;
    organization_id: string;
    user_id: string;
    joined_at: string;
  };
  subscription?: {
    tier: string;
    access_source: string;
  };
  error?: string;
  errorCode?: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Validate request method
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing authorization header",
        } as JoinOrganizationResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
    } = await supabase.auth.getUser(token);

    if (!user) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Unauthorized",
        } as JoinOrganizationResponse),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body = (await req.json()) as JoinOrganizationRequest;

    if (!body.inviteCode || typeof body.inviteCode !== "string") {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid invite code format",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const inviteCode = body.inviteCode.trim().toUpperCase();

    // Query invite code from database
    const { data: invite, error: fetchError } = await supabase
      .from("organization_invites")
      .select("*")
      .eq("invite_code", inviteCode)
      .single();

    console.log(`Found invite for code ${inviteCode}:`, JSON.stringify(invite));

    if (fetchError || !invite) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invite code not found",
          errorCode: "INVITE_NOT_FOUND",
        } as JoinOrganizationResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate invite status
    // Check if invite is deactivated
    if (invite.is_active === false) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invite code has been deactivated",
          errorCode: "INVITE_DEACTIVATED",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (invite.expires_at) {
      const expiresAt = new Date(invite.expires_at);
      if (expiresAt < new Date()) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Invite code has expired",
            errorCode: "INVITE_EXPIRED",
          } as JoinOrganizationResponse),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (invite.max_uses !== null && invite.uses_count >= invite.max_uses) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invite code has reached maximum uses",
          errorCode: "MAX_USES_EXCEEDED",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const organizationId = invite.organization_id;

    // Check if user is already a member of this organization
    const { data: existingMember } = await supabase
      .from("organization_members")
      .select("*")
      .eq("organization_id", organizationId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (existingMember) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "You are already a member of this organization",
          errorCode: "ALREADY_MEMBER",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check seat capacity
    const { data: organization, error: orgError } = await supabase
      .from("organizations")
      .select("seat_count, seats_used")
      .eq("id", organizationId)
      .single();

    if (orgError || !organization) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Organization not found",
          errorCode: "ORG_NOT_FOUND",
        } as JoinOrganizationResponse),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(
      `Checking capacity for org ${organizationId}: seats_used=${organization.seats_used}, seat_count=${organization.seat_count}`,
    );

    const isAtCapacity = organization.seats_used >= organization.seat_count;
    console.log(`isAtCapacity: ${isAtCapacity}`);

    if (isAtCapacity) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Organization has reached seat capacity",
          errorCode: "SEAT_LIMIT_REACHED",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Increment invite uses
    const { error: updateInviteError } = await supabase
      .from("organization_invites")
      .update({ uses_count: (invite.uses_count || 0) + 1 })
      .eq("invite_code", inviteCode);

    if (updateInviteError) {
      console.error("Error incrementing invite uses:", updateInviteError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to process invite",
          errorCode: "UPDATE_FAILED",
        } as JoinOrganizationResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Increment seats_used counter (non-atomic for now due to PostgREST limitation)
    const { error: seatsError } = await supabase
      .from("organizations")
      .update({ seats_used: organization.seats_used + 1 })
      .eq("id", organizationId);

    if (seatsError) {
      console.error("Error incrementing seats_used:", seatsError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to update organization seats",
          errorCode: "UPDATE_FAILED",
        } as JoinOrganizationResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create member record
    const now = new Date().toISOString();
    const { data: member, error: memberError } = await supabase
      .from("organization_members")
      .insert({
        organization_id: organizationId,
        user_id: user.id,
        joined_at: now,
        is_active: true,
      })
      .select()
      .single();

    if (memberError || !member) {
      console.error("Error creating organization member:", memberError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to add you as member",
        } as JoinOrganizationResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Grant premium subscription via organization sponsorship
    const { data: subscription, error: subscriptionError } = await supabase
      .from("subscriptions")
      .upsert({
        user_id: user.id,
        plan_type: "organization",
        status: "active",
        access_source: "organization_sponsored",
        organization_id: organizationId,
        product_id: "org_sponsored_premium",
        original_transaction_id: `org_${organizationId}_${user.id}`,
        expires_at: null, // Sponsored memberships don't expire as long as they're in the org
      }, { onConflict: "user_id" })
      .select()
      .single();

    if (subscriptionError) {
      console.error("Error granting premium subscription:", subscriptionError);
      // Rollback: delete member, decrement seats
      await supabase.from("organization_members").delete().eq("id", member.id);
      await supabase
        .from("organizations")
        .update({ seats_used: organization.seats_used })
        .eq("id", organizationId);

      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to grant premium subscription",
          debugError: subscriptionError,
        } as JoinOrganizationResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create audit log entries
    const { error: auditError } = await supabase.from("audit_log").insert({
      organization_id: organizationId,
      event_type: "member_joined",
      actor_id: user.id,
      target_user_id: user.id,
      metadata: {
        invite_code: inviteCode,
        joined_via: "invite_code",
        timestamp: now,
      },
    });

    if (auditError) {
      console.error("Error creating audit log:", auditError);
      // Non-fatal
    }

    // Log to billing audit for Stripe tracking
    const { error: billingError } = await supabase
      .from("billing_audit_log")
      .insert({
        organization_id: organizationId,
        event_type: "member_joined_with_subscription",
        metadata: {
          user_id: user.id,
          subscription_id: subscription?.id,
          invite_code: inviteCode,
          joined_at: now,
        },
      });

    if (billingError) {
      console.error("Error creating billing audit log:", billingError);
      // Non-fatal
    }

    // Success response
    return new Response(
      JSON.stringify({
        success: true,
        member: {
          id: member.id,
          organization_id: member.organization_id,
          user_id: member.user_id,
          joined_at: member.joined_at,
        },
        subscription: subscription
          ? {
              tier: subscription.plan_type,
              access_source: subscription.access_source,
            }
          : undefined,
      } as JoinOrganizationResponse),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Join organization error:", error);
    return new Response(
      JSON.stringify({ success: false, error: "Internal server error", debugError: error }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
