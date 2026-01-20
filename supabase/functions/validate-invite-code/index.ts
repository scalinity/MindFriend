import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

interface ValidateInviteCodeRequest {
  inviteCode: string;
}

interface ValidateInviteCodeResponse {
  valid: boolean;
  organizationId?: string;
  organizationName?: string;
  remainingUses?: number;
  expiresAt?: string;
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

    // Validate authentication
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Missing authorization header",
        } as ValidateInviteCodeResponse),
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
          valid: false,
          error: "Unauthorized",
        } as ValidateInviteCodeResponse),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Parse request body
    const body = (await req.json()) as ValidateInviteCodeRequest;

    if (!body.inviteCode || typeof body.inviteCode !== "string") {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Invalid invite code format",
        } as ValidateInviteCodeResponse),
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
      .select(
        `
        id,
        invite_code,
        organization_id,
        max_uses,
        uses_count,
        expires_at,
        is_active,
        organizations (
          id,
          name
        )
      `,
      )
      .eq("invite_code", inviteCode)
      .single();

    if (fetchError || !invite) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Invite code not found",
          errorCode: "INVITE_NOT_FOUND",
        } as ValidateInviteCodeResponse),
        {
          status: 404,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Check if invite is deactivated
    if (!invite.is_active) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Invite code has been deactivated",
          errorCode: "INVITE_DEACTIVATED",
        } as ValidateInviteCodeResponse),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Check if invite has expired
    if (invite.expires_at) {
      const expiresAt = new Date(invite.expires_at);
      if (expiresAt < new Date()) {
        return new Response(
          JSON.stringify({
            valid: false,
            error: "Invite code has expired",
            errorCode: "INVITE_EXPIRED",
          } as ValidateInviteCodeResponse),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          },
        );
      }
    }

    // Check if invite has reached max uses
    if (invite.max_uses !== null && invite.uses_count >= invite.max_uses) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Invite code has reached maximum uses",
          errorCode: "MAX_USES_EXCEEDED",
        } as ValidateInviteCodeResponse),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Increment uses_count
    const { error: updateError } = await supabase
      .from("organization_invites")
      .update({ uses_count: invite.uses_count + 1 })
      .eq("id", invite.id);

    if (updateError) {
      console.error("Error incrementing uses_count:", updateError);
      // Non-fatal - validation still succeeds
    }

    // Calculate remaining uses (after increment)
    const remainingUses =
      invite.max_uses !== null
        ? invite.max_uses - (invite.uses_count + 1)
        : null;

    // Return valid response
    return new Response(
      JSON.stringify({
        valid: true,
        organizationId: invite.organization_id,
        organizationName: (invite.organizations as any)?.name,
        remainingUses,
        expiresAt: invite.expires_at,
      } as ValidateInviteCodeResponse),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error validating invite code:", error);

    return new Response(
      JSON.stringify({
        valid: false,
        error: "Internal server error",
      } as ValidateInviteCodeResponse),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
