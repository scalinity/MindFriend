// MindFriend Check Streak Protection Edge Function
// Daily cron job to proactively check and apply streak shields for all users
// Triggered daily at 06:00 UTC (before most users wake up)
// This ensures shields are applied even if users don't open the app

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

// Constants
const BATCH_SIZE = 50;
const MAX_USERS = 10000; // Safety cap to prevent runaway processing
const OPERATION_TIMEOUT_MS = 25000;
const NOTIFICATION_TIMEOUT_MS = 5000; // 5s timeout for notification calls
const MAX_CONCURRENT_BATCHES = 4; // Process batches in parallel with limit

interface ProtectionCheckResult {
  usersChecked: number;
  shieldsUsed: number;
  recoveryEnabled: number;
  errors: string[];
}

interface UserAtRisk {
  user_id: string;
  current_streak_days: number;
  last_quest_date: string;
  streak_shields_remaining: number;
}

/**
 * Constant-time string comparison to prevent timing attacks
 */
function constantTimeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/**
 * Creates a promise that rejects after the specified timeout
 */
function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  operation: string,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(
        new Error(`Operation '${operation}' timed out after ${timeoutMs}ms`),
      );
    }, timeoutMs);

    promise
      .then((result) => {
        clearTimeout(timeoutId);
        resolve(result);
      })
      .catch((error) => {
        clearTimeout(timeoutId);
        reject(error);
      });
  });
}

/**
 * Splits an array into chunks of specified size
 */
function chunkArray<T>(array: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < array.length; i += chunkSize) {
    chunks.push(array.slice(i, i + chunkSize));
  }
  return chunks;
}

/**
 * Anonymize user ID for logging (first 8 chars only)
 * Full ID logged only when absolutely necessary for debugging
 */
function anonymizeUserId(userId: string): string {
  return userId.substring(0, 8) + "...";
}

/**
 * Process batches with concurrency limit
 */
async function processBatchesWithLimit<T>(
  batches: T[][],
  processBatch: (batch: T[], batchIndex: number) => Promise<void>,
  maxConcurrent: number,
): Promise<void> {
  const results: Promise<void>[] = [];
  let currentIndex = 0;

  async function processNext(): Promise<void> {
    while (currentIndex < batches.length) {
      const batchIndex = currentIndex++;
      await processBatch(batches[batchIndex], batchIndex);
    }
  }

  // Start up to maxConcurrent workers
  for (let i = 0; i < Math.min(maxConcurrent, batches.length); i++) {
    results.push(processNext());
  }

  await Promise.all(results);
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(origin) });
  }

  // Validate HTTP method - only POST allowed for cron jobs
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...headers, Allow: "POST, OPTIONS" },
    });
  }

  try {
    // Verify cron secret
    const cronSecret = req.headers.get("X-Cron-Secret");
    const expectedSecret = Deno.env.get("CRON_SECRET");

    if (!expectedSecret) {
      console.error("CRON_SECRET environment variable is not configured");
      return new Response(JSON.stringify({ error: "Service unavailable" }), {
        status: 503,
        headers,
      });
    }

    // Validate required environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not configured");
      return new Response(JSON.stringify({ error: "Service unavailable" }), {
        status: 503,
        headers,
      });
    }

    if (!cronSecret || !constantTimeCompare(cronSecret, expectedSecret)) {
      console.error("Invalid or missing cron secret");
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    console.log("Starting daily streak protection check");

    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    const result: ProtectionCheckResult = {
      usersChecked: 0,
      shieldsUsed: 0,
      recoveryEnabled: 0,
      errors: [],
    };

    // Find users who might need streak protection:
    // - Have a streak > 0
    // - Last quest was more than 1 day ago (potential miss)
    // - Not already in recovery mode
    const findUsersPromise = supabaseAdmin
      .from("user_stats")
      .select(
        "user_id, current_streak_days, last_quest_date, streak_shields_remaining",
      )
      .gt("current_streak_days", 0)
      .eq("recovery_quest_available", false)
      .not("last_quest_date", "is", null) as Promise<{
      data: UserAtRisk[] | null;
      error: Error | null;
    }>;

    const { data: usersAtRisk, error: findError } = await withTimeout(
      findUsersPromise,
      OPERATION_TIMEOUT_MS,
      "find_users_at_risk",
    );

    if (findError) {
      console.error("Error finding users at risk:", findError);
      return new Response(
        JSON.stringify({ success: false, error: findError.message, result }),
        { status: 500, headers },
      );
    }

    if (!usersAtRisk?.length) {
      console.log("No users at risk of streak loss");
      return new Response(
        JSON.stringify({ success: true, result, message: "No users at risk" }),
        { status: 200, headers },
      );
    }

    console.log(
      `Found ${usersAtRisk.length} users to check for streak protection`,
    );

    // IMPORTANT: We do NOT filter users by date here.
    // The RPC function check_streak_protection handles timezone-aware date logic.
    // Each user has their own timezone stored in profiles, and the RPC calculates
    // whether they missed yesterday based on THEIR local time, not server UTC.
    // Filtering here with UTC would cause 50-80% of users to be incorrectly skipped.

    // Apply MAX_USERS safety cap to prevent runaway processing
    const usersNeedingProtection = usersAtRisk.slice(0, MAX_USERS);
    if (usersAtRisk.length > MAX_USERS) {
      console.warn(
        `WARNING: ${usersAtRisk.length} users at risk, processing only first ${MAX_USERS}. ` +
          `Consider investigating if this is expected or indicates a data issue.`,
      );
    }

    console.log(
      `${usersNeedingProtection.length} users need streak protection check (RPC will apply timezone-aware filtering)`,
    );

    // Process in batches with concurrency limit
    const userBatches = chunkArray(usersNeedingProtection, BATCH_SIZE);
    const totalBatches = userBatches.length;

    await processBatchesWithLimit(
      userBatches,
      async (batch, batchIndex) => {
        console.log(
          `Processing batch ${batchIndex + 1}/${totalBatches} (${batch.length} users)`,
        );

        const batchPromises = batch.map(async (user) => {
          const anonUserId = anonymizeUserId(user.user_id);
          try {
            // Call check_streak_protection RPC for each user
            const { data, error } = await supabaseAdmin.rpc(
              "check_streak_protection",
              {
                p_user_id: user.user_id,
              },
            );

            if (error) {
              // Log anonymized user ID
              console.error(
                `Error checking protection for user ${anonUserId}:`,
                error.code || error.message,
              );
              result.errors.push(
                `Protection check failed: ${error.code || "UNKNOWN"}`,
              );
              return;
            }

            // Validate RPC result structure
            if (!data || data.length === 0) {
              console.warn(`RPC returned empty result for user ${anonUserId}`);
              result.errors.push(`Empty RPC result`);
              return;
            }

            result.usersChecked++;

            if (data[0]?.streak_protected) {
              result.shieldsUsed++;
              // Use anonymized ID and correct streak from RPC result (not stale query value)
              console.log(
                `Shield used for user ${anonUserId}, streak ${data[0].new_streak} protected`,
              );

              // Send notification with timeout
              try {
                await withTimeout(
                  supabaseAdmin.functions.invoke("send-notification", {
                    body: {
                      type: "shield_used",
                      recipientId: user.user_id, // Full ID needed for notification delivery
                      data: {
                        streak: data[0].new_streak, // Use correct value from RPC
                        shieldsRemaining: data[0].shields_remaining,
                        shieldsMax: data[0].shields_max,
                      },
                    },
                  }),
                  NOTIFICATION_TIMEOUT_MS,
                  "send_shield_notification",
                );
              } catch (notifyError) {
                console.error(
                  `Failed to notify user ${anonUserId}:`,
                  notifyError instanceof Error
                    ? notifyError.message
                    : "Unknown error",
                );
              }
            } else if (data[0]?.recovery_available) {
              result.recoveryEnabled++;
              console.log(
                `Recovery enabled for user ${anonUserId}, streak ${data[0].streak_before_break} to recover`,
              );

              // Send notification with timeout
              try {
                await withTimeout(
                  supabaseAdmin.functions.invoke("send-notification", {
                    body: {
                      type: "recovery_available",
                      recipientId: user.user_id, // Full ID needed for notification delivery
                      data: {
                        streakToRecover: data[0].streak_before_break,
                      },
                    },
                  }),
                  NOTIFICATION_TIMEOUT_MS,
                  "send_recovery_notification",
                );
              } catch (notifyError) {
                console.error(
                  `Failed to notify user ${anonUserId}:`,
                  notifyError instanceof Error
                    ? notifyError.message
                    : "Unknown error",
                );
              }
            }
          } catch (error) {
            // Log anonymized ID
            console.error(
              `Unexpected error for user ${anonUserId}:`,
              error instanceof Error ? error.message : "Unknown error",
            );
            result.errors.push(
              `Unexpected error: ${error instanceof Error ? error.name : "UNKNOWN"}`,
            );
          }
        });

        await Promise.allSettled(batchPromises);

        // Circuit breaker: stop if too many errors
        if (result.errors.length > usersNeedingProtection.length * 0.1) {
          console.error(
            `High error rate detected (${result.errors.length} errors). Stopping batch processing.`,
          );
          throw new Error("High error rate - aborting");
        }
      },
      MAX_CONCURRENT_BATCHES,
    );

    console.log(
      `Streak protection check complete: ${result.usersChecked} checked, ` +
        `${result.shieldsUsed} shields used, ${result.recoveryEnabled} recovery enabled`,
    );

    return new Response(JSON.stringify({ success: true, result }), {
      status: 200,
      headers,
    });
  } catch (error) {
    console.error("Check streak protection error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal server error",
        code:
          error instanceof Error && error.message.includes("timed out")
            ? "OPERATION_TIMEOUT"
            : "INTERNAL_ERROR",
      }),
      { status: 500, headers },
    );
  }
});
