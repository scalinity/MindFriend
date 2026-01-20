import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  try {
    // Validate request method
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
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
          headers: { "Content-Type": "application/json" },
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
          headers: { "Content-Type": "application/json" },
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
          headers: { "Content-Type": "application/json" },
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

    if (fetchError || !invite) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invite code not found",
          errorCode: "INVITE_NOT_FOUND",
        } as JoinOrganizationResponse),
        {
          status: 404,
          headers: { "Content-Type": "application/json" },
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
          headers: { "Content-Type": "application/json" },
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
            headers: { "Content-Type": "application/json" },
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
          headers: { "Content-Type": "application/json" },
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
      .single();

    if (existingMember) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "You are already a member of this organization",
          errorCode: "ALREADY_MEMBER",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
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
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (organization.seats_used >= organization.seat_count) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Organization has reached seat capacity",
          errorCode: "SEAT_LIMIT_REACHED",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Increment invite uses
    const { error: updateInviteError } = await supabase
      .from("organization_invites")
      .update({ uses_count: invite.uses_count + 1 })
      .eq("invite_code", inviteCode);

    if (updateInviteError) {
      console.error("Error incrementing invite uses:", updateInviteError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to process invite",
        } as JoinOrganizationResponse),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Add user as organization member
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
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Increment seats_used counter atomically with capacity check
    const { data: updatedOrg, error: seatsError } = await supabase
      .from("organizations")
      .update({ seats_used: organization.seats_used + 1 })
      .eq("id", organizationId)
      .lt("seats_used", "seat_count") // Atomic capacity check
      .select()
      .single();

    if (seatsError || !updatedOrg) {
      console.error(
        "Error incrementing seats_used (capacity reached):",
        seatsError,
      );
      // Rollback: delete member
      await supabase.from("organization_members").delete().eq("id", member.id);

      return new Response(
        JSON.stringify({
          success: false,
          error: "Organization has reached seat capacity",
          errorCode: "SEAT_LIMIT_REACHED",
        } as JoinOrganizationResponse),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Grant premium subscription via organization sponsorship
    const { data: subscription, error: subscriptionError } = await supabase
      .from("subscriptions")
      .insert({
        user_id: user.id,
        organization_id: organizationId,
        tier: "premium",
        status: "active",
        access_source: "organization_sponsored",
        current_period_start: now,
        current_period_end: null, // Null = organization-managed expiry
      })
      .select()
      .single();

    if (subscriptionError) {
      console.error("Error creating subscription:", subscriptionError);
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
        } as JoinOrganizationResponse),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
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
              tier: subscription.tier,
              access_source: subscription.access_source,
            }
          : undefined,
      } as JoinOrganizationResponse),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error joining organization:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal server error",
      } as JoinOrganizationResponse),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
