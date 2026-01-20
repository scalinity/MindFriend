import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface PrivacyLockSettings {
  app_lock_enabled: boolean;
  auto_lock_seconds: number;
  quick_lock_method: string;
  triple_tap_enabled: boolean;
}

interface UpdateRequest {
  app_lock_enabled?: boolean;
  auto_lock_seconds?: number;
  quick_lock_method?: string;
  triple_tap_enabled?: boolean;
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const method = req.method;

  if (method === "GET") {
    // Fetch user's privacy lock settings
    const { data, error } = await supabase
      .from("privacy_lock_settings")
      .select("*")
      .eq("user_id", user.id)
      .single();

    if (error && error.code !== "PGRST116") {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Return default settings if none exist
    if (!data) {
      return new Response(JSON.stringify({
        app_lock_enabled: false,
        auto_lock_seconds: 300,
        quick_lock_method: "menu",
        triple_tap_enabled: false,
        user_id: user.id,
      }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (method === "PUT" || method === "PATCH") {
    const body: UpdateRequest = await req.json();

    // Validate input
    if (body.auto_lock_seconds !== undefined) {
      const validTimeouts = [60, 300, 900, 1800, 3600, 0]; // 1min, 5min, 15min, 30min, 1hr, Never
      if (!validTimeouts.includes(body.auto_lock_seconds)) {
        return new Response(JSON.stringify({ error: "Invalid auto-lock timeout" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    if (body.quick_lock_method !== undefined) {
      if (!["menu", "triple_tap"].includes(body.quick_lock_method)) {
        return new Response(JSON.stringify({ error: "Invalid quick lock method" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // Upsert settings
    const { data, error } = await supabase
      .from("privacy_lock_settings")
      .upsert({
        user_id: user.id,
        app_lock_enabled: body.app_lock_enabled,
        auto_lock_seconds: body.auto_lock_seconds,
        quick_lock_method: body.quick_lock_method,
        triple_tap_enabled: body.triple_tap_enabled,
        updated_at: new Date().toISOString(),
      } as PrivacyLockSettings)
      .select()
      .single();

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "Method not allowed" }), {
    status: 405,
    headers: { "Content-Type": "application/json" },
  });
});
