// MindFriend Send Buddy Invite Edge Function
// Creates buddy invitation and optionally sends email/SMS

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { escapeHtml, isValidEmail, sanitizeEmail } from "../_shared/utils.ts";

interface SendBuddyInviteRequest {
  contact: string;
  method: "sms" | "email" | "link";
  send_notification?: boolean;
}

interface SendBuddyInviteResponse {
  success: boolean;
  invite_code: string;
  relationship_id: string;
  expires_at: string;
  notification_sent?: boolean;
  message: string;
}

// Generate a 6-character alphanumeric invite code
function generateBuddyCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Validate phone number (basic validation)
function isValidPhone(phone: string): boolean {
  // Remove all non-digit characters for validation
  const digits = phone.replace(/\D/g, "");
  return digits.length >= 10 && digits.length <= 15;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
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

    const {
      contact: rawContact,
      method,
      send_notification = true,
    }: SendBuddyInviteRequest = await req.json();

    if (!rawContact || !method) {
      return new Response(
        JSON.stringify({
          error: "Missing contact or method",
          code: "MISSING_PARAMS",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate contact based on method
    let contact = rawContact.trim();

    if (method === "email") {
      if (!isValidEmail(contact)) {
        return new Response(
          JSON.stringify({
            error: "Invalid email format",
            code: "INVALID_EMAIL",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      contact = sanitizeEmail(contact);
    } else if (method === "sms") {
      if (!isValidPhone(contact)) {
        return new Response(
          JSON.stringify({
            error: "Invalid phone number",
            code: "INVALID_PHONE",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Check rate limit (max 10 invites per day)
    const today = new Date().toISOString().split("T")[0];
    const { count: todayCount } = await supabaseAdmin
      .from("buddy_relationships")
      .select("*", { count: "exact", head: true })
      .eq("inviter_id", user.id)
      .gte("invited_at", `${today}T00:00:00Z`);

    if (todayCount && todayCount >= 10) {
      return new Response(
        JSON.stringify({
          error: "Daily invite limit reached (10 per day)",
          code: "RATE_LIMIT",
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if there's already a pending invite for this contact
    const { data: existingInvite } = await supabaseAdmin
      .from("buddy_relationships")
      .select("id, invite_code, expires_at")
      .eq("inviter_id", user.id)
      .eq("invitee_contact", contact.toLowerCase())
      .eq("status", "pending")
      .gt("expires_at", new Date().toISOString())
      .single();

    if (existingInvite) {
      // Return existing invite
      return new Response(
        JSON.stringify({
          success: true,
          invite_code: existingInvite.invite_code,
          relationship_id: existingInvite.id,
          expires_at: existingInvite.expires_at,
          message: "An active invitation already exists for this contact",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate invite code (ensure uniqueness)
    let inviteCode: string;
    let attempts = 0;
    do {
      inviteCode = generateBuddyCode();
      const { data: existing } = await supabaseAdmin
        .from("buddy_relationships")
        .select("id")
        .eq("invite_code", inviteCode)
        .single();

      if (!existing) break;
      attempts++;
    } while (attempts < 10);

    if (attempts >= 10) {
      return new Response(
        JSON.stringify({
          error: "Failed to generate unique invite code",
          code: "CODE_GEN_FAILED",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Set expiry (30 days)
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    // Create buddy relationship
    const { data: relationship, error: insertError } = await supabaseAdmin
      .from("buddy_relationships")
      .insert({
        inviter_id: user.id,
        invite_code: inviteCode,
        invite_method: method,
        invitee_contact: method === "link" ? null : contact.toLowerCase(),
        status: "pending",
        expires_at: expiresAt.toISOString(),
      })
      .select()
      .single();

    if (insertError || !relationship) {
      console.error("Error creating buddy relationship:", insertError);
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

    let notificationSent = false;

    // Send notification if requested
    if (send_notification && method !== "link") {
      // Get inviter's profile
      const { data: inviterProfile } = await supabaseAdmin
        .from("profiles")
        .select("display_name")
        .eq("id", user.id)
        .single();

      const inviterName = inviterProfile?.display_name || "Someone";
      const deepLink = `https://getmindfriend.app/buddy/${inviteCode}`;

      if (method === "email") {
        const resendApiKey = Deno.env.get("RESEND_API_KEY");

        if (resendApiKey) {
          try {
            const safeInviterName = escapeHtml(inviterName);

            const emailResponse = await fetch("https://api.resend.com/emails", {
              method: "POST",
              headers: {
                Authorization: `Bearer ${resendApiKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                from: "MindFriend <noreply@getmindfriend.app>",
                to: [contact],
                subject: `${safeInviterName} wants to be your wellness buddy!`,
                html: `
                  <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
                    <h1 style="color: #6366f1; margin-bottom: 24px;">You've Got a Wellness Buddy Request!</h1>

                    <p style="font-size: 16px; line-height: 1.6; color: #374151;">
                      ${safeInviterName} wants to be your wellness buddy on MindFriend.
                    </p>

                    <p style="font-size: 16px; line-height: 1.6; color: #374151;">
                      Together, you can:
                    </p>

                    <ul style="font-size: 16px; line-height: 1.8; color: #374151;">
                      <li>See each other's streaks for motivation</li>
                      <li>Send encouragement to support one another</li>
                      <li>Stay accountable on your wellness journeys</li>
                      <li>Both earn bonus XP when you connect!</li>
                    </ul>

                    <div style="background: #f3f4f6; border-radius: 12px; padding: 24px; margin: 24px 0; text-align: center;">
                      <p style="font-size: 14px; color: #6b7280; margin-bottom: 8px;">Your Buddy Code</p>
                      <p style="font-size: 32px; font-weight: bold; color: #6366f1; letter-spacing: 2px; margin: 0;">
                        ${inviteCode}
                      </p>
                    </div>

                    <div style="text-align: center; margin: 24px 0;">
                      <a href="${deepLink}" style="display: inline-block; background: #6366f1; color: white; padding: 14px 28px; border-radius: 12px; text-decoration: none; font-weight: 600;">
                        Accept Invitation
                      </a>
                    </div>

                    <p style="font-size: 16px; line-height: 1.6; color: #374151;">
                      Or enter the code in the MindFriend app after signing up.
                    </p>

                    <p style="font-size: 14px; color: #9ca3af; margin-top: 32px;">
                      This invitation expires in 30 days.
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
              notificationSent = true;
            } else {
              console.error("Resend API error:", await emailResponse.text());
            }
          } catch (emailError) {
            console.error("Error sending email:", emailError);
          }
        } else {
          console.log("RESEND_API_KEY not configured, skipping email");
        }
      } else if (method === "sms") {
        // SMS integration - stub for MVP
        // In production, integrate with Twilio, MessageBird, or similar
        console.log(
          `SMS stub: Would send to ${contact}: "${inviterName} wants to be your wellness buddy on MindFriend! Join with code: ${inviteCode} or tap: ${deepLink}"`,
        );
        // For MVP, we don't actually send SMS - just return the code
        notificationSent = false;
      }
    }

    const response: SendBuddyInviteResponse = {
      success: true,
      invite_code: inviteCode,
      relationship_id: relationship.id,
      expires_at: expiresAt.toISOString(),
      message: notificationSent
        ? `Invitation sent to ${contact}`
        : "Invitation created. Share the code with your buddy.",
    };

    if (send_notification) {
      response.notification_sent = notificationSent;
    }

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Send buddy invite error:", error);
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
