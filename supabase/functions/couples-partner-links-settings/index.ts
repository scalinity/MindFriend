// PATCH /functions/v1/couples/partner-links-settings/{id}
// Update sharing preferences for this partnership

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";

serve(async (req) => {
  try {
    // Only accept PATCH method
    if (req.method !== "PATCH") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("Missing required environment variables");
      return CouplesErrors.unexpectedError(new Error("Server configuration error"));
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: { Authorization: req.headers.get("Authorization")! },
      },
    });

    // Authenticate user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return CouplesErrors.missingAuth();
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return CouplesErrors.missingAuth();
    }

    const userId = user.id;

    // Extract partner link ID from URL path
    const url = new URL(req.url);
    const pathSegments = url.pathname.split("/");
    const partnerLinkId = pathSegments[pathSegments.length - 2]; // Last segment is "settings"

    if (!partnerLinkId) {
      return CouplesErrors.missingField("partnerLinkId");
    }

    // Parse request body
    let body;
    try {
      body = await req.json();
    } catch {
      return CouplesErrors.invalidJson();
    }

    const { shareMood, shareExercises } = body;

    // Validate at least one field is provided
    if (shareMood === undefined && shareExercises === undefined) {
      return CouplesErrors.missingField("shareMood or shareExercises");
    }

    // Validate field types if provided
    if (shareMood !== undefined && typeof shareMood !== "boolean") {
      return CouplesErrors.invalidFieldType("shareMood", "boolean");
    }

    if (shareExercises !== undefined && typeof shareExercises !== "boolean") {
      return CouplesErrors.invalidFieldType("shareExercises", "boolean");
    }

    // Fetch partner_link by ID
    const { data: partnerLink, error: fetchError } = await supabase
      .from("partner_links")
      .select("*")
      .eq("id", partnerLinkId)
      .maybeSingle();

    if (fetchError) {
      console.error("Failed to fetch partner link:", fetchError);
      return CouplesErrors.databaseError(fetchError);
    }

    if (!partnerLink) {
      return CouplesErrors.partnerLinkNotFound();
    }

    // Validate user is part of the partnership
    if (partnerLink.user_id_1 !== userId && partnerLink.user_id_2 !== userId) {
      return CouplesErrors.accessDenied();
    }

    // Determine which user is making the request and prepare update
    const isUser1 = partnerLink.user_id_1 === userId;
    const updateFields: Record<string, boolean> = {};

    if (shareMood !== undefined) {
      updateFields[isUser1 ? "user_1_share_mood" : "user_2_share_mood"] =
        shareMood;
    }

    if (shareExercises !== undefined) {
      updateFields[
        isUser1 ? "user_1_share_exercises" : "user_2_share_exercises"
      ] = shareExercises;
    }

    // Update sharing settings
    const { data: updatedLink, error: updateError } = await supabase
      .from("partner_links")
      .update(updateFields)
      .eq("id", partnerLinkId)
      .select()
      .single();

    if (updateError) {
      console.error("Failed to update sharing settings:", updateError);
      return CouplesErrors.databaseError(updateError);
    }

    // Return success with updated settings
    const currentShareMood = isUser1
      ? updatedLink.user_1_share_mood
      : updatedLink.user_2_share_mood;
    const currentShareExercises = isUser1
      ? updatedLink.user_1_share_exercises
      : updatedLink.user_2_share_exercises;

    return formatSuccess(
      {
        partnerLinkId: updatedLink.id,
        shareMood: currentShareMood,
        shareExercises: currentShareExercises,
        message: "Sharing settings updated.",
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in partner-links/settings:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
