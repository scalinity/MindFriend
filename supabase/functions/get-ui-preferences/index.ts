// MindFriend Get UI Preferences Edge Function
// Retrieves user's UI preferences including Calm Screen Mode settings

import { authenticateRequest, isAuthError } from "../_shared/auth.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

// Default preferences for new users
const DEFAULT_PREFERENCES = {
  screen_mode: "standard",
  reduced_motion: false,
  reduced_transparency: false,
  reduced_noise: false,
  ios_reduced_motion_linked: false,
  schedule_enabled: false,
  schedule_start_time: null,
  schedule_end_time: null,
  schedule_timezone: "UTC",
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Authenticate the request
  const authResult = await authenticateRequest(req);

  if (isAuthError(authResult)) {
    return authResult.response;
  }

  const { user, supabaseUser } = authResult;

  try {
    // Fetch existing preferences using authenticated client (respects RLS)
    const { data, error } = await supabaseUser
      .from("ui_preferences")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    if (error) {
      console.error("Database error fetching preferences:", error);
      return new Response(
        JSON.stringify({ error: "Database error", message: error.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Return existing preferences or defaults
    const preferences = data || DEFAULT_PREFERENCES;

    return new Response(JSON.stringify({ preferences }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: "An unexpected error occurred",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
