// Shared authentication utilities for Edge Functions
// Reduces DRY violations across functions

import {
  createClient,
  SupabaseClient,
  User,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "./cors.ts";

export interface AuthResult {
  user: User;
  supabaseUser: SupabaseClient;
  supabaseAdmin: SupabaseClient;
}

export interface AuthError {
  response: Response;
}

/**
 * Authenticates a request and returns Supabase clients
 * Returns either AuthResult on success or AuthError on failure
 */
export async function authenticateRequest(
  req: Request,
): Promise<AuthResult | AuthError> {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return {
      response: new Response(
        JSON.stringify({ error: "Missing authorization" }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      ),
    };
  }

  const token = authHeader.replace("Bearer ", "");

  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  );

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Pass token explicitly to getUser() - calling without token requires an active session
  // which a freshly created client doesn't have
  const {
    data: { user },
    error: authError,
  } = await supabaseUser.auth.getUser(token);

  if (authError || !user) {
    console.error("Auth error:", authError?.message || "No user returned");
    return {
      response: new Response(
        JSON.stringify({
          code: 401,
          message: authError?.message || "Invalid JWT",
        }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      ),
    };
  }

  return { user, supabaseUser, supabaseAdmin };
}

/**
 * Type guard to check if auth result is an error
 */
export function isAuthError(
  result: AuthResult | AuthError,
): result is AuthError {
  return "response" in result;
}

/**
 * Check if request is authorized as a cron job or service role
 * Used by scheduled functions that also support manual triggers
 */
export function isAuthorizedCronRequest(
  headers: Headers,
  cronSecret: string,
  serviceRoleKey: string,
): boolean {
  // Check for cron secret in custom header
  const cronHeader = headers.get("x-cron-secret");
  if (cronHeader && cronSecret && cronHeader === cronSecret) {
    return true;
  }

  // Check for service role key in Authorization header
  const authHeader = headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ") && serviceRoleKey) {
    const token = authHeader.replace("Bearer ", "");
    if (token === serviceRoleKey) {
      return true;
    }
  }

  return false;
}

/**
 * UUID v4 format validation
 */
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isValidUUID(value: string): boolean {
  return UUID_REGEX.test(value);
}

/**
 * Creates a JSON error response
 */
export function errorResponse(
  error: string,
  message: string,
  status: number,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(JSON.stringify({ error, message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Creates a JSON success response
 */
export function successResponse(
  data: unknown,
  status: number,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
