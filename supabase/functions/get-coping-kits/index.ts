// Edge Function: get-coping-kits
// Fetches available coping kits with user state (pin status, active progress)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders } from "../_shared/cors.ts";
import { CommonErrors, createErrorResponse } from "../_shared/errors.ts";

interface CopingKitResponse {
  id: string;
  title: string;
  description: string;
  context_tag: string;
  steps_count: number;
  estimated_minutes: number;
  is_premium: boolean;
  user_state: {
    pinned: boolean;
    last_used_at: string | null;
    total_uses: number;
    has_active_progress: boolean;
  } | null;
}

interface ActiveProgressResponse {
  kit_id: string;
  kit_title: string;
  current_step_index: number;
  total_steps: number;
  minutes_remaining: number;
  expires_at: string;
}

interface GetCopingKitsResponse {
  kits: CopingKitResponse[];
  active_progress_kits: ActiveProgressResponse[];
}

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Create Supabase client with user's JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return CommonErrors.unauthorized(corsHeaders);
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    // Verify user authentication
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return CommonErrors.invalidToken(corsHeaders);
    }

    // Parse query params for optional context filter
    const url = new URL(req.url);
    const contextTag = url.searchParams.get("context_tag");

    // Fetch all coping kits
    let kitsQuery = supabase
      .from("coping_kits")
      .select(
        "id, title, description, context_tag, steps, estimated_minutes, is_premium, display_order",
      )
      .order("display_order");

    if (contextTag) {
      kitsQuery = kitsQuery.eq("context_tag", contextTag);
    }

    const { data: kits, error: kitsError } = await kitsQuery;
    if (kitsError) {
      console.error("Error fetching kits:", kitsError);
      return CommonErrors.internalError(corsHeaders);
    }

    // Fetch user's kit preferences
    const { data: userKits, error: userKitsError } = await supabase
      .from("user_coping_kits")
      .select("kit_id, pinned, pin_order, last_used_at, total_uses")
      .eq("user_id", user.id);

    if (userKitsError) {
      console.error("Error fetching user kits:", userKitsError);
      return CommonErrors.internalError(corsHeaders);
    }

    // Create a map for quick lookup
    const userKitsMap = new Map((userKits ?? []).map((uk) => [uk.kit_id, uk]));

    // Fetch active progress for user
    const { data: activeProgress, error: progressError } = await supabase
      .from("kit_progress")
      .select("id, kit_id, current_step_index, started_at, expires_at")
      .eq("user_id", user.id)
      .gt("expires_at", new Date().toISOString());

    if (progressError) {
      console.error("Error fetching progress:", progressError);
      return CommonErrors.internalError(corsHeaders);
    }

    // Create a map for active progress
    const progressMap = new Map(
      (activeProgress ?? []).map((p) => [p.kit_id, p]),
    );

    // Fetch kit details for active progress
    const progressKitIds = Array.from(progressMap.keys());
    let progressKits: { id: string; title: string; steps: unknown }[] = [];
    if (progressKitIds.length > 0) {
      const { data } = await supabase
        .from("coping_kits")
        .select("id, title, steps")
        .in("id", progressKitIds);
      progressKits = data ?? [];
    }
    const progressKitsMap = new Map(progressKits.map((pk) => [pk.id, pk]));

    // Build response
    const kitsResponse: CopingKitResponse[] = (kits ?? []).map((kit) => {
      const userState = userKitsMap.get(kit.id);
      const progress = progressMap.get(kit.id);
      return {
        id: kit.id,
        title: kit.title,
        description: kit.description,
        context_tag: kit.context_tag,
        steps_count: Array.isArray(kit.steps) ? kit.steps.length : 0,
        estimated_minutes: kit.estimated_minutes,
        is_premium: kit.is_premium,
        user_state: userState
          ? {
              pinned: userState.pinned,
              last_used_at: userState.last_used_at,
              total_uses: userState.total_uses,
              has_active_progress: !!progress,
            }
          : null,
      };
    });

    const activeProgressResponse: ActiveProgressResponse[] = Array.from(
      progressMap.entries(),
    )
      .filter(([_, p]) => {
        // Filter out expired progress
        return new Date(p.expires_at) > new Date();
      })
      .map(([kitId, progress]) => {
        const kit = progressKitsMap.get(kitId);
        const totalSteps =
          kit && Array.isArray(kit.steps) ? kit.steps.length : 0;
        const remainingSteps = totalSteps - progress.current_step_index;
        // Estimate 2 minutes per remaining step
        const minutesRemaining = Math.max(1, remainingSteps * 2);

        return {
          kit_id: kitId,
          kit_title: kit?.title ?? "Unknown Kit",
          current_step_index: progress.current_step_index,
          total_steps: totalSteps,
          minutes_remaining: minutesRemaining,
          expires_at: progress.expires_at,
        };
      });

    const response: GetCopingKitsResponse = {
      kits: kitsResponse,
      active_progress_kits: activeProgressResponse,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error in get-coping-kits:", error);
    return CommonErrors.internalError(corsHeaders);
  }
});
