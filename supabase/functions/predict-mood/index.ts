// MindFriend Mood Prediction Edge Function
// Runs daily via cron to generate mood predictions for eligible users
// See: docs/specs/005-predictive-mood-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import {
  calculatePrediction,
  shouldTriggerIntervention,
  DEFAULT_WEIGHTS,
} from "./algorithms.ts";
import type {
  PredictionFeatures,
  FeatureWeights,
  EligibleUser,
} from "./types.ts";

const BATCH_SIZE = 100; // Process users in batches
const USER_TIMEOUT_MS = 30000; // 30s timeout per user
const BATCH_TIMEOUT_MS = 120000; // 2min timeout per batch

/**
 * Wrap a promise with a timeout
 */
function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  errorMessage: string,
): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(errorMessage)), timeoutMs),
    ),
  ]);
}

/**
 * Hash user ID for logging (privacy-safe)
 */
function hashUserId(userId: string): string {
  return userId.substring(0, 8) + "...";
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  // Require cron secret or service role key
  const expectedCronSecret = Deno.env.get("CRON_SECRET");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // Fail fast if required secrets are missing
  if (!expectedCronSecret || !serviceRoleKey) {
    console.error("CRITICAL: Missing CRON_SECRET or SUPABASE_SERVICE_ROLE_KEY");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers },
    );
  }

  if (
    !isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey)
  ) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!supabaseUrl) {
      console.error("CRITICAL: Missing SUPABASE_URL");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers },
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    const now = new Date();
    const targetDate = now.toISOString().split("T")[0]; // YYYY-MM-DD
    let usersProcessed = 0;
    let predictionsCreated = 0;
    let interventionsTriggered = 0;
    let skippedExisting = 0;
    let errors: string[] = [];

    // Get eligible users (14+ moods, in target timezone window)
    // Default to processing users where it's 6-8 AM local time
    const { data: eligibleUsers, error: eligibleError } =
      await supabaseAdmin.rpc("get_prediction_eligible_users", {
        p_target_hour: 6,
        p_hour_window: 2,
      });

    if (eligibleError) {
      console.error("Error fetching eligible users:", eligibleError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch eligible users" }),
        { status: 500, headers },
      );
    }

    console.log(
      `Found ${eligibleUsers?.length || 0} eligible users for mood prediction`,
    );

    // Process users in batches
    const batches: EligibleUser[][] = [];
    for (let i = 0; i < (eligibleUsers || []).length; i += BATCH_SIZE) {
      batches.push((eligibleUsers as EligibleUser[]).slice(i, i + BATCH_SIZE));
    }

    for (const batch of batches) {
      const batchPromises = batch.map(async (user) => {
        const userHash = hashUserId(user.user_id);

        const processUser = async () => {
          // Check if prediction already exists for today
          const { data: existing } = await supabaseAdmin
            .from("mood_predictions")
            .select("id")
            .eq("user_id", user.user_id)
            .eq("predicted_for", targetDate)
            .single();

          if (existing) {
            skippedExisting++;
            return { success: true, skipped: true };
          }

          // Get features for this user
          const { data: featuresData, error: featuresError } =
            await supabaseAdmin.rpc("get_prediction_features", {
              p_user_id: user.user_id,
            });

          if (featuresError || !featuresData) {
            console.error(
              `Features error for user ${userHash}:`,
              featuresError?.message,
            );
            errors.push(`Features error for user ${userHash}`);
            return { success: false };
          }

          const features = featuresData as PredictionFeatures;

          // Get user-specific model weights (or use default)
          let weights: FeatureWeights = DEFAULT_WEIGHTS;
          const { data: userModel } = await supabaseAdmin
            .from("prediction_models")
            .select("feature_weights")
            .eq("user_id", user.user_id)
            .single();

          if (userModel?.feature_weights) {
            weights = userModel.feature_weights as FeatureWeights;
          }

          // Calculate prediction
          const prediction = calculatePrediction(features, weights);

          // Insert prediction
          const { data: insertedPrediction, error: insertError } =
            await supabaseAdmin
              .from("mood_predictions")
              .insert({
                user_id: user.user_id,
                predicted_for: targetDate,
                predicted_mood: prediction.predictedMood,
                confidence: prediction.confidence,
                factors: prediction.factors,
                model_version: prediction.modelVersion,
                features_used: prediction.featuresUsed,
              })
              .select()
              .single();

          if (insertError) {
            console.error(
              `Insert error for user ${userHash}:`,
              insertError.message,
            );
            errors.push(`Insert error for user ${userHash}`);
            return { success: false };
          }

          predictionsCreated++;

          // Check if intervention should be triggered
          if (
            shouldTriggerIntervention(
              prediction.predictedMood,
              prediction.confidence,
            )
          ) {
            try {
              // Call suggest-intervention function with timeout
              const interventionResponse = await withTimeout(
                supabaseAdmin.functions.invoke("suggest-intervention", {
                  body: {
                    userId: user.user_id,
                    predictionId: insertedPrediction.id,
                    predictedMood: prediction.predictedMood,
                    factors: prediction.factors,
                    features: prediction.featuresUsed,
                  },
                }),
                10000, // 10s timeout for intervention
                `Intervention timeout for user ${userHash}`,
              );

              if (interventionResponse.error) {
                console.error(
                  `Intervention error for user ${userHash}:`,
                  interventionResponse.error.message,
                );
              } else {
                interventionsTriggered++;
              }
            } catch (interventionError) {
              console.error(
                `Intervention failed for user ${userHash}:`,
                interventionError instanceof Error
                  ? interventionError.message
                  : "Unknown error",
              );
            }
          }

          usersProcessed++;
          return { success: true };
        };

        // Wrap user processing with timeout
        try {
          return await withTimeout(
            processUser(),
            USER_TIMEOUT_MS,
            `Timeout processing user ${userHash}`,
          );
        } catch (userError) {
          console.error(
            `Error for user ${userHash}:`,
            userError instanceof Error ? userError.message : "Unknown error",
          );
          errors.push(`Error for user ${userHash}`);
          return { success: false };
        }
      });

      // Use Promise.allSettled for batch failure isolation
      const batchResults = await withTimeout(
        Promise.allSettled(batchPromises),
        BATCH_TIMEOUT_MS,
        "Batch processing timeout",
      ).catch(() => {
        console.error("Batch timeout - some users may not have been processed");
        return [];
      });

      // Log batch statistics
      const settled = batchResults.filter(
        (r) => r.status === "fulfilled",
      ).length;
      const rejected = batchResults.filter(
        (r) => r.status === "rejected",
      ).length;
      if (rejected > 0) {
        console.warn(
          `Batch completed: ${settled} succeeded, ${rejected} failed`,
        );
      }
    }

    console.log("Mood prediction complete:", {
      usersProcessed,
      predictionsCreated,
      interventionsTriggered,
      skippedExisting,
      errorCount: errors.length,
    });

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: now.toISOString(),
        target_date: targetDate,
        users_processed: usersProcessed,
        predictions_created: predictionsCreated,
        interventions_triggered: interventionsTriggered,
        skipped_existing: skippedExisting,
        errors: errors.length > 0 ? errors : undefined,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Mood prediction error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
