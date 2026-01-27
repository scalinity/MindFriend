/**
 * Therapist Accept Edge Function
 * Purpose: Verify JWT magic link and accept therapy connection invitation
 * Flow: Therapist clicks email link → JWT verified → Connection status updated to "active"
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import {
  enforceHTTPS,
  getSecurityHeaders,
} from "../_shared/https-enforcement.ts";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Enforce HTTPS/TLS
  const httpsCheck = enforceHTTPS(req);
  if (!httpsCheck.secure) {
    return httpsCheck.error!;
  }

  // Initialize Supabase client
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    // Parse request body
    const body = await req.json();
    const invitationToken = body.token?.trim();

    if (!invitationToken) {
      return new Response(
        JSON.stringify({
          error: "INVALID_REQUEST",
          message: "Invitation token is required",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Verify JWT signature
    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) {
      console.error("CRITICAL: JWT_SECRET environment variable not configured");
      return new Response(
        JSON.stringify({
          error: "SERVER_ERROR",
          message: "Server configuration error",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(jwtSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"],
    );

    let payload;
    try {
      payload = await verify(invitationToken, key);
    } catch (error) {
      console.error("JWT verification failed:", error);
      return new Response(
        JSON.stringify({
          error: "INVALID_TOKEN",
          message: "Invalid or expired invitation token",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate payload structure
    if (
      !payload.clientId ||
      !payload.therapistId ||
      payload.purpose !== "therapist_invitation"
    ) {
      return new Response(
        JSON.stringify({
          error: "INVALID_TOKEN",
          message: "Token payload is invalid",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const { clientId, therapistId } = payload;

    // Hash the incoming token to compare with stored hash
    const tokenHash = await hashToken(invitationToken);

    // Find the connection with this token hash
    const { data: connection, error: fetchError } = await supabase
      .from("therapy_connections")
      .select("id, status, invitation_token_hash, invitation_expires_at")
      .eq("client_id", clientId)
      .eq("therapist_id", therapistId)
      .single();

    if (fetchError || !connection) {
      return new Response(
        JSON.stringify({
          error: "CONNECTION_NOT_FOUND",
          message: "No invitation found for this token",
        }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    // Verify token hash matches (prevents token reuse and theft)
    if (connection.invitation_token_hash !== tokenHash) {
      return new Response(
        JSON.stringify({
          error: "TOKEN_MISMATCH",
          message: "Token does not match invitation",
        }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check if connection already active
    if (connection.status === "active") {
      return new Response(
        JSON.stringify({
          success: true,
          message: "Connection already active",
          connectionId: connection.id,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check if connection was revoked
    if (connection.status === "revoked" || connection.status === "ended") {
      return new Response(
        JSON.stringify({
          error: "CONNECTION_REVOKED",
          message: "This invitation has been revoked by the client",
        }),
        { status: 410, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check expiration
    if (connection.invitation_expires_at) {
      const expiresAt = new Date(connection.invitation_expires_at);
      if (expiresAt < new Date()) {
        return new Response(
          JSON.stringify({
            error: "INVITATION_EXPIRED",
            message: "This invitation has expired",
            expiredAt: expiresAt.toISOString(),
          }),
          { status: 410, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    // Update connection to active and clear the invitation token hash
    const { error: updateError } = await supabase
      .from("therapy_connections")
      .update({
        status: "active",
        connected_at: new Date().toISOString(),
        invitation_token_hash: null, // Clear token hash to prevent reuse
        invitation_token: null, // Clear legacy field if exists
        invitation_expires_at: null,
      })
      .eq("id", connection.id);

    if (updateError) {
      console.error("Failed to activate connection:", updateError);
      return new Response(
        JSON.stringify({
          error: "UPDATE_FAILED",
          message: "Failed to activate connection",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Log successful acceptance to audit trail
    await supabase.from("therapy_access_log").insert({
      connection_id: connection.id,
      therapist_id: therapistId,
      action: "connection_accepted",
      resource_type: "therapy_connection",
      created_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({
        success: true,
        message: "Connection accepted successfully",
        connectionId: connection.id,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Therapist accept error:", error);
    return new Response(
      JSON.stringify({
        error: "INTERNAL_ERROR",
        message: "An error occurred",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

/**
 * Hash a token with SHA-256 to compare with stored hash
 */
async function hashToken(token: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(token);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hashHex;
}
