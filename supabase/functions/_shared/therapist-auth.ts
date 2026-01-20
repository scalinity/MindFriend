/**
 * Therapist API Authentication Utilities
 * Purpose: SHA-256 API key verification and permission checking
 * Security: Keys are hashed before storage, never stored in plaintext
 */

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

export interface APIKeyRecord {
  id: string;
  therapist_id: string;
  name: string;
  permissions: string[];
  rate_limit_per_hour: number;
  is_active: boolean;
  expires_at: string | null;
  therapist_accounts: {
    id: string;
    user_id: string;
    is_verified: boolean;
    practice_name: string | null;
  };
}

export interface AuthResult {
  success: boolean;
  therapistId?: string;
  apiKeyId?: string;
  permissions?: string[];
  rateLimitPerHour?: number;
  error?: string;
  errorCode?:
    | "INVALID_API_KEY"
    | "KEY_EXPIRED"
    | "THERAPIST_NOT_VERIFIED"
    | "KEY_INACTIVE";
}

/**
 * Hash API key with SHA-256 algorithm
 * @param apiKey - Raw API key string
 * @returns SHA-256 hash as hex string
 */
export async function hashAPIKey(apiKey: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(apiKey);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hashHex;
}

/**
 * Authenticate API key and return therapist information
 * @param supabase - Supabase client with service role
 * @param apiKey - Raw API key from X-API-Key header
 * @returns AuthResult with therapist info or error
 */
export async function authenticateAPIKey(
  supabase: SupabaseClient,
  apiKey: string | null,
): Promise<AuthResult> {
  // Validate API key is provided
  if (!apiKey) {
    return {
      success: false,
      error: "API key is required",
      errorCode: "INVALID_API_KEY",
    };
  }

  // Hash the key for lookup
  const keyHash = await hashAPIKey(apiKey);

  // Query API key record with therapist info
  const { data: apiKeyRecord, error } = await supabase
    .from("integration_api_keys")
    .select(
      `
      id,
      therapist_id,
      name,
      permissions,
      rate_limit_per_hour,
      is_active,
      expires_at,
      therapist_accounts!inner (
        id,
        user_id,
        is_verified,
        practice_name
      )
    `,
    )
    .eq("api_key_hash", keyHash)
    .single();

  if (error || !apiKeyRecord) {
    return {
      success: false,
      error: "Invalid API key",
      errorCode: "INVALID_API_KEY",
    };
  }

  // Check if key is active
  if (!apiKeyRecord.is_active) {
    return {
      success: false,
      error: "API key is inactive",
      errorCode: "KEY_INACTIVE",
    };
  }

  // Check if key has expired
  if (apiKeyRecord.expires_at) {
    const expiresAt = new Date(apiKeyRecord.expires_at);
    if (expiresAt < new Date()) {
      return {
        success: false,
        error: "API key has expired",
        errorCode: "KEY_EXPIRED",
      };
    }
  }

  // Check if therapist is verified
  const therapistAccount = Array.isArray(apiKeyRecord.therapist_accounts)
    ? apiKeyRecord.therapist_accounts[0]
    : apiKeyRecord.therapist_accounts;

  if (!therapistAccount?.is_verified) {
    return {
      success: false,
      error: "Therapist account is not verified",
      errorCode: "THERAPIST_NOT_VERIFIED",
    };
  }

  // Update last_used_at timestamp
  await supabase
    .from("integration_api_keys")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", apiKeyRecord.id);

  // Return successful authentication
  return {
    success: true,
    therapistId: apiKeyRecord.therapist_id,
    apiKeyId: apiKeyRecord.id,
    permissions: apiKeyRecord.permissions || [],
    rateLimitPerHour: apiKeyRecord.rate_limit_per_hour,
  };
}

/**
 * Check if therapist has permission for specific action
 * @param permissions - List of permissions from API key
 * @param required - Required permission string (e.g., 'read_mood')
 * @returns true if permission granted, false otherwise
 */
export function hasPermission(
  permissions: string[],
  required: string,
): boolean {
  return permissions.includes(required);
}

/**
 * Check if therapist has active connection with client and required permission
 * @param supabase - Supabase client
 * @param therapistId - Therapist account ID
 * @param clientId - Client user ID
 * @param permissionColumn - Permission column to check (e.g., 'share_mood')
 * @returns Connection ID if authorized, null otherwise
 */
export async function checkConnectionPermission(
  supabase: SupabaseClient,
  therapistId: string,
  clientId: string,
  permissionColumn?: string,
): Promise<string | null> {
  let query = supabase
    .from("therapy_connections")
    .select("id")
    .eq("therapist_id", therapistId)
    .eq("client_id", clientId)
    .eq("status", "active");

  // Add permission check if specified
  if (permissionColumn) {
    query = query.eq(permissionColumn, true);
  }

  const { data, error } = await query.single();

  if (error || !data) {
    return null;
  }

  return data.id;
}

/**
 * Generate structured API error response
 * @param errorCode - Error code constant
 * @param message - Human-readable error message
 * @param statusCode - HTTP status code
 * @returns Response object
 */
export function apiError(
  errorCode: string,
  message: string,
  statusCode: number,
): Response {
  return new Response(
    JSON.stringify({
      error: errorCode,
      message,
    }),
    {
      status: statusCode,
      headers: { "Content-Type": "application/json" },
    },
  );
}

/**
 * Generate structured API success response
 * @param data - Response data object
 * @param statusCode - HTTP status code (default 200)
 * @returns Response object
 */
export function apiSuccess(data: any, statusCode: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status: statusCode,
    headers: { "Content-Type": "application/json" },
  });
}
