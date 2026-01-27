import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SaveFavoriteRequest {
  modality: "tactile" | "visual" | "audio";
  patternId: string;
  isFavorite: boolean;
}

interface SaveFavoriteResponse {
  success: boolean;
  message: string;
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
    const { modality, patternId, isFavorite }: SaveFavoriteRequest =
      await req.json();

    // Validate request
    if (!modality || !patternId || isFavorite === undefined) {
      return new Response(
        JSON.stringify({ error: "Missing modality, patternId, or isFavorite" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (isFavorite) {
      // Add to favorites
      const { error: insertError } = await supabase
        .from("sensory_favorites")
        .insert({
          user_id: user.id,
          modality,
          pattern_id: patternId,
        })
        .select()
        .single();

      if (insertError) {
        // Check if already exists (unique constraint violation)
        if (insertError.code === "23505") {
          const response: SaveFavoriteResponse = {
            success: true,
            message: "Pattern already favorited",
          };

          return new Response(JSON.stringify(response), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }

        console.error("Failed to add favorite:", insertError);
        return new Response(
          JSON.stringify({ error: "Failed to add favorite" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: SaveFavoriteResponse = {
        success: true,
        message: "Pattern added to favorites",
      };

      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    } else {
      // Remove from favorites
      const { error: deleteError } = await supabase
        .from("sensory_favorites")
        .delete()
        .eq("user_id", user.id)
        .eq("modality", modality)
        .eq("pattern_id", patternId);

      if (deleteError) {
        console.error("Failed to remove favorite:", deleteError);
        return new Response(
          JSON.stringify({ error: "Failed to remove favorite" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: SaveFavoriteResponse = {
        success: true,
        message: "Pattern removed from favorites",
      };

      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  } catch (error) {
    console.error("Error in save-sensory-favorite:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
