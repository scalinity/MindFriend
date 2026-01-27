import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface CreateSessionRequest {
  modality: "tactile" | "visual" | "audio";
  patternId: string;
}

interface CreateSessionResponse {
  sessionId: string;
  premiumAccess: boolean;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate JWT and get user
    const authHeader = req.headers.get("Authorization")!;
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const { modality, patternId }: CreateSessionRequest = await req.json();

    // Validate request
    if (!modality || !patternId) {
      return new Response(
        JSON.stringify({ error: "Missing modality or patternId" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if pattern is premium
    const premiumPatterns = [
      "tactile-earth-pulse",
      "visual-spiral",
      "visual-flower-bloom",
      "visual-dot-grid",
    ];
    const isPremiumPattern = premiumPatterns.includes(patternId);

    // Check premium access if needed
    let premiumAccess = false;
    if (isPremiumPattern) {
      const { data: subscription } = await supabase
        .from("subscriptions")
        .select("status")
        .eq("user_id", user.id)
        .single();

      premiumAccess = subscription?.status === "active";

      if (!premiumAccess) {
        return new Response(
          JSON.stringify({
            error: "Premium subscription required",
            code: "PREMIUM_REQUIRED",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Insert sensory_sessions record
    const { data: session, error: insertError } = await supabase
      .from("sensory_sessions")
      .insert({
        user_id: user.id,
        modality,
        pattern_id: patternId,
        status: "active",
      })
      .select()
      .single();

    if (insertError || !session) {
      console.error("Failed to create session:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create session" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const response: CreateSessionResponse = {
      sessionId: session.id,
      premiumAccess: isPremiumPattern && premiumAccess,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in create-sensory-session:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
