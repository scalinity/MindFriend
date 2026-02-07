/**
 * Get AR Exercises Edge Function
 *
 * Returns available AR exercises filtered by device capabilities and user subscription.
 *
 * Request:
 *   GET /functions/v1/get-ar-exercises?capabilities={arkit,trueDepth,lidar}
 *   Headers: Authorization: Bearer <jwt>
 *
 * Response:
 *   { exercises: ARExercise[] }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

// CORS headers for preflight requests

interface ARCapabilities {
  arkit: boolean;
  trueDepth: boolean;
  lidar: boolean;
}

interface ARExercise {
  id: string;
  exerciseName: string;
  arType: string;
  description: string;
  durationSeconds: number;
  instructions: string[];
  voiceGuidanceScript: string[];
  sceneConfig: Record<string, unknown>;
  isPremium: boolean;
  isAvailable: boolean;
  unavailableReason: string | null;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing Supabase configuration");
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse capabilities from query string
    const url = new URL(req.url);
    const capabilitiesParam = url.searchParams.get("capabilities");
    let capabilities: ARCapabilities = {
      arkit: false,
      trueDepth: false,
      lidar: false,
    };

    if (capabilitiesParam) {
      try {
        capabilities = JSON.parse(capabilitiesParam);
      } catch {
        // Use defaults if parsing fails
      }
    }

    // Determine capability level
    let capabilityLevel = "fallback";
    if (capabilities.arkit) {
      capabilityLevel = capabilities.lidar ? "full_ar" : "limited_ar";
    }

    // Check user's premium status
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .single();

    const isPremiumUser = subscription?.status === "active";

    // Fetch all AR exercise types
    const { data: exerciseTypes, error: fetchError } = await supabase
      .from("ar_exercise_types")
      .select("*")
      .order("created_at", { ascending: true });

    if (fetchError) {
      throw fetchError;
    }

    // Annotate exercises with availability
    const exercises: ARExercise[] = (exerciseTypes || []).map((ex) => {
      const requiredCaps = ex.required_capabilities as ARCapabilities;

      let isAvailable = true;
      let unavailableReason: string | null = null;

      // Check premium requirement
      if (ex.is_premium && !isPremiumUser) {
        isAvailable = false;
        unavailableReason = "requires_premium";
      }

      // Check LiDAR requirement
      if (requiredCaps.lidar && !capabilities.lidar) {
        isAvailable = false;
        unavailableReason = "requires_lidar";
      }

      // Check TrueDepth requirement
      if (requiredCaps.trueDepth && !capabilities.trueDepth) {
        isAvailable = false;
        unavailableReason = "requires_truedepth";
      }

      // Check basic AR requirement
      if (requiredCaps.arkit && !capabilities.arkit) {
        // Allow fallback for certain exercise types
        const supportsFallback = ["breathing_orb", "grounding_541"].includes(
          ex.ar_type,
        );
        if (!supportsFallback) {
          isAvailable = false;
          unavailableReason = "requires_ar";
        }
      }

      return {
        id: ex.id,
        exerciseName: ex.exercise_name,
        arType: ex.ar_type,
        description: ex.description,
        durationSeconds: ex.duration_seconds,
        instructions: ex.instructions || [],
        voiceGuidanceScript: ex.voice_guidance_script || [],
        sceneConfig: ex.scene_config || {},
        isPremium: ex.is_premium,
        isAvailable,
        unavailableReason,
      };
    });

    return new Response(
      JSON.stringify({
        exercises,
        deviceCapability: capabilityLevel,
        isPremiumUser,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error in get-ar-exercises:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
