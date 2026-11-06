import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";

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

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
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
    if (!authHeader?.startsWith("Bearer ") || !authHeader.slice(7)) {
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
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
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
        created_by_admin_id,
        max_uses,
        uses_count,
        expires_at,
        is_active,
        organizations (
          id,
          name,
          status,
          subscription_status
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
      if (!Number.isFinite(expiresAt.getTime()) || expiresAt <= new Date()) {
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

    const organization = invite.organizations as unknown as {
      name: string;
      status: string;
      subscription_status: string;
    } | null;
    if (
      !organization || organization.status !== "active" ||
      organization.subscription_status !== "active"
    ) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Organization sponsorship is not active",
          errorCode: "SPONSORSHIP_INACTIVE",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: issuer, error: issuerError } = await supabase
      .from("organization_admins")
      .select("id")
      .eq("id", invite.created_by_admin_id)
      .eq("organization_id", invite.organization_id)
      .eq("role", "admin")
      .maybeSingle();
    if (issuerError || !issuer) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: "Invite issuer is not authorized",
          errorCode: "INVITE_DEACTIVATED",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validation is a preview. Only a committed join consumes an invitation use.
    const remainingUses = invite.max_uses !== null
      ? invite.max_uses - (invite.uses_count ?? 0)
      : null;

    // Return valid response
    return new Response(
      JSON.stringify({
        valid: true,
        organizationId: invite.organization_id,
        organizationName: organization.name,
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
