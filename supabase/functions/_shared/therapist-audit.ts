/**
 * Therapist Audit Logging Utilities
 * Purpose: Record all therapist data access for HIPAA compliance
 * Retention: 7 years minimum (configurable)
 * Security: Append-only, service role access required
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type AuditAction =
  | "view_mood"
  | "view_journal"
  | "view_assessments"
  | "view_exercises"
  | "export_data"
  | "create_assignment"
  | "update_assignment"
  | "crisis_alert_sent"
  | "connection_created"
  | "connection_revoked"
  | "permissions_changed";

export interface AuditLogEntry {
  connectionId: string;
  therapistId: string;
  action: AuditAction;
  resourceType?: string;
  resourceId?: string;
  ipAddress?: string;
  userAgent?: string;
}

/**
 * Log therapist data access event
 * @param supabase - Supabase client with service role
 * @param entry - Audit log entry details
 * @returns Log entry ID or null on failure
 */
export async function logAccess(
  supabase: SupabaseClient,
  entry: AuditLogEntry,
): Promise<string | null> {
  try {
    const { data, error } = await supabase
      .from("therapy_access_log")
      .insert({
        connection_id: entry.connectionId,
        therapist_id: entry.therapistId,
        action: entry.action,
        resource_type: entry.resourceType || null,
        resource_id: entry.resourceId || null,
        ip_address: entry.ipAddress || null,
        user_agent: entry.userAgent || null,
      })
      .select("id")
      .single();

    if (error) {
      console.error("Failed to log audit event:", error);
      return null;
    }

    return data?.id || null;
  } catch (error) {
    console.error("Exception during audit logging:", error);
    return null;
  }
}

/**
 * Log multiple access events in batch (for bulk operations)
 * @param supabase - Supabase client with service role
 * @param entries - Array of audit log entries
 * @returns Number of successfully logged entries
 */
export async function logAccessBatch(
  supabase: SupabaseClient,
  entries: AuditLogEntry[],
): Promise<number> {
  if (entries.length === 0) return 0;

  try {
    const records = entries.map((entry) => ({
      connection_id: entry.connectionId,
      therapist_id: entry.therapistId,
      action: entry.action,
      resource_type: entry.resourceType || null,
      resource_id: entry.resourceId || null,
      ip_address: entry.ipAddress || null,
      user_agent: entry.userAgent || null,
    }));

    const { data, error } = await supabase
      .from("therapy_access_log")
      .insert(records)
      .select("id");

    if (error) {
      console.error("Failed to log batch audit events:", error);
      return 0;
    }

    return data?.length || 0;
  } catch (error) {
    console.error("Exception during batch audit logging:", error);
    return 0;
  }
}

/**
 * Extract IP address from request headers
 * Handles various proxy headers (Cloudflare, AWS, etc.)
 * @param req - Request object
 * @returns IP address or null
 */
export function extractIPAddress(req: Request): string | null {
  // Check common proxy headers
  const headers = [
    "cf-connecting-ip", // Cloudflare
    "x-real-ip", // Nginx
    "x-forwarded-for", // Standard proxy header
  ];

  for (const header of headers) {
    const value = req.headers.get(header);
    if (value) {
      // x-forwarded-for can have multiple IPs, take the first one
      return value.split(",")[0].trim();
    }
  }

  return null;
}

/**
 * Extract user agent from request headers
 * @param req - Request object
 * @returns User agent string or null
 */
export function extractUserAgent(req: Request): string | null {
  return req.headers.get("user-agent");
}

/**
 * Create audit log entry from request context
 * @param req - Request object
 * @param connectionId - Connection ID
 * @param therapistId - Therapist account ID
 * @param action - Action being performed
 * @param resourceType - Optional resource type
 * @param resourceId - Optional resource ID
 * @returns AuditLogEntry object ready for logging
 */
export function createAuditEntry(
  req: Request,
  connectionId: string,
  therapistId: string,
  action: AuditAction,
  resourceType?: string,
  resourceId?: string,
): AuditLogEntry {
  return {
    connectionId,
    therapistId,
    action,
    resourceType,
    resourceId,
    ipAddress: extractIPAddress(req),
    userAgent: extractUserAgent(req),
  };
}

/**
 * Log and return - convenience function for one-liner logging
 * Usage: return await logAndReturn(supabase, entry, response)
 * @param supabase - Supabase client
 * @param entry - Audit log entry
 * @param response - Response to return to client
 * @returns The response (after logging completes)
 */
export async function logAndReturn(
  supabase: SupabaseClient,
  entry: AuditLogEntry,
  response: Response,
): Promise<Response> {
  // Log asynchronously but don't block the response
  logAccess(supabase, entry).catch((error) => {
    console.error("Async audit logging failed:", error);
  });

  return response;
}

/**
 * Format action for human-readable display
 * @param action - Audit action constant
 * @returns Human-readable description
 */
export function formatAction(action: AuditAction): string {
  const actionMap: Record<AuditAction, string> = {
    view_mood: "Viewed mood data",
    view_journal: "Viewed journal entries",
    view_assessments: "Viewed assessment results",
    view_exercises: "Viewed exercise history",
    export_data: "Exported client data",
    create_assignment: "Created assignment",
    update_assignment: "Updated assignment",
    crisis_alert_sent: "Received crisis alert",
    connection_created: "Connection established",
    connection_revoked: "Connection revoked",
    permissions_changed: "Sharing permissions changed",
  };

  return actionMap[action] || action;
}

/**
 * Query audit log for specific connection
 * @param supabase - Supabase client (user context, RLS enforced)
 * @param connectionId - Connection ID
 * @param limit - Maximum number of entries to return
 * @returns Array of audit log entries
 */
export async function getAuditLog(
  supabase: SupabaseClient,
  connectionId: string,
  limit: number = 100,
): Promise<any[]> {
  const { data, error } = await supabase
    .from("therapy_access_log")
    .select("*")
    .eq("connection_id", connectionId)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) {
    console.error("Failed to retrieve audit log:", error);
    return [];
  }

  return data || [];
}
