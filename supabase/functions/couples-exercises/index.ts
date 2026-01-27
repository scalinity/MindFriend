// GET /functions/v1/couples/couples-exercises
// List available couples exercises based on entitlements

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { userHasPremiumAccess } from "../_shared/couples-utils.ts";
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

    // Check if user has premium access (own subscription or partner's)
    let hasPremium: boolean;
    try {
      hasPremium = await userHasPremiumAccess(supabase, userId);
    } catch (error) {
      console.error("Error checking premium access:", error);
      return CouplesErrors.databaseError(error as Error);
    }

    // Parse query parameters
    const url = new URL(req.url);
    const type = url.searchParams.get("type");
    const difficulty = url.searchParams.get("difficulty");

    // Build query for exercises
    let query = supabase.from("couples_exercises").select("*");

    // Apply filters
    if (type) {
      query = query.eq("type", type);
    }

    if (difficulty) {
      query = query.eq("difficulty", difficulty);
    }

    // Fetch all matching exercises
    const { data: exercises, error: fetchError } = await query;

    if (fetchError) {
      console.error("Failed to fetch exercises:", fetchError);
      return CouplesErrors.databaseError(fetchError);
    }

    // Filter premium exercises if user doesn't have premium
    const availableExercises =
      exercises?.filter((ex) => {
        return !ex.requires_premium || hasPremium;
      }) || [];

    // Calculate counts
    const totalFree =
      exercises?.filter((ex) => !ex.requires_premium).length || 0;
    const totalPremium =
      exercises?.filter((ex) => ex.requires_premium).length || 0;

    // Format response
    const formattedExercises = availableExercises.map((ex) => ({
      id: ex.id,
      name: ex.name,
      description: ex.description,
      type: ex.type,
      difficulty: ex.difficulty,
      durationMinutes: ex.duration_minutes,
      isPremium: ex.requires_premium,
      requiresBothPartners: ex.requires_both_partners,
      canDoSolo: ex.can_do_solo,
    }));

    return formatSuccess(
      {
        exercises: formattedExercises,
        totalAvailable: availableExercises.length,
        free: totalFree,
        premium: totalPremium,
        hasPartnerPremium: hasPremium,
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in couples-exercises:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
