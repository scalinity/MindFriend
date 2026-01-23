import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "*",
      },
    });
  }

  const diagnostics: any = {
    timestamp: new Date().toISOString(),
    method: req.method,
    url: req.url,
    hasAuthHeader: false,
    tokenLength: 0,
    tokenPrefix: "",
    envVarsPresent: {
      SUPABASE_URL: !!Deno.env.get("SUPABASE_URL"),
      SUPABASE_ANON_KEY: !!Deno.env.get("SUPABASE_ANON_KEY"),
      SUPABASE_SERVICE_ROLE_KEY: !!Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    },
    expectedValues: {
      supabaseUrl: Deno.env.get("SUPABASE_URL"),
    },
  };

  try {
    const authHeader = req.headers.get("Authorization");

    if (!authHeader) {
      diagnostics.error = "Missing Authorization header";
      return new Response(JSON.stringify(diagnostics), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    diagnostics.hasAuthHeader = true;
    const token = authHeader.replace("Bearer ", "");
    diagnostics.tokenLength = token.length;
    diagnostics.tokenPrefix = token.substring(0, 30);

    // Decode JWT (without verification) to inspect claims
    try {
      const parts = token.split(".");
      if (parts.length === 3) {
        const payload = JSON.parse(
          atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
        );
        diagnostics.tokenClaims = {
          aud: payload.aud,
          iss: payload.iss,
          sub: payload.sub,
          exp: payload.exp,
          expDate: new Date(payload.exp * 1000).toISOString(),
          isExpired: payload.exp * 1000 < Date.now(),
          role: payload.role,
        };
      }
    } catch (e) {
      diagnostics.tokenDecodeError = (e as Error).message;
    }

    // Try with service role key
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError) {
      diagnostics.authError = {
        message: authError.message,
        status: authError.status,
        name: authError.name,
      };
      diagnostics.user = null;

      return new Response(JSON.stringify(diagnostics), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    if (!user) {
      diagnostics.authError = { message: "No user returned from auth.getUser" };
      diagnostics.user = null;

      return new Response(JSON.stringify(diagnostics), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    diagnostics.success = true;
    diagnostics.user = {
      id: user.id,
      email: user.email,
      aud: user.aud,
      created_at: user.created_at,
    };

    return new Response(JSON.stringify(diagnostics), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    diagnostics.exception = {
      message: (error as Error).message,
      name: (error as Error).name,
    };

    return new Response(JSON.stringify(diagnostics), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
});
