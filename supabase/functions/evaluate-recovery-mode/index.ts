// Recovery Mode Evaluation Edge Function
// Daily cron job that evaluates auto-entry/exit conditions for all users
// See: kimispecs/03-recovery-mode-ux-spec.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface EvaluationResult {
  userId: string;
  action: "enter" | "exit" | "none";
  reason: string;
  previousState: boolean;
  newState: boolean;
}

interface CronResponse {
  success: boolean;
  processedUsers: number;
  entered: number;
  exited: number;
  unchanged: number;
  errors: number;
  results: EvaluationResult[];
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
    // Initialize Supabase client with service role (this is a cron job)
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate this is a service role call (cron jobs use service role)
    const authHeader = req.headers.get("Authorization");
    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

      // Constant-time comparison
      const tokenBytes = new TextEncoder().encode(token);
      const keyBytes = new TextEncoder().encode(serviceRoleKey);
      let isServiceRole = tokenBytes.length === keyBytes.length;
      if (isServiceRole) {
        let diff = 0;
        for (let i = 0; i < tokenBytes.length; i++) {
          diff |= tokenBytes[i] ^ keyBytes[i];
        }
        isServiceRole = diff === 0;
      }

      if (!isServiceRole) {
        // Validate as authenticated user for manual trigger (testing)
        const {
          data: { user },
        } = await supabaseAdmin.auth.getUser(token);
        if (!user) {
          return new Response(JSON.stringify({ error: "Unauthorized" }), {
            status: 401,
            headers,
          });
        }
        // For authenticated users, only evaluate their own state
        const result = await evaluateUserRecoveryMode(supabaseAdmin, user.id);
        return new Response(
          JSON.stringify({
            success: true,
            processedUsers: 1,
            entered: result.action === "enter" ? 1 : 0,
            exited: result.action === "exit" ? 1 : 0,
            unchanged: result.action === "none" ? 1 : 0,
            errors: 0,
            results: [result],
          }),
          { status: 200, headers },
        );
      }
    }

    // Service role: process all users with recent mood activity
    console.log("[Recovery Mode Cron] Starting evaluation...");

    // Get all users who have logged moods in the last 7 days
    // This is more efficient than evaluating all users
    const { data: activeUsers, error: usersError } = await supabaseAdmin
      .from("moods")
      .select("user_id")
      .gte(
        "created_at",
        new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
      )
      .order("user_id");

    if (usersError) {
      console.error(
        "[Recovery Mode Cron] Error fetching active users:",
        usersError,
      );
      return new Response(
        JSON.stringify({ error: "Failed to fetch active users" }),
        { status: 500, headers },
      );
    }

    // Deduplicate user IDs
    const uniqueUserIds = [
      ...new Set(activeUsers?.map((m) => m.user_id) || []),
    ];
    console.log(
      `[Recovery Mode Cron] Processing ${uniqueUserIds.length} active users`,
    );

    const results: EvaluationResult[] = [];
    let entered = 0;
    let exited = 0;
    let unchanged = 0;
    let errors = 0;

    // Process users in batches of 50 to avoid overwhelming the database
    const batchSize = 50;
    for (let i = 0; i < uniqueUserIds.length; i += batchSize) {
      const batch = uniqueUserIds.slice(i, i + batchSize);

      const batchResults = await Promise.all(
        batch.map(async (userId) => {
          try {
            return await evaluateUserRecoveryMode(supabaseAdmin, userId);
          } catch (error) {
            console.error(
              `[Recovery Mode Cron] Error processing user ${userId}:`,
              error,
            );
            return {
              userId,
              action: "none" as const,
              reason: `error: ${error instanceof Error ? error.message : "unknown"}`,
              previousState: false,
              newState: false,
            };
          }
        }),
      );

      for (const result of batchResults) {
        results.push(result);
        if (result.action === "enter") entered++;
        else if (result.action === "exit") exited++;
        else if (result.reason.startsWith("error:")) errors++;
        else unchanged++;
      }
    }

    const response: CronResponse = {
      success: true,
      processedUsers: uniqueUserIds.length,
      entered,
      exited,
      unchanged,
      errors,
      results: results.filter((r) => r.action !== "none"), // Only return changes for logging
    };

    console.log(
      `[Recovery Mode Cron] Complete: ${entered} entered, ${exited} exited, ${unchanged} unchanged, ${errors} errors`,
    );

    return new Response(JSON.stringify(response), { status: 200, headers });
  } catch (error) {
    console.error("[Recovery Mode Cron] Unhandled error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});

async function evaluateUserRecoveryMode(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<EvaluationResult> {
  // Call the database function that handles the evaluation logic
  const { data, error } = await supabase.rpc(
    "evaluate_recovery_mode_for_user",
    {
      p_user_id: userId,
    },
  );

  if (error) {
    console.error(`[Recovery Mode] RPC error for user ${userId}:`, error);
    throw error;
  }

  // The function returns a single row
  const result = data?.[0];
  if (!result) {
    return {
      userId,
      action: "none",
      reason: "no_result",
      previousState: false,
      newState: false,
    };
  }

  return {
    userId,
    action: result.action as "enter" | "exit" | "none",
    reason: result.reason || "",
    previousState: result.previous_state || false,
    newState: result.new_state || false,
  };
}
