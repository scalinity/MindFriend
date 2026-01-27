// GET /functions/v1/couples/partners/mood-summary
// Fetch partner's mood for last N days (if sharing enabled)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getPartnerId } from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";

serve(async (req) => {
  try {
    // Only accept GET method
    if (req.method !== "GET") {
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

    // Get partner ID
    let partnerId: string | null;
    try {
      partnerId = await getPartnerId(supabase, userId);
    } catch (error) {
      console.error("Error getting partner ID:", error);
      return CouplesErrors.databaseError(error as Error);
    }

    if (!partnerId) {
      return CouplesErrors.notPartner();
    }

    // Get partner link to check sharing settings
    const { data: partnerLink } = await supabase
      .from("partner_links")
      .select("*")
      .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
      .eq("status", "active")
      .single();

    if (!partnerLink) {
      return CouplesErrors.notPartner();
    }

    // Determine which user is the partner and check if they're sharing mood
    const isUser1 = partnerLink.user_id_1 === userId;
    const partnerSharesMood = isUser1
      ? partnerLink.user_2_share_mood
      : partnerLink.user_1_share_mood;

    if (!partnerSharesMood) {
      return CouplesErrors.accessDenied();
    }

    // Parse query parameter for days (default 7)
    const url = new URL(req.url);
    const daysParam = url.searchParams.get("days");
    const days = daysParam ? parseInt(daysParam, 10) : 7;

    if (isNaN(days) || days < 1 || days > 30) {
      return CouplesErrors.invalidFieldValue(
        "days",
        "must be between 1 and 30",
      );
    }

    // Calculate date range
    const startDate = new Date(Date.now() - days * 24 * 3600 * 1000);

    // Fetch partner's moods
    const { data: moods, error: moodsError } = await supabase
      .from("moods")
      .select("*")
      .eq("user_id", partnerId)
      .gte("created_at", startDate.toISOString())
      .order("created_at", { ascending: false });

    if (moodsError) {
      console.error("Failed to fetch partner moods:", moodsError);
      return CouplesErrors.databaseError(moodsError);
    }

    // Get partner's profile for name
    const { data: partnerProfile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", partnerId)
      .single();

    const partnerName = partnerProfile?.display_name || "Your partner";

    // Format moods response
    const formattedMoods = (moods || []).map((mood) => ({
      date: mood.created_at.split("T")[0],
      mood: mood.mood_emoji || mood.mood || "😊",
      timestamp: mood.created_at,
    }));

    // Calculate last update time
    const lastUpdate =
      moods && moods.length > 0
        ? getRelativeTime(new Date(moods[0].created_at))
        : "No recent moods";

    return formatSuccess(
      {
        partnerId,
        partnerName,
        moods: formattedMoods,
        lastUpdate,
        sharingEnabled: true,
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in partners/mood-summary:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});

/**
 * Get relative time string (e.g., "2 hours ago")
 */
function getRelativeTime(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return "Just now";
  if (diffMins < 60)
    return `${diffMins} minute${diffMins === 1 ? "" : "s"} ago`;
  if (diffHours < 24)
    return `${diffHours} hour${diffHours === 1 ? "" : "s"} ago`;
  return `${diffDays} day${diffDays === 1 ? "" : "s"} ago`;
}
