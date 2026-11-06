// Recovery Mode Evaluation Edge Function
// Daily cron job that evaluates auto-entry/exit conditions for all users
// See: kimispecs/03-recovery-mode-ux-spec.md

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  authenticateRequest,
  isAuthError,
  isAuthorizedCronRequest,
} from "../_shared/auth.ts";

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

Deno.serve(async (req) => {
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
    const isScheduled = await isAuthorizedCronRequest(
      req.headers,
      Deno.env.get("CRON_SECRET") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    if (!isScheduled) {
      const auth = await authenticateRequest(req);
      if (isAuthError(auth)) return auth.response;
      const result = await evaluateUserRecoveryMode(
        auth.supabaseUser,
        auth.user.id,
      );
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

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const uniqueUserIds = await recoveryCandidateUserIds(supabaseAdmin);

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
              reason: `error: ${
                error instanceof Error ? error.message : "unknown"
              }`,
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
  supabase: SupabaseClient,
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

  return parseRecoveryEvaluation(data, userId);
}

/** The SQL RPC returns a JSON object, not a table row array. Reject invalid state instead of inventing it. */
export function parseRecoveryEvaluation(
  data: unknown,
  userId: string,
): EvaluationResult {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("Invalid recovery evaluation result");
  }
  const result = data as Record<string, unknown>;
  if (
    !["enter", "exit", "none"].includes(String(result.action)) ||
    typeof result.reason !== "string" ||
    typeof result.previous_state !== "boolean" ||
    typeof result.new_state !== "boolean"
  ) {
    throw new Error("Invalid recovery evaluation result");
  }
  return {
    userId,
    action: result.action as EvaluationResult["action"],
    reason: result.reason,
    previousState: result.previous_state,
    newState: result.new_state,
  };
}

async function recoveryCandidateUserIds(
  supabase: SupabaseClient,
): Promise<string[]> {
  const ids = new Set<string>();
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  for (const table of ["moods", "user_settings"] as const) {
    for (let offset = 0;; offset += 1000) {
      let query = supabase.from(table).select("user_id").order("user_id").order(
        "id",
      );
      query = table === "moods"
        ? query.gte("created_at", since)
        : query.eq("recovery_mode_active", true);
      const { data, error } = await query.range(offset, offset + 999);
      if (error) throw error;
      for (const row of data ?? []) ids.add(row.user_id);
      if (!data || data.length < 1000) break;
    }
  }
  return [...ids];
}
