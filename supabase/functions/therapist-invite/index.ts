/**
 * Therapist Invite Edge Function
 * Purpose: Send email invitation to therapist with JWT magic link (7-day expiration)
 * Flow: Client invites → Email sent → Therapist clicks link → Connection accepted
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Initialize Supabase client
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    // Get authenticated user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "UNAUTHORIZED", message: "Invalid token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // Parse request body
    const body = await req.json();
    const therapistEmail = body.therapistEmail?.trim().toLowerCase();

    if (!therapistEmail || !isValidEmail(therapistEmail)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_EMAIL",
          message: "Valid email address is required",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check if therapist exists in therapist_accounts
    const { data: therapistAccount } = await supabase
      .from("therapist_accounts")
      .select("id, user_id, is_verified, practice_name")
      .eq(
        "user_id",
        supabase.auth.admin.listUsers().then(async () => {
          // Query auth.users by email (requires service role)
          const { data: authUsers } = await supabase.auth.admin.listUsers();
          const therapistUser = authUsers?.users?.find(
            (u) => u.email === therapistEmail,
          );
          return therapistUser?.id;
        }),
      )
      .single();

    // Get therapist user_id from auth.users
    const { data: authUsers } = await supabase.auth.admin.listUsers();
    const therapistUser = authUsers?.users?.find(
      (u) => u.email === therapistEmail,
    );

    if (!therapistUser) {
      return new Response(
        JSON.stringify({
          error: "THERAPIST_NOT_FOUND",
          message:
            "Therapist email not registered. They must create an account first.",
        }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check if therapist has an account in therapist_accounts
    const { data: therapistAccountCheck } = await supabase
      .from("therapist_accounts")
      .select("id, is_verified, accepts_invites")
      .eq("user_id", therapistUser.id)
      .single();

    if (!therapistAccountCheck) {
      return new Response(
        JSON.stringify({
          error: "NOT_A_THERAPIST",
          message: "This user is not registered as a therapist.",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    if (!therapistAccountCheck.accepts_invites) {
      return new Response(
        JSON.stringify({
          error: "THERAPIST_NOT_ACCEPTING",
          message: "This therapist is not accepting new connections.",
        }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      );
    }

    const therapistId = therapistAccountCheck.id;

    // Check if connection already exists
    const { data: existingConnection } = await supabase
      .from("therapy_connections")
      .select("id, status")
      .eq("client_id", user.id)
      .eq("therapist_id", therapistId)
      .single();

    if (existingConnection) {
      if (existingConnection.status === "active") {
        return new Response(
          JSON.stringify({
            error: "CONNECTION_EXISTS",
            message: "You are already connected to this therapist.",
          }),
          { status: 409, headers: { "Content-Type": "application/json" } },
        );
      } else if (existingConnection.status === "pending") {
        return new Response(
          JSON.stringify({
            error: "INVITATION_PENDING",
            message:
              "Invitation already sent. Waiting for therapist to accept.",
          }),
          { status: 409, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    // Generate JWT token for magic link (7-day expiration)
    const jwtSecret = Deno.env.get("JWT_SECRET") || "your-secret-key";
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(jwtSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"],
    );

    const invitationToken = await create(
      { alg: "HS256", typ: "JWT" },
      {
        clientId: user.id,
        therapistId: therapistId,
        purpose: "therapist_invitation",
        exp: getNumericDate(7 * 24 * 60 * 60), // 7 days
      },
      key,
    );

    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    // Create or update therapy_connection
    const { data: connection, error: connectionError } = await supabase
      .from("therapy_connections")
      .upsert(
        {
          client_id: user.id,
          therapist_id: therapistId,
          status: "pending",
          invited_by: "client",
          invitation_token: invitationToken,
          invitation_expires_at: expiresAt.toISOString(),
          invited_at: new Date().toISOString(),
        },
        {
          onConflict: "client_id,therapist_id",
        },
      )
      .select()
      .single();

    if (connectionError) {
      console.error("Failed to create connection:", connectionError);
      return new Response(
        JSON.stringify({
          error: "DATABASE_ERROR",
          message: "Failed to create invitation",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Get client profile info for email
    const { data: clientProfile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", user.id)
      .single();

    // Send email via Resend
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    if (!resendApiKey) {
      console.error("RESEND_API_KEY not configured");
      // Don't fail - connection created, just log error
    } else {
      const magicLink = `https://getmindfriend.app/therapist/accept?token=${invitationToken}`;
      const clientName =
        clientProfile?.display_name || user.email?.split("@")[0] || "A client";

      try {
        const emailResponse = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: "MindFriend <noreply@getmindfriend.app>",
            to: therapistEmail,
            subject: `Connection Request from ${clientName}`,
            html: generateEmailHTML(clientName, magicLink, expiresAt),
          }),
        });

        if (!emailResponse.ok) {
          const errorText = await emailResponse.text();
          console.error("Failed to send email:", errorText);
        }
      } catch (emailError) {
        console.error("Email send exception:", emailError);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        invitationId: connection.id,
        expiresAt: expiresAt.toISOString(),
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Therapist invite error:", error);
    return new Response(
      JSON.stringify({ error: "INTERNAL_ERROR", message: "An error occurred" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

function generateEmailHTML(
  clientName: string,
  magicLink: string,
  expiresAt: Date,
): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Connection Request from ${clientName}</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">

  <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; border-radius: 10px 10px 0 0; text-align: center;">
    <h1 style="color: white; margin: 0; font-size: 24px;">New Connection Request</h1>
  </div>

  <div style="background: #f9fafb; padding: 30px; border-radius: 0 0 10px 10px; border: 1px solid #e5e7eb;">

    <p style="font-size: 16px; margin-bottom: 20px;">
      <strong>${clientName}</strong> has invited you to connect on MindFriend to share their wellness progress with you.
    </p>

    <div style="background: white; padding: 20px; border-radius: 8px; border: 1px solid #e5e7eb; margin: 20px 0;">
      <h2 style="margin-top: 0; font-size: 18px; color: #111827;">What you'll be able to see:</h2>
      <ul style="padding-left: 20px; color: #6b7280;">
        <li>Daily mood scores and trends</li>
        <li>Assessment results (PHQ-9, GAD-7)</li>
        <li>Exercise completion history (if shared)</li>
        <li>Journal entries (if shared)</li>
      </ul>
      <p style="font-size: 14px; color: #6b7280; margin-bottom: 0;">
        <em>Your client controls what data is shared and can revoke access at any time.</em>
      </p>
    </div>

    <div style="text-align: center; margin: 30px 0;">
      <a href="${magicLink}" style="display: inline-block; background: #667eea; color: white; padding: 14px 32px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
        Accept Connection Request
      </a>
    </div>

    <p style="font-size: 14px; color: #6b7280; text-align: center; margin-top: 20px;">
      This invitation expires on <strong>${expiresAt.toLocaleDateString()}</strong>
    </p>

    <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">

    <p style="font-size: 13px; color: #9ca3af; text-align: center;">
      If you didn't expect this invitation, you can safely ignore this email.
    </p>

  </div>

  <p style="font-size: 12px; color: #9ca3af; text-align: center; margin-top: 20px;">
    MindFriend • Your Partner in Mental Wellness<br>
    <a href="https://getmindfriend.app/privacy" style="color: #9ca3af;">Privacy Policy</a> •
    <a href="https://getmindfriend.app/terms" style="color: #9ca3af;">Terms of Service</a>
  </p>

</body>
</html>
  `;
}
