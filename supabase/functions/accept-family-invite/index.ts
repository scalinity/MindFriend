// MindFriend Accept Family Invite Edge Function
// Handles family/couples plan invitation acceptance

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface AcceptInviteRequest {
  invite_code: string;
}

interface AcceptInviteResponse {
  success: boolean;
  familyId?: string;
  circleId?: string;
  message: string;
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

    const { invite_code }: AcceptInviteRequest = await req.json();

    if (!invite_code) {
      return new Response(JSON.stringify({ error: "Missing invite_code" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Find the invitation
    const { data: invitation, error: inviteError } = await supabaseAdmin
      .from("family_invitations")
      .select(
        `
        *,
        family_groups (
          id,
          name,
          admin_user_id,
          circle_id
        )
      `,
      )
      .eq("invite_code", invite_code.toUpperCase())
      .is("accepted_at", null)
      .single();

    if (inviteError || !invitation) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid or already used invitation code",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if invitation is expired
    if (new Date(invitation.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "This invitation has expired",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const familyGroup = invitation.family_groups;
    const familyId = invitation.family_id;
    const circleId = familyGroup?.circle_id;

    // Use atomic RPC to claim seat (prevents race conditions)
    const { data: claimResult, error: claimError } = await supabaseAdmin.rpc(
      "claim_family_seat",
      {
        p_family_id: familyId,
        p_user_id: user.id,
        p_invited_email: invitation.email,
      },
    );

    if (claimError) {
      console.error("Error claiming seat:", claimError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to claim family seat",
          code: "RPC_ERROR",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Handle RPC result
    if (!claimResult.success) {
      return new Response(
        JSON.stringify({
          success: false,
          error: claimResult.error,
          code: claimResult.code,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get admin subscription for member subscription creation
    const { data: adminSub } = await supabaseAdmin
      .from("subscriptions")
      .select("*")
      .eq("id", claimResult.admin_subscription_id)
      .single();

    // Add user to the family circle
    if (circleId) {
      // Check if already a circle member
      const { data: existingCircleMember } = await supabaseAdmin
        .from("circle_members")
        .select("id")
        .eq("circle_id", circleId)
        .eq("user_id", user.id)
        .single();

      if (!existingCircleMember) {
        await supabaseAdmin.from("circle_members").insert({
          circle_id: circleId,
          user_id: user.id,
          role: "member",
        });
      }
    }

    // Mark invitation as accepted
    await supabaseAdmin
      .from("family_invitations")
      .update({ accepted_at: new Date().toISOString() })
      .eq("id", invitation.id);

    // Note: seats_used is already incremented by the atomic claim_family_seat RPC

    // Create subscription for new member (linked to same family)
    await supabaseAdmin.from("subscriptions").upsert(
      {
        user_id: user.id,
        product_id: adminSub.product_id,
        original_transaction_id: `family-${adminSub.original_transaction_id}`,
        status: "active",
        plan_type: adminSub.plan_type,
        billing_period: adminSub.billing_period,
        family_id: familyId,
        is_family_admin: false,
        seats_used: 0, // Non-admin members don't track seats
        seats_total: 0,
        expires_at: adminSub.expires_at,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );

    // Update profile to premium
    await supabaseAdmin
      .from("profiles")
      .update({
        subscription_tier: "premium",
        daily_ai_quota: -1, // Unlimited
        premium_badge: "premium_supporter",
      })
      .eq("id", user.id);

    // Award Premium Supporter badge
    const { data: badge } = await supabaseAdmin
      .from("badges")
      .select("id")
      .eq("code", "premium_supporter")
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

    const response: AcceptInviteResponse = {
      success: true,
      familyId,
      message: `Welcome to ${familyGroup?.name || "the family plan"}!`,
    };

    if (circleId) {
      response.circleId = circleId;
    }

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Accept invite error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
