// Request validation utilities for MindFriend Edge Functions
// Provides safe extraction of auth tokens and JSON body parsing

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Extract and validate Authorization header
 * Prevents crashes from missing or malformed headers
 *
 * @param req - The incoming request
 * @returns JWT token or null if missing/invalid
 */
export function extractAuthToken(req: Request): string | null {
  const authHeader = req.headers.get("Authorization");
  
  if (!authHeader) {
    return null;
  }

  // Check for "Bearer " prefix
  if (!authHeader.startsWith("Bearer ")) {
    return null;
  }

  const token = authHeader.substring(7).trim(); // Remove "Bearer " prefix
  
  if (!token) {
    return null;
  }

  return token;
}

/**
 * Safely parse JSON body with error handling
 * Prevents crashes from malformed JSON
 *
 * @param req - The incoming request
 * @returns Parsed JSON object or null if parsing fails
 */
export async function safeParseJson<T = Record<string, unknown>>(
  req: Request,
): Promise<T | null> {
  try {
    return await req.json();
  } catch (_error) {
    return null;
  }
}

/**
 * Authenticate user and return user object
 * Handles all error cases including missing token and invalid token
 *
 * @param req - The incoming request
 * @param supabase - Supabase client (with service role key)
 * @returns User object or error details
 */
export async function authenticateRequest(
  req: Request,
  supabase: SupabaseClient,
): Promise<
  | { success: true; user: { id: string; email?: string } }
  | { success: false; status: number; error: string }
> {
  const token = extractAuthToken(req);

  if (!token) {
    return {
      success: false,
      status: 401,
      error: "Missing or invalid Authorization header",
    };
  }

  try {
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return {
        success: false,
        status: 401,
        error: "Unauthorized",
      };
    }

    return {
      success: true,
      user,
    };
  } catch (_error) {
    return {
      success: false,
      status: 401,
      error: "Invalid authentication token",
    };
  }
}
