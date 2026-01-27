// Toggle Vacation Mode Edge Function
// Enables or disables vacation mode (streak freeze) for users

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

const OPERATION_TIMEOUT_MS = 15000; // 15s timeout for database operations

/**
 * Creates a promise that rejects after the specified timeout
 * Properly handles Supabase PostgrestBuilder which implements PromiseLike
 */
function withTimeout<T>(
  promiseOrBuilder: Promise<T> | PromiseLike<T>,
  timeoutMs: number,
  operation: string,
): Promise<T> {
  const promise = Promise.resolve(promiseOrBuilder);
  
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

interface ToggleVacationRequest {
  action: "activate" | "deactivate";
  startDate?: string; // ISO date string (YYYY-MM-DD), required for activate
  endDate?: string; // ISO date string (YYYY-MM-DD), required for activate
  reason?: string; // Optional reason
}

interface VacationModeResponse {
  id: string;
  isActive: boolean;
  startDate: string;
  endDate: string;
  daysCount: number;
}

serve(async (req) => {
  const headers = getCorsHeaders(req.headers.get("Origin"));

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers });
  }

  try {
    // Validate authorization
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    // Parse request body with error handling (P1 fix: prevent crash on malformed JSON)
    let body: ToggleVacationRequest;
    try {
      body = await req.json();
    } catch (error) {
      return new Response(
        JSON.stringify({ error: "Invalid JSON in request body" }),
        {
          status: 400,
          headers: { ...headers, "Content-Type": "application/json" },
        },
      );
    }
    
    const { action, startDate, endDate, reason } = body;

    // Validate action
    if (!action || (action !== "activate" && action !== "deactivate")) {
      return new Response(
        JSON.stringify({
          error: "Invalid action. Must be 'activate' or 'deactivate'",
        }),
        {
          status: 400,
          headers: { ...headers, "Content-Type": "application/json" },
        },
      );
    }

    if (action === "activate") {
      // Validate dates BEFORE passing them
      if (!startDate || !endDate) {
        return new Response(
          JSON.stringify({ error: "startDate and endDate are required for activation" }),
          {
            status: 400,
            headers: { ...headers, "Content-Type": "application/json" },
          },
        );
      }
      
      return await activateVacation(
        supabase,
        user.id,
        startDate,
        endDate,
        reason,
        headers,
      );
    } else {
      return await deactivateVacation(supabase, user.id, headers);
    }
  } catch (error) {
    console.error("Toggle vacation error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
      }),
      {
        status: 500,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }
});

async function activateVacation(
  supabase: SupabaseClient,
  userId: string,
  startDate: string,
  endDate: string,
  reason: string | undefined,
  headers: Record<string, string>,
): Promise<Response> {
  // Check user's subscription tier before enforcing quota (with timeout)
  const { data: subscription, error: subError } = await withTimeout(
    supabase
      .from("subscriptions")
      .select("tier, is_active")
      .eq("user_id", userId)
      .eq("is_active", true)
      .single(),
    OPERATION_TIMEOUT_MS,
    "subscription check",
  );
  
  if (subError && subError.code !== "PGRST116") {
    console.error("Subscription check error:", subError.code);
    // Continue with free tier assumption on error
  }
  
  const isPremium = subscription?.tier === "premium" && subscription?.is_active === true;
  
  // Rate limiting: Only enforce for free tier users
  if (!isPremium) {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const { data: recentVacations, error: countError } = await withTimeout(
      supabase
        .from("vacation_mode")
        .select("id", { count: "exact", head: false })
        .eq("user_id", userId)
        .gte("created_at", thirtyDaysAgo.toISOString()),
    OPERATION_TIMEOUT_MS,
      "rate limit check",
    );
    
    if (countError) {
      console.error("Count error:", countError);
      return new Response(
        JSON.stringify({ error: "Failed to check vacation quota" }),
        {
          status: 500,
          headers: { ...headers, "Content-Type": "application/json" },
        },
      );
    }
    
    // Free tier limit: 1 vacation per month
    if (recentVacations && recentVacations.length >= 1) {
      return new Response(
        JSON.stringify({
          error: "quota_exceeded",
          message: "Free tier allows 1 vacation per month. Upgrade to Premium for unlimited vacations.",
        }),
        {
          status: 429,
          headers: { ...headers, "Content-Type": "application/json" },
        },
      );
    }
  }

  // Parse dates
  const start = new Date(startDate);
  const end = new Date(endDate);

  // Validate date range
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return new Response(
      JSON.stringify({ error: "Invalid date format" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Calculate days difference using Math.floor to match iOS dateComponents logic
  // iOS uses: dateComponents([.day], from: start, to: end).day + 1
  // This ensures Jan 1 to Jan 7 = 6 days diff, then +1 = 7 days total (inclusive)
  const daysDiff = Math.floor(
    (end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24),
  );

  if (daysDiff < 0) {
    return new Response(
      JSON.stringify({ error: "End date must be after start date" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Check >= 14 instead of > 14 because we return daysDiff + 1
  // This prevents 15-day vacations (daysDiff=14, returned daysCount=15)
  if (daysDiff >= 14) {
    return new Response(
      JSON.stringify({ error: "Maximum vacation duration is 14 days" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Check for overlapping active vacations (with timeout)
  const { data: existing } = await withTimeout(
    supabase
      .from("vacation_mode")
      .select("*")
      .eq("user_id", userId)
      .eq("is_active", true)
      .single(),
    OPERATION_TIMEOUT_MS,
    "overlap check",
  );

  if (existing) {
    return new Response(
      JSON.stringify({
        error: "You already have an active vacation",
      }),
      {
        status: 409,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Get current streak value (with timeout)
  const { data: stats } = await withTimeout(
    supabase
      .from("user_stats")
      .select("current_streak_days")
      .eq("user_id", userId)
      .single(),
    OPERATION_TIMEOUT_MS,
    "streak fetch",
  );

  // Sanitize reason field to prevent XSS/injection
  const sanitizedReason = reason 
    ? reason.trim().substring(0, 200).replace(/[<>]/g, '') 
    : null;

  // Create vacation mode entry (with timeout)
  const { data: vacation, error: insertError } = await withTimeout(
    supabase
      .from("vacation_mode")
      .insert({
        user_id: userId,
        start_date: startDate,
        end_date: endDate,
        is_active: true,
        reason: sanitizedReason,
        streak_on_activation: stats?.current_streak_days || 0,
      })
      .select()
      .single(),
    OPERATION_TIMEOUT_MS,
    "vacation insert",
  );

  if (insertError) {
    console.error("Insert error:", insertError);
    return new Response(
      JSON.stringify({
        error: "Failed to create vacation mode",
      }),
      {
        status: 500,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Return success response
  const response: VacationModeResponse = {
    id: vacation.id,
    isActive: vacation.is_active,
    startDate: vacation.start_date,
    endDate: vacation.end_date,
    daysCount: daysDiff + 1,
  };

  return new Response(JSON.stringify({ success: true, vacation: response }), {
    status: 200,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

async function deactivateVacation(
  supabase: SupabaseClient,
  userId: string,
  headers: Record<string, string>,
): Promise<Response> {
  // Deactivate all active vacations for user (with timeout)
  const { error: updateError } = await withTimeout(
    supabase
      .from("vacation_mode")
      .update({
        is_active: false,
        deactivated_at: new Date().toISOString(),
      })
      .eq("user_id", userId)
      .eq("is_active", true),
    OPERATION_TIMEOUT_MS,
    "vacation deactivate",
  );

  if (updateError) {
    console.error("Update error:", updateError.code);
    return new Response(
      JSON.stringify({
        error: "Failed to deactivate vacation mode",
      }),
      {
        status: 500,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  return new Response(
    JSON.stringify({
      success: true,
      message: "Vacation mode deactivated",
    }),
    {
      status: 200,
      headers: { ...headers, "Content-Type": "application/json" },
    },
  );
}
