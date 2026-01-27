import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import * as jose from "https://deno.land/x/jose@v4.15.4/index.ts";

// Apple's public key endpoint
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";

interface AppleNotificationPayload {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  sub: string;
  email?: string;
  event_type:
    | "email-disabled"
    | "email-enabled"
    | "consent-withdrawn"
    | "account-delete";
  real_user_status?: number;
}

// Cache for Apple's public keys (refresh every 24 hours)
let cachedKeys: jose.JSONWebKeySet | null = null;
let keysCacheTime = 0;
const CACHE_DURATION = 24 * 60 * 60 * 1000; // 24 hours

/**
 * Fetch and cache Apple's public keys
 */
async function getApplePublicKeys(): Promise<jose.JSONWebKeySet> {
  const now = Date.now();

  if (cachedKeys && now - keysCacheTime < CACHE_DURATION) {
    return cachedKeys;
  }

  const response = await fetch(APPLE_KEYS_URL);
  if (!response.ok) {
    throw new Error(`Failed to fetch Apple public keys: ${response.status}`);
  }

  cachedKeys = (await response.json()) as jose.JSONWebKeySet;
  keysCacheTime = now;

  return cachedKeys;
}

/**
 * Verify and decode Apple's JWT
 */
async function verifyAppleJWT(
  token: string,
): Promise<AppleNotificationPayload> {
  const keys = await getApplePublicKeys();

  const decoded = await jose.jwtVerify(token, async (header) => {
    // Find the matching public key
    const key = keys.keys.find((k) => k.kid === header.kid);
    if (!key) {
      throw new Error(`No matching key found: ${header.kid}`);
    }

    // Import the JWK as a KeyLike
    return await jose.importJWK(key);
  });

  return decoded.payload as AppleNotificationPayload;
}

/**
 * Handle email disabled event
 */
async function handleEmailDisabled(
  supabase: ReturnType<typeof createClient>,
  payload: AppleNotificationPayload,
) {
  const { data: user, error } = await supabase.auth.admin.getUserById(
    payload.sub,
  );

  if (error) {
    console.error("Failed to fetch user:", error);
    return;
  }

  if (!user) {
    console.warn(`User not found: ${payload.sub}`);
    return;
  }

  // Update user metadata to mark email as disabled
  const { error: updateError } = await supabase.auth.admin.updateUserById(
    payload.sub,
    {
      user_metadata: {
        ...user.user_metadata,
        apple_email_disabled: true,
        apple_email_disabled_at: new Date().toISOString(),
      },
    },
  );

  if (updateError) {
    console.error("Failed to update user metadata:", updateError);
  } else {
    console.log(`Email disabled for user: ${payload.sub}`);
  }
}

/**
 * Handle email enabled event
 */
async function handleEmailEnabled(
  supabase: ReturnType<typeof createClient>,
  payload: AppleNotificationPayload,
) {
  const { data: user, error } = await supabase.auth.admin.getUserById(
    payload.sub,
  );

  if (error) {
    console.error("Failed to fetch user:", error);
    return;
  }

  if (!user) {
    console.warn(`User not found: ${payload.sub}`);
    return;
  }

  // Update user metadata to mark email as enabled
  const { error: updateError } = await supabase.auth.admin.updateUserById(
    payload.sub,
    {
      user_metadata: {
        ...user.user_metadata,
        apple_email_disabled: false,
        apple_email_enabled_at: new Date().toISOString(),
      },
    },
  );

  if (updateError) {
    console.error("Failed to update user metadata:", updateError);
  } else {
    console.log(`Email enabled for user: ${payload.sub}`);
  }
}

/**
 * Handle consent withdrawn event
 */
async function handleConsentWithdrawn(
  supabase: ReturnType<typeof createClient>,
  payload: AppleNotificationPayload,
) {
  const { data: user, error } = await supabase.auth.admin.getUserById(
    payload.sub,
  );

  if (error) {
    console.error("Failed to fetch user:", error);
    return;
  }

  if (!user) {
    console.warn(`User not found: ${payload.sub}`);
    return;
  }

  // Update user metadata to mark consent as withdrawn
  const { error: updateError } = await supabase.auth.admin.updateUserById(
    payload.sub,
    {
      user_metadata: {
        ...user.user_metadata,
        apple_consent_withdrawn: true,
        apple_consent_withdrawn_at: new Date().toISOString(),
      },
    },
  );

  if (updateError) {
    console.error("Failed to update user metadata:", updateError);
  } else {
    console.log(`Consent withdrawn for user: ${payload.sub}`);
  }
}

/**
 * Handle account deletion
 */
async function handleAccountDelete(
  supabase: ReturnType<typeof createClient>,
  payload: AppleNotificationPayload,
) {
  const userId = payload.sub;

  console.log(`Account deletion requested for user: ${userId}`);

  try {
    // 1. Delete all user data from custom tables (respecting foreign keys)
    // Delete in order of dependencies

    // Delete conversation messages
    const { error: msgError } = await supabase
      .from("messages")
      .delete()
      .eq("user_id", userId);

    if (msgError && msgError.code !== "PGRST116") {
      // PGRST116 = no rows affected
      console.error("Error deleting messages:", msgError);
    }

    // Delete conversations
    const { error: convError } = await supabase
      .from("conversations")
      .delete()
      .eq("user_id", userId);

    if (convError && convError.code !== "PGRST116") {
      console.error("Error deleting conversations:", convError);
    }

    // Delete moods
    const { error: moodError } = await supabase
      .from("moods")
      .delete()
      .eq("user_id", userId);

    if (moodError && moodError.code !== "PGRST116") {
      console.error("Error deleting moods:", moodError);
    }

    // Delete exercise sessions
    const { error: sessionError } = await supabase
      .from("exercise_sessions")
      .delete()
      .eq("user_id", userId);

    if (sessionError && sessionError.code !== "PGRST116") {
      console.error("Error deleting exercise sessions:", sessionError);
    }

    // Delete user badges
    const { error: badgeError } = await supabase
      .from("user_badges")
      .delete()
      .eq("user_id", userId);

    if (badgeError && badgeError.code !== "PGRST116") {
      console.error("Error deleting user badges:", badgeError);
    }

    // Delete circle posts
    const { error: postError } = await supabase
      .from("circle_posts")
      .delete()
      .eq("user_id", userId);

    if (postError && postError.code !== "PGRST116") {
      console.error("Error deleting circle posts:", postError);
    }

    // Delete circle memberships
    const { error: memberError } = await supabase
      .from("circle_members")
      .delete()
      .eq("user_id", userId);

    if (memberError && memberError.code !== "PGRST116") {
      console.error("Error deleting circle memberships:", memberError);
    }

    // Delete circles created by user
    const { error: circleError } = await supabase
      .from("circles")
      .delete()
      .eq("created_by", userId);

    if (circleError && circleError.code !== "PGRST116") {
      console.error("Error deleting circles:", circleError);
    }

    // Delete quests
    const { error: questError } = await supabase
      .from("quests")
      .delete()
      .eq("user_id", userId);

    if (questError && questError.code !== "PGRST116") {
      console.error("Error deleting quests:", questError);
    }

    // Delete subscriptions
    const { error: subError } = await supabase
      .from("subscriptions")
      .delete()
      .eq("user_id", userId);

    if (subError && subError.code !== "PGRST116") {
      console.error("Error deleting subscriptions:", subError);
    }

    // Delete crisis events
    const { error: crisisError } = await supabase
      .from("crisis_events")
      .delete()
      .eq("user_id", userId);

    if (crisisError && crisisError.code !== "PGRST116") {
      console.error("Error deleting crisis events:", crisisError);
    }

    // Delete user settings
    const { error: settingsError } = await supabase
      .from("user_settings")
      .delete()
      .eq("user_id", userId);

    if (settingsError && settingsError.code !== "PGRST116") {
      console.error("Error deleting user settings:", settingsError);
    }

    // Delete user profile
    const { error: profileError } = await supabase
      .from("profiles")
      .delete()
      .eq("id", userId);

    if (profileError && profileError.code !== "PGRST116") {
      console.error("Error deleting profile:", profileError);
    }

    // 2. Delete the auth user (this also deletes any other auth-related data)
    const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);

    if (deleteError) {
      console.error("Error deleting auth user:", deleteError);
      throw deleteError;
    }

    console.log(`Successfully deleted all data for user: ${userId}`);
  } catch (error) {
    console.error("Error handling account deletion:", error);
    throw error;
  }
}

serve(async (req) => {
  // Only POST requests are allowed
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Get the JWT from the request body
    const body = await req.json();
    const token = body.token || body;

    if (!token) {
      return new Response(
        JSON.stringify({ error: "Missing token in request body" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Verify and decode the JWT
    let payload: AppleNotificationPayload;
    try {
      payload = await verifyAppleJWT(
        typeof token === "string" ? token : token.toString(),
      );
    } catch (error) {
      console.error("JWT verification failed:", error);
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Handle different event types
    switch (payload.event_type) {
      case "email-disabled":
        await handleEmailDisabled(supabase, payload);
        break;

      case "email-enabled":
        await handleEmailEnabled(supabase, payload);
        break;

      case "consent-withdrawn":
        await handleConsentWithdrawn(supabase, payload);
        break;

      case "account-delete":
        await handleAccountDelete(supabase, payload);
        break;

      default:
        console.warn(`Unknown event type: ${payload.event_type}`);
    }

    // Return success response
    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
