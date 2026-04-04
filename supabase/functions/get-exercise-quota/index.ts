import { getCorsHeaders } from "../_shared/cors.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface QuotaResponse {
  used: number;
  limit: number;
  remaining: number;
  isPremium: boolean;
}

// Constants for quota limits
const FREE_TIER_MONTHLY_LIMIT = 1;
const PREMIUM_MONTHLY_LIMIT = 999; // Practical "unlimited"

serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
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
    const monthlyLimit = isPremium ? PREMIUM_MONTHLY_LIMIT : FREE_TIER_MONTHLY_LIMIT;

    // Count this month's generations using UTC first-of-month for consistency
    const now = new Date();
    const monthStartUTC = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );

    const { count, error: countError } = await supabase
      .from("generated_content")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", monthStartUTC.toISOString());

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
      limit: monthlyLimit,
      remaining: Math.max(0, monthlyLimit - used),
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
