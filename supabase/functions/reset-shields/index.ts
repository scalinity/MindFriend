// MindFriend Reset Shields Edge Function
// Weekly cron job to reset streak shields for all users
// Triggered Monday at 05:00 UTC
// See: specs/10-streak-recovery.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Constants
const NOTIFICATION_BATCH_SIZE = 20;
const OPERATION_TIMEOUT_MS = 25000; // 25s to leave margin for cleanup before Edge Function timeout

interface ShieldResetResult {
  usersReset: number;
  notificationsSent: number;
  errors: string[];
}

interface UserForNotification {
  user_id: string;
  shields_used: number;
  new_shields: number;
}

/**
 * Constant-time string comparison to prevent timing attacks on secret validation
 */
function constantTimeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

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

  try {
    // Verify cron secret with constant-time comparison
    const cronSecret = req.headers.get("X-Cron-Secret");
    const expectedSecret = Deno.env.get("CRON_SECRET");

    // Validate CRON_SECRET is configured
    if (!expectedSecret) {
      console.error("CRON_SECRET environment variable is not configured");
      return new Response(
        JSON.stringify({
          error: "Service misconfigured",
          code: "CRON_SECRET_NOT_SET",
        }),
        {
          status: 503,
          headers,
        },
      );
    }

    // Validate cron secret with constant-time comparison to prevent timing attacks
    if (!cronSecret || !constantTimeCompare(cronSecret, expectedSecret)) {
      console.error("Invalid or missing cron secret");
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    console.log("Starting weekly shield reset");

    // Initialize Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const result: ShieldResetResult = {
      usersReset: 0,
      notificationsSent: 0,
      errors: [],
    };

    // Get users who need notification (shields were used) - with timeout
    const fetchUsersPromise = supabaseAdmin.rpc(
      "get_users_for_shield_reset_notification",
    ) as Promise<{
      data: UserForNotification[] | null;
      error: Error | null;
    }>;

    const { data: usersForNotification, error: fetchError } = await withTimeout(
      fetchUsersPromise,
      OPERATION_TIMEOUT_MS,
      "fetch_users_for_notification",
    );

    if (fetchError) {
      console.error("Error fetching users for notification:", fetchError);
      result.errors.push(`Fetch error: ${fetchError.message}`);
    }

    const usersToNotify = usersForNotification || [];
    console.log(
      `Found ${usersToNotify.length} users who used shields this week`,
    );

    // Reset shields for all users - with timeout
    const resetPromise = supabaseAdmin.rpc("reset_weekly_shields") as Promise<{
      data: { users_reset: number; shield_events_created: number }[] | null;
      error: Error | null;
    }>;

    const { data: resetResult, error: resetError } = await withTimeout(
      resetPromise,
      OPERATION_TIMEOUT_MS,
      "reset_weekly_shields",
    );

    if (resetError) {
      console.error("Error resetting shields:", resetError);
      result.errors.push(`Reset error: ${resetError.message}`);
      return new Response(
        JSON.stringify({
          success: false,
          error: resetError.message,
          result,
        }),
        {
          status: 500,
          headers,
        },
      );
    }

    if (resetResult && resetResult.length > 0) {
      result.usersReset = resetResult[0].users_reset;
      console.log(`Reset shields for ${result.usersReset} users`);
    }

    // Send notifications in batches with Promise.allSettled for resilience
    const userBatches = chunkArray(usersToNotify, NOTIFICATION_BATCH_SIZE);

    for (const batch of userBatches) {
      const notificationPromises = batch.map((user) =>
        supabaseAdmin.functions
          .invoke("send-notification", {
            body: {
              type: "shield_reset",
              recipientId: user.user_id,
              data: {
                shieldsMax: user.new_shields,
              },
            },
          })
          .then((res) => ({ userId: user.user_id, ...res }))
          .catch((err) => ({ userId: user.user_id, error: err })),
      );

      const batchResults = await Promise.allSettled(notificationPromises);

      for (const settledResult of batchResults) {
        if (settledResult.status === "fulfilled") {
          const value = settledResult.value as {
            userId: string;
            error?: Error;
          };
          if (!value.error) {
            result.notificationsSent++;
          } else {
            console.error(
              `Failed to notify user ${value.userId}:`,
              value.error,
            );
            result.errors.push(
              `Notify ${value.userId}: ${String(value.error)}`,
            );
          }
        } else {
          console.error("Notification promise rejected:", settledResult.reason);
          result.errors.push(
            `Batch notify error: ${String(settledResult.reason)}`,
          );
        }
      }
    }

    console.log(
      `Shield reset complete: ${result.usersReset} users reset, ${result.notificationsSent} notifications sent`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        result,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Reset shields error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal server error",
        // Don't expose raw error details in production
        code:
          error instanceof Error && error.message.includes("timed out")
            ? "OPERATION_TIMEOUT"
            : "INTERNAL_ERROR",
      }),
      { status: 500, headers },
    );
  }
});
