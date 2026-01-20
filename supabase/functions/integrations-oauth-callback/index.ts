import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get user from JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Handle different OAuth callback providers
  const url = new URL(req.url);
  const provider = url.searchParams.get("provider");

  if (req.method === "POST") {
    const { code, state, integrationType } = await req.json();

    // Validate state to prevent CSRF
    const { data: storedState } = await supabase
      .from("integration_states")
      .select("*")
      .eq("user_id", user.id)
      .eq("state", state)
      .eq("integration_type", integrationType)
      .single();

    if (!storedState || new Date() > new Date(storedState.expires_at)) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired state" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Exchange code for token based on provider
    let accessToken: string;
    let refreshToken: string | null = null;
    let expiresIn: number;

    try {
      switch (provider) {
        case "google": {
          const tokenResponse = await fetch(
            "https://oauth2.googleapis.com/token",
            {
              method: "POST",
              headers: { "Content-Type": "application/x-www-form-urlencoded" },
              body: new URLSearchParams({
                code,
                client_id: Deno.env.get("GOOGLE_CLIENT_ID")!,
                client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
                redirect_uri: `${Deno.env.get("SUPABASE_URL")}/functions/v1/integrations-oauth-callback?provider=google`,
                grant_type: "authorization_code",
              }),
            },
          );
          const tokenData = await tokenResponse.json();
          accessToken = tokenData.access_token;
          refreshToken = tokenData.refresh_token;
          expiresIn = tokenData.expires_in;
          break;
        }

        case "microsoft": {
          const tokenResponse = await fetch(
            "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            {
              method: "POST",
              headers: { "Content-Type": "application/x-www-form-urlencoded" },
              body: new URLSearchParams({
                code,
                client_id: Deno.env.get("MICROSOFT_CLIENT_ID")!,
                client_secret: Deno.env.get("MICROSOFT_CLIENT_SECRET")!,
                redirect_uri: `${Deno.env.get("SUPABASE_URL")}/functions/v1/integrations-oauth-callback?provider=microsoft`,
                grant_type: "authorization_code",
              }),
            },
          );
          const tokenData = await tokenResponse.json();
          accessToken = tokenData.access_token;
          refreshToken = tokenData.refresh_token;
          expiresIn = tokenData.expires_in;
          break;
        }

        case "tripit": {
          const tokenResponse = await fetch(
            "https://api.tripit.com/oauth/access_token",
            {
              method: "POST",
              headers: {
                "Content-Type": "application/x-www-form-urlencoded",
                Authorization: `OAuth realm="TripIt", oauth_consumer_key="${Deno.env.get("TRIPIT_CLIENT_ID")}", oauth_token="${code.split("&")[0].split("=")[1]}", oauth_signature_method="HMAC-SHA1"`,
              },
            },
          );
          const tokenData = await tokenResponse.text();
          // Parse OAuth 1.0a response
          const params = new URLSearchParams(tokenData);
          accessToken = params.get("oauth_token") || "";
          refreshToken = params.get("oauth_token_secret");
          expiresIn = 86400 * 30; // 30 days
          break;
        }

        default:
          return new Response(
            JSON.stringify({ error: "Unsupported provider" }),
            {
              status: 400,
              headers: { "Content-Type": "application/json" },
            },
          );
      }

      // Store integration record
      const { error: insertError } = await supabase.from("integrations").upsert(
        {
          user_id: user.id,
          integration_type: integrationType,
          provider_id: user.email,
          status: "connected",
          scopes: [],
          last_sync_at: new Date().toISOString(),
        },
        { onConflict: "user_id, integration_type" },
      );

      if (insertError) {
        return new Response(JSON.stringify({ error: insertError.message }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      // Clean up state
      await supabase
        .from("integration_states")
        .delete()
        .eq("id", storedState.id);

      // Log audit event
      await supabase.rpc("log_audit_event", {
        p_user_id: user.id,
        p_action: "integration_connected",
        p_resource_type: integrationType,
        p_resource_id: integrationType,
        p_actor_type: "user",
        p_actor_id: user.id,
        p_details: JSON.stringify({ provider }),
      });

      return new Response(JSON.stringify({ success: true, provider }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch (error) {
      return new Response(JSON.stringify({ error: "Token exchange failed" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  // Handle OAuth state initiation (for PKCE)
  if (req.method === "GET" && url.searchParams.get("action") === "init") {
    const integrationType = url.searchParams.get("integration_type");
    const state = crypto.randomUUID();

    // Store state for validation
    await supabase.from("integration_states").insert({
      user_id: user.id,
      state,
      integration_type: integrationType,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(), // 10 minutes
    });

    return new Response(JSON.stringify({ state, integrationType }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "Method not allowed" }), {
    status: 405,
    headers: { "Content-Type": "application/json" },
  });
});
