// MindFriend Delete Account Edge Function
// Handles complete account deletion with proper cascade and cleanup

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import { handleError, errorResponse } from "../_shared/error-handler.ts";

const log = createLogger("delete-account");

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Admin client for all operations
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Authenticate user from token
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: userError,
    } = await supabaseAdmin.auth.getUser(token);

    if (userError || !user) {
      log.warn("Auth error during account deletion", {
        errorCode: userError?.code,
      });
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = user.id;
    log.userAction("Deleting account", userId);

    // Delete from tables that don't have ON DELETE CASCADE FKs to profiles
    // Most tables cascade automatically when the auth user is deleted
    // because profiles.id references auth.users(id) with CASCADE

    // 1. Delete rate limits (no FK)
    await supabaseAdmin.from("rate_limits").delete().eq("user_id", userId);

    // 2. Delete notification history (no FK cascade)
    await supabaseAdmin
      .from("notification_history")
      .delete()
      .eq("user_id", userId);

    // 3. Delete memory fragments (complex relationships)
    await supabaseAdmin.from("memory_fragments").delete().eq("user_id", userId);

    // 4. Delete voice sessions
    await supabaseAdmin.from("voice_sessions").delete().eq("user_id", userId);

    // 5. Handle family memberships (remove from groups, not delete groups)
    await supabaseAdmin.from("family_members").delete().eq("user_id", userId);

    // 6. Transfer ownership of circles user owns to another member
    // This preserves circle content for remaining members
    const { data: ownedCircles } = await supabaseAdmin
      .from("circles")
      .select("id")
      .eq("owner_id", userId);

    for (const circle of ownedCircles || []) {
      // Find another member to transfer ownership to
      const { data: nextOwner } = await supabaseAdmin
        .from("circle_members")
        .select("user_id")
        .eq("circle_id", circle.id)
        .neq("user_id", userId)
        .order("joined_at", { ascending: true })
        .limit(1)
        .maybeSingle();

      if (nextOwner) {
        // Transfer ownership to the next oldest member
        await supabaseAdmin
          .from("circles")
          .update({ owner_id: nextOwner.user_id })
          .eq("id", circle.id);

        // Update their role to owner
        await supabaseAdmin
          .from("circle_members")
          .update({ role: "owner" })
          .eq("circle_id", circle.id)
          .eq("user_id", nextOwner.user_id);

        log.info("Transferred circle ownership", {
          circleId: circle.id,
          newOwnerId: nextOwner.user_id.slice(0, 8),
        });
      } else {
        // No other members - delete the empty circle
        await supabaseAdmin.from("circles").delete().eq("id", circle.id);
        log.info("Deleted empty circle", { circleId: circle.id });
      }
    }

    // Remove user from circles they're a member of (not owner)
    await supabaseAdmin.from("circle_members").delete().eq("user_id", userId);

    // 7. Delete the auth user - this cascades to profiles and most other data
    const { error: deleteAuthError } =
      await supabaseAdmin.auth.admin.deleteUser(userId);

    if (deleteAuthError) {
      // Log error server-side, return generic message to client
      return errorResponse(
        deleteAuthError,
        { operation: "deleteUser" },
        500,
        corsHeaders,
      );
    }

    log.info("Account deleted successfully");

    return new Response(
      JSON.stringify({
        success: true,
        message: "Account deleted successfully",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    return errorResponse(
      error,
      { operation: "deleteAccount" },
      500,
      corsHeaders,
    );
  }
});
