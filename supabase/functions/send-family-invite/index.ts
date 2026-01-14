// MindFriend Send Family Invite Edge Function
// Creates family invitation and optionally sends email via Resend

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { generateInviteCode } from "../_shared/billing-types.ts";
import { escapeHtml, isValidEmail, sanitizeEmail } from "../_shared/utils.ts";

interface SendInviteRequest {
  email: string;
  send_email?: boolean; // Optional: send email via Resend
}

interface SendInviteResponse {
  success: boolean;
  invite_code: string;
  expires_at: string;
  email_sent?: boolean;
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

    const { email: rawEmail, send_email = false }: SendInviteRequest =
      await req.json();

    if (!rawEmail) {
      return new Response(
        JSON.stringify({ error: "Missing email", code: "MISSING_EMAIL" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate and sanitize email
    if (!isValidEmail(rawEmail)) {
      return new Response(
        JSON.stringify({
          error: "Invalid email format",
          code: "INVALID_EMAIL_FORMAT",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const email = sanitizeEmail(rawEmail);

    // Check if user has a family group (is admin)
    const { data: familyGroup, error: groupError } = await supabaseAdmin
      .from("family_groups")
      .select("id, name")
      .eq("admin_user_id", user.id)
      .single();

    if (groupError || !familyGroup) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "You don't have a family plan. Purchase a couples or family plan first.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if there are available seats
    const { data: subscription } = await supabaseAdmin
      .from("subscriptions")
      .select("seats_used, seats_total")
      .eq("user_id", user.id)
      .eq("is_family_admin", true)
      .eq("status", "active")
      .single();

    if (!subscription) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Active subscription not found",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (subscription.seats_used >= subscription.seats_total) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `No seats available. Your plan allows ${subscription.seats_total} members.`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if there's already a pending invitation for this email
    const { data: existingInvite } = await supabaseAdmin
      .from("family_invitations")
      .select("id, invite_code, expires_at")
      .eq("family_id", familyGroup.id)
      .eq("email", email.toLowerCase())
      .is("accepted_at", null)
      .gt("expires_at", new Date().toISOString())
      .single();

    if (existingInvite) {
      // Return existing invitation
      return new Response(
        JSON.stringify({
          success: true,
          invite_code: existingInvite.invite_code,
          expires_at: existingInvite.expires_at,
          message: "An active invitation already exists for this email",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate invite code
    const inviteCode = generateInviteCode();
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7); // 7 days expiry

    // Create invitation
    const { error: inviteError } = await supabaseAdmin
      .from("family_invitations")
      .insert({
        family_id: familyGroup.id,
        email: email.toLowerCase(),
        invite_code: inviteCode,
        expires_at: expiresAt.toISOString(),
      });

    if (inviteError) {
      console.error("Error creating invitation:", inviteError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to create invitation",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let emailSent = false;

    // Send email if requested and Resend is configured
    if (send_email) {
      const resendApiKey = Deno.env.get("RESEND_API_KEY");

      if (resendApiKey) {
        try {
          // Get admin's profile for the invite email
          const { data: adminProfile } = await supabaseAdmin
            .from("profiles")
            .select("display_name")
            .eq("id", user.id)
            .single();

          // Escape all user-provided content to prevent XSS
          const safeSenderName = escapeHtml(
            adminProfile?.display_name || "Someone",
          );
          const safeFamilyName = escapeHtml(familyGroup.name);

          const emailResponse = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${resendApiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              from: "MindFriend <noreply@getmindfriend.app>",
              to: [email],
              subject: `${safeSenderName} invited you to join their MindFriend plan`,
              html: `
                <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
                  <h1 style="color: #6366f1; margin-bottom: 24px;">You're Invited!</h1>

                  <p style="font-size: 16px; line-height: 1.6; color: #374151;">
                    ${safeSenderName} has invited you to join their ${safeFamilyName} on MindFriend.
                  </p>

                  <p style="font-size: 16px; line-height: 1.6; color: #374151;">
                    With this invitation, you'll get full premium access including:
                  </p>

                  <ul style="font-size: 16px; line-height: 1.8; color: #374151;">
                    <li>Unlimited AI conversations</li>
                    <li>All premium exercises</li>
                    <li>Advanced insights</li>
                    <li>A shared circle with your family</li>
                  </ul>

                  <div style="background: #f3f4f6; border-radius: 12px; padding: 24px; margin: 24px 0; text-align: center;">
                    <p style="font-size: 14px; color: #6b7280; margin-bottom: 8px;">Your Invite Code</p>
                    <p style="font-size: 32px; font-weight: bold; color: #6366f1; letter-spacing: 2px; margin: 0;">
                      ${inviteCode}
                    </p>
                  </div>

                  <p style="font-size: 16px; line-height: 1.6; color: #374151;">
                    To accept this invitation:
                  </p>

                  <ol style="font-size: 16px; line-height: 1.8; color: #374151;">
                    <li>Download MindFriend from the App Store</li>
                    <li>Create an account or sign in</li>
                    <li>Go to Profile → Premium → Enter Invite Code</li>
                    <li>Enter the code above</li>
                  </ol>

                  <p style="font-size: 14px; color: #9ca3af; margin-top: 32px;">
                    This invitation expires in 7 days.
                  </p>

                  <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 32px 0;" />

                  <p style="font-size: 12px; color: #9ca3af; text-align: center;">
                    MindFriend - Your AI companion for mental wellness
                  </p>
                </div>
              `,
            }),
          });

          if (emailResponse.ok) {
            emailSent = true;
          } else {
            console.error("Resend API error:", await emailResponse.text());
          }
        } catch (emailError) {
          console.error("Error sending email:", emailError);
          // Don't fail the request if email fails - the code was still created
        }
      } else {
        console.log("RESEND_API_KEY not configured, skipping email");
      }
    }

    const response: SendInviteResponse = {
      success: true,
      invite_code: inviteCode,
      expires_at: expiresAt.toISOString(),
      message: emailSent
        ? `Invitation sent to ${email}`
        : "Invitation created. Share the code with your invitee.",
    };

    if (send_email) {
      response.email_sent = emailSent;
    }

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Send invite error:", error);
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
