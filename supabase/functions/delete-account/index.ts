import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createLogger } from "../_shared/logger.ts";

const log = createLogger("delete-account");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
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

    // Create Supabase client with user's JWT
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // User client to get the user ID
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Get the authenticated user
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      log.warn("Auth error during account deletion", { errorCode: userError?.code });
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = user.id;
    log.userAction("Deleting account", userId);

    // Admin client for deletion operations
    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Delete user data from all tables (order matters due to foreign keys)
    // Most tables have ON DELETE CASCADE, but we'll be explicit

    // 1. Delete messages (get conversation IDs first, then delete messages)
    const { data: conversations } = await adminClient
      .from("conversations")
      .select("id")
      .eq("user_id", userId);

    if (conversations && conversations.length > 0) {
      const conversationIds = conversations.map((c) => c.id);
      await adminClient
        .from("messages")
        .delete()
        .in("conversation_id", conversationIds);
    }

    // 2. Delete conversations
    await adminClient.from("conversations").delete().eq("user_id", userId);

    // 3. Delete circle checkins
    await adminClient.from("circle_checkins").delete().eq("user_id", userId);

    // 4. Delete circle memberships
    await adminClient.from("circle_members").delete().eq("user_id", userId);

    // 5. Delete circles owned by user
    await adminClient.from("circles").delete().eq("owner_id", userId);

    // 6. Delete exercise sessions
    await adminClient.from("exercise_sessions").delete().eq("user_id", userId);

    // 7. Delete user quests
    await adminClient.from("user_quests").delete().eq("user_id", userId);

    // 8. Delete user badges
    await adminClient.from("user_badges").delete().eq("user_id", userId);

    // 9. Delete moods
    await adminClient.from("moods").delete().eq("user_id", userId);

    // 10. Delete devices
    await adminClient.from("devices").delete().eq("user_id", userId);

    // 11. Delete profile
    await adminClient.from("profiles").delete().eq("id", userId);

    // 12. Finally, delete the auth user
    const { error: deleteAuthError } =
      await adminClient.auth.admin.deleteUser(userId);

    if (deleteAuthError) {
      log.error("Error deleting auth user", { errorMessage: deleteAuthError.message });
      return new Response(
        JSON.stringify({
          error: "Failed to delete account",
          details: deleteAuthError.message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
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
    log.error("Delete account error", { error: String(error) });
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
