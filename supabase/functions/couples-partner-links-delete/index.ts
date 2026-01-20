// DELETE /functions/v1/couples/partner-links-delete/{id}
// Unlink partnership (silent to other partner)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CouplesErrors } from "../_shared/couples-errors.ts";

serve(async (req) => {
  try {
    // Only accept DELETE method
    if (req.method !== "DELETE") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("Missing required environment variables");
      return CouplesErrors.unexpectedError(new Error("Server configuration error"));
    }

    // Initialize Supabase client with service role
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
    const partnerLinkId = pathSegments[pathSegments.length - 1];

    if (!partnerLinkId) {
      return CouplesErrors.missingField("partnerLinkId");
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

    // Update partner_link to end the partnership
    const { error: updateError } = await supabase
      .from("partner_links")
      .update({
        status: "ended",
        ended_at: new Date().toISOString(),
      })
      .eq("id", partnerLinkId);

    if (updateError) {
      console.error("Failed to end partnership:", updateError);
      return CouplesErrors.databaseError(updateError);
    }

    // Return 204 No Content
    return new Response(null, { status: 204 });
  } catch (error) {
    console.error("Unexpected error in partner-links/delete:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
