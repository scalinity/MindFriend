/**
 * Therapist API Edge Function
 * Purpose: RESTful API for EHR/practice management integrations
 * Authentication: X-API-Key header (SHA-256 hashed)
 * Rate Limiting: 1000 requests/hour per API key
 * Audit Logging: All access logged to therapy_access_log table
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  authenticateAPIKey,
  hasPermission,
  checkConnectionPermission,
  apiError,
  apiSuccess,
} from "../_shared/therapist-auth.ts";
import {
  logAccess,
  createAuditEntry,
  AuditAction,
} from "../_shared/therapist-audit.ts";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Initialize Supabase client with service role
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    // Extract and authenticate API key
    const apiKey = req.headers.get("X-API-Key");
    const authResult = await authenticateAPIKey(supabase, apiKey);

    if (!authResult.success) {
      return apiError(
        authResult.errorCode!,
        authResult.error!,
        authResult.errorCode === "INVALID_API_KEY" ? 401 : 403,
      );
    }

    const { therapistId, permissions, rateLimitPerHour } = authResult;

    // Parse URL and route to handlers
    const url = new URL(req.url);
    const pathname = url.pathname.replace("/therapist-api", "");

    // SEC-HIGH-002: Implement rate limiting (check request count in last hour)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await supabase
      .from("therapy_access_log")
      .select("*", { count: "exact", head: true })
      .eq("therapist_id", therapistId)
      .gte("accessed_at", oneHourAgo);

    if (
      !countError &&
      count !== null &&
      rateLimitPerHour &&
      count >= rateLimitPerHour
    ) {
      return apiError(
        "RATE_LIMIT_EXCEEDED",
        `Rate limit of ${rateLimitPerHour} requests/hour exceeded. Please try again later.`,
        429,
      );
    }

    // Route handling
    if (pathname === "/clients" && req.method === "GET") {
      return await handleGetClients(req, supabase, therapistId!);
    } else if (
      pathname.match(/^\/clients\/[0-9a-fA-F-]+\/mood$/) &&
      req.method === "GET"
    ) {
      const clientId = pathname.split("/")[2];
      return await handleGetMood(
        req,
        supabase,
        therapistId!,
        clientId,
        permissions!,
      );
    } else if (
      pathname.match(/^\/clients\/[0-9a-fA-F-]+\/assessments$/) &&
      req.method === "GET"
    ) {
      const clientId = pathname.split("/")[2];
      return await handleGetAssessments(
        req,
        supabase,
        therapistId!,
        clientId,
        permissions!,
      );
    } else if (
      pathname.match(/^\/clients\/[0-9a-fA-F-]+\/assignments$/) &&
      req.method === "POST"
    ) {
      const clientId = pathname.split("/")[2];
      return await handleCreateAssignment(
        req,
        supabase,
        therapistId!,
        clientId,
        permissions!,
      );
    } else {
      return apiError("NOT_FOUND", `Endpoint ${pathname} not found`, 404);
    }
  } catch (error) {
    console.error("Therapist API error:", error);
    return apiError("INTERNAL_ERROR", "An internal error occurred", 500);
  }
});

/**
 * GET /clients - List all active client connections
 */
async function handleGetClients(
  req: Request,
  supabase: any,
  therapistId: string,
) {
  try {
    // Parse pagination params
    const url = new URL(req.url);
    const page = parseInt(url.searchParams.get("page") || "1");
    const limit = Math.min(
      parseInt(url.searchParams.get("limit") || "20"),
      100,
    );
    const offset = (page - 1) * limit;

    // Query active connections with client profiles
    const {
      data: connections,
      error,
      count,
    } = await supabase
      .from("therapy_connections")
      .select(
        `
        id,
        client_id,
        share_mood,
        share_journal,
        share_assessments,
        share_exercises,
        connected_at,
        profiles!therapy_connections_client_id_fkey (
          display_name,
          avatar_url
        )
      `,
        { count: "exact" },
      )
      .eq("therapist_id", therapistId)
      .eq("status", "active")
      .order("connected_at", { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error("Failed to fetch clients:", error);
      return apiError("DATABASE_ERROR", "Failed to fetch clients", 500);
    }

    // Format response
    const clients = connections.map((conn: any) => ({
      id: conn.id,
      clientId: conn.client_id,
      connectedAt: conn.connected_at,
      permissions: {
        shareMood: conn.share_mood,
        shareJournal: conn.share_journal,
        shareAssessments: conn.share_assessments,
        shareExercises: conn.share_exercises,
      },
      profile: {
        displayName: conn.profiles?.display_name || "Client",
        avatarUrl: conn.profiles?.avatar_url || null,
      },
    }));

    return apiSuccess({
      clients,
      pagination: {
        page,
        limit,
        total: count || 0,
        hasMore: (count || 0) > offset + limit,
      },
    });
  } catch (error) {
    console.error("handleGetClients error:", error);
    return apiError("INTERNAL_ERROR", "Failed to process request", 500);
  }
}

/**
 * GET /clients/:id/mood - Get client mood data (last 30 days)
 */
async function handleGetMood(
  req: Request,
  supabase: any,
  therapistId: string,
  clientId: string,
  permissions: string[],
) {
  try {
    // Check API key permission
    if (!hasPermission(permissions, "read_mood")) {
      return apiError(
        "PERMISSION_DENIED",
        "API key lacks read_mood permission",
        403,
      );
    }

    // Check connection and sharing permission
    const connectionId = await checkConnectionPermission(
      supabase,
      therapistId,
      clientId,
      "share_mood",
    );

    if (!connectionId) {
      return apiError(
        "PERMISSION_DENIED",
        "No active connection or mood sharing not enabled",
        403,
      );
    }

    // Parse date range params (default: last 30 days)
    const url = new URL(req.url);
    const fromDate =
      url.searchParams.get("from") ||
      new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const toDate = url.searchParams.get("to") || new Date().toISOString();

    // Query mood data
    const { data: moods, error } = await supabase
      .from("moods")
      .select("id, score, emotions, notes, logged_at")
      .eq("user_id", clientId)
      .gte("logged_at", fromDate)
      .lte("logged_at", toDate)
      .order("logged_at", { ascending: false });

    if (error) {
      console.error("Failed to fetch mood data:", error);
      return apiError("DATABASE_ERROR", "Failed to fetch mood data", 500);
    }

    // Log access
    await logAccess(
      supabase,
      createAuditEntry(
        req,
        connectionId,
        therapistId,
        "view_mood" as AuditAction,
        "mood",
        undefined,
      ),
    );

    return apiSuccess({ moods: moods || [] });
  } catch (error) {
    console.error("handleGetMood error:", error);
    return apiError("INTERNAL_ERROR", "Failed to process request", 500);
  }
}

/**
 * GET /clients/:id/assessments - Get client assessment results
 */
async function handleGetAssessments(
  req: Request,
  supabase: any,
  therapistId: string,
  clientId: string,
  permissions: string[],
) {
  try {
    // Check API key permission
    if (!hasPermission(permissions, "read_assessments")) {
      return apiError(
        "PERMISSION_DENIED",
        "API key lacks read_assessments permission",
        403,
      );
    }

    // Check connection and sharing permission
    const connectionId = await checkConnectionPermission(
      supabase,
      therapistId,
      clientId,
      "share_assessments",
    );

    if (!connectionId) {
      return apiError(
        "PERMISSION_DENIED",
        "No active connection or assessment sharing not enabled",
        403,
      );
    }

    // Parse limit param
    const url = new URL(req.url);
    const limit = Math.min(
      parseInt(url.searchParams.get("limit") || "20"),
      100,
    );

    // Query assessment data
    const { data: assessments, error } = await supabase
      .from("assessment_responses")
      .select(
        `
        id,
        score,
        severity,
        completed_at,
        answers,
        assessment_types (
          code,
          name,
          description
        )
      `,
      )
      .eq("user_id", clientId)
      .order("completed_at", { ascending: false })
      .limit(limit);

    if (error) {
      console.error("Failed to fetch assessments:", error);
      return apiError("DATABASE_ERROR", "Failed to fetch assessment data", 500);
    }

    // Log access
    await logAccess(
      supabase,
      createAuditEntry(
        req,
        connectionId,
        therapistId,
        "view_assessments" as AuditAction,
        "assessment",
        undefined,
      ),
    );

    return apiSuccess({ assessments: assessments || [] });
  } catch (error) {
    console.error("handleGetAssessments error:", error);
    return apiError("INTERNAL_ERROR", "Failed to process request", 500);
  }
}

/**
 * POST /clients/:id/assignments - Create new assignment
 */
async function handleCreateAssignment(
  req: Request,
  supabase: any,
  therapistId: string,
  clientId: string,
  permissions: string[],
) {
  try {
    // Check API key permission
    if (!hasPermission(permissions, "write_assignments")) {
      return apiError(
        "PERMISSION_DENIED",
        "API key lacks write_assignments permission",
        403,
      );
    }

    // Check connection exists and is active
    const connectionId = await checkConnectionPermission(
      supabase,
      therapistId,
      clientId,
    );

    if (!connectionId) {
      return apiError(
        "PERMISSION_DENIED",
        "No active connection with this client",
        403,
      );
    }

    // Parse request body
    const body = await req.json();

    // Validate required fields
    if (!body.title || body.title.trim().length === 0) {
      return apiError("VALIDATION_ERROR", "Title is required", 400);
    }

    if (
      !body.type ||
      !["exercise", "journal_prompt", "mood_tracking", "custom"].includes(
        body.type,
      )
    ) {
      return apiError("VALIDATION_ERROR", "Invalid assignment type", 400);
    }

    // Validate type-specific requirements
    if (body.type === "exercise" && !body.exerciseId) {
      return apiError(
        "VALIDATION_ERROR",
        "Exercise ID required for exercise assignments",
        400,
      );
    }

    if (body.type === "journal_prompt" && !body.journalPrompt) {
      return apiError(
        "VALIDATION_ERROR",
        "Journal prompt required for journal_prompt assignments",
        400,
      );
    }

    // Insert assignment
    const { data: assignment, error } = await supabase
      .from("therapist_assignments")
      .insert({
        connection_id: connectionId,
        title: body.title.trim(),
        description: body.description?.trim() || null,
        assignment_type: body.type,
        exercise_id: body.exerciseId || null,
        journal_prompt: body.journalPrompt || null,
        due_date: body.dueDate || null,
        frequency: body.frequency || "once",
      })
      .select()
      .single();

    if (error) {
      console.error("Failed to create assignment:", error);
      return apiError("DATABASE_ERROR", "Failed to create assignment", 500);
    }

    // Log access
    await logAccess(
      supabase,
      createAuditEntry(
        req,
        connectionId,
        therapistId,
        "create_assignment" as AuditAction,
        "assignment",
        assignment.id,
      ),
    );

    // TODO: Send push notification to client

    return apiSuccess({ assignment }, 201);
  } catch (error) {
    console.error("handleCreateAssignment error:", error);
    return apiError("INTERNAL_ERROR", "Failed to process request", 500);
  }
}
