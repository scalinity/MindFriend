import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface QuotaResponse {
  used: number;
  limit: number;
  remaining: number;
  isPremium: boolean;
}

// Constants for quota limits
const FREE_TIER_DAILY_LIMIT = 3;
const PREMIUM_DAILY_LIMIT = 999; // Practical "unlimited"

// Standard CORS headers for all responses
const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
};

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    // Check premium status
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .eq("status", "active")
      .maybeSingle();

    const isPremium = !!subscription;
    const dailyLimit = isPremium ? PREMIUM_DAILY_LIMIT : FREE_TIER_DAILY_LIMIT;

    // Count today's generations using UTC midnight for consistency
    const now = new Date();
    const todayUTC = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
    );

    const { count, error: countError } = await supabase
      .from("generated_content")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", todayUTC.toISOString());

    if (countError) {
      console.error("Error counting generations:", countError);
      return new Response(JSON.stringify({ error: "Failed to check quota" }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    const used = count ?? 0;

    const response: QuotaResponse = {
      used,
      limit: dailyLimit,
      remaining: Math.max(0, dailyLimit - used),
      isPremium,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: corsHeaders,
    });
  } catch (error) {
    console.error("Error in get-exercise-quota:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
