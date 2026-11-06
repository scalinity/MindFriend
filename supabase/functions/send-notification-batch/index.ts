// MindFriend Batch Notification Edge Function
// Sends notifications to multiple recipients in a single request
// Used by iOS for circle activity notifications to reduce N+1 calls
// See: specs/04-smart-notifications.md

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";
import { createLogger } from "../_shared/logger.ts";

const log = createLogger("send-notification-batch");

// Max recipients per batch request
const MAX_BATCH_SIZE = 50;

// Rate limit: 10 batch requests per minute per user
const BATCH_RATE_LIMIT = {
  windowMs: 60 * 1000,
  maxRequests: 10,
};

type NotificationType =
  | "circle_activity"
  | "hug"
  | "streak_risk"
  | "weekly_summary"
  | "challenge";

interface BatchNotificationRequest {
  type: NotificationType;
  recipientIds: string[];
  data: {
    senderId?: string;
    senderName?: string;
    circleId?: string;
    circleName?: string;
    challengeTitle?: string;
    completions?: number;
  };
}

interface BatchResult {
  recipientId: string;
  success: boolean;
  skipped?: boolean;
  queued?: boolean;
  reason?: string;
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
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate authorization
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ") || !authHeader.slice(7)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    // Rate limiting check
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "notification-batch",
      BATCH_RATE_LIMIT,
    );

    if (!rateLimitResult.allowed) {
      log.warn("Rate limit exceeded", { userId: user.id.slice(0, 8) });
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          retryAfter: rateLimitResult.retryAfter,
        }),
        {
          status: 429,
          headers: {
            ...headers,
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    // Parse and validate request
    const body: BatchNotificationRequest = await req.json();

    if (!body.type || !body.recipientIds || !Array.isArray(body.recipientIds)) {
      return new Response(
        JSON.stringify({ error: "Missing type or recipientIds array" }),
        { status: 400, headers },
      );
    }

    if (body.recipientIds.some((id) => typeof id !== "string" || !id)) {
      return new Response(JSON.stringify({ error: "Invalid recipientIds" }), {
        status: 400,
        headers,
      });
    }
    // Match database UUID formatting when filtering Swift's uppercase UUIDs.
    body.recipientIds = body.recipientIds.map((id) => id.toLowerCase());

    if (body.recipientIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, results: [], sent: 0 }),
        { status: 200, headers },
      );
    }

    if (body.recipientIds.length > MAX_BATCH_SIZE) {
      return new Response(
        JSON.stringify({
          error: `Batch size exceeds maximum of ${MAX_BATCH_SIZE}`,
        }),
        { status: 400, headers },
      );
    }

    // iOS batches only circle activity, hugs and challenge notifications.
    // Every batch requires the same sender/circle boundary as a single send.
    if (!["circle_activity", "hug", "challenge"].includes(body.type)) {
      return new Response(
        JSON.stringify({ error: "Forbidden notification type" }),
        {
          status: 403,
          headers,
        },
      );
    }
    if (!body.data?.circleId || typeof body.data.circleId !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing circleId for circle notification" }),
        {
          status: 400,
          headers,
        },
      );
    }
    const { data: membership, error: membershipError } = await supabaseAdmin
      .from("circle_members")
      .select("id")
      .eq("circle_id", body.data.circleId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (membershipError || !membership) {
      return new Response(
        JSON.stringify({ error: "Not authorized for this circle" }),
        {
          status: 403,
          headers,
        },
      );
    }

    // SECURITY FIX #002: Filter recipients to only valid circle members
    const CIRCLE_SCOPED_TYPES: NotificationType[] = [
      "circle_activity",
      "hug",
      "challenge",
    ];
    if (body.data?.circleId && CIRCLE_SCOPED_TYPES.includes(body.type)) {
      const { data: validMembers, error: membersError } = await supabaseAdmin
        .from("circle_members")
        .select("user_id")
        .eq("circle_id", body.data.circleId)
        .in("user_id", body.recipientIds);

      if (membersError) {
        return new Response(
          JSON.stringify({ error: "Unable to validate recipients" }),
          {
            status: 403,
            headers,
          },
        );
      }
      const validSet = new Set((validMembers || []).map((m) => m.user_id));
      const filteredIds = body.recipientIds.filter((id) => validSet.has(id));

      if (filteredIds.length === 0) {
        log.info("No valid recipients in circle", {
          circleId: body.data.circleId.slice(0, 8),
          requestedCount: body.recipientIds.length,
        });
        return new Response(
          JSON.stringify({
            success: true,
            results: [],
            sent: 0,
            reason: "no_valid_recipients",
          }),
          { status: 200, headers },
        );
      }

      // Update to only include valid members
      body.recipientIds = filteredIds;
    }

    // SECURITY FIX #002: Forward user JWT to send-notification (don't use service role bypass)
    const fnUrl = `${
      Deno.env.get("SUPABASE_URL")
    }/functions/v1/send-notification`;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const results: BatchResult[] = [];
    const sendPromises = body.recipientIds.map(async (recipientId) => {
      try {
        // Use direct fetch with USER JWT to ensure per-user rate limiting is enforced
        const response = await fetch(fnUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            // Forward USER JWT for per-user rate limiting
            Authorization: authHeader,
            // apikey required by Supabase gateway
            apikey: serviceRoleKey,
          },
          body: JSON.stringify({
            type: body.type,
            recipientId,
            data: {
              ...body.data,
              senderId: user.id, // Always set sender from authenticated user
            },
          }),
        });

        const result = (await response.json()) as {
          success?: boolean;
          skipped?: boolean;
          sent?: boolean;
          queued?: boolean;
          reason?: string;
          error?: string;
        };

        if (!response.ok || result.error) {
          return {
            recipientId,
            success: false,
            reason: result.error || `HTTP ${response.status}`,
          };
        }

        return {
          recipientId,
          success: result.success === true && result.sent === true &&
            !result.skipped && !result.queued,
          skipped: result.skipped,
          queued: result.queued,
          reason: result.reason ??
            (result.sent === false && !result.skipped && !result.queued
              ? "Delivery failed"
              : undefined),
        };
      } catch (err) {
        log.error("Error sending notification", {
          recipientId: recipientId.slice(0, 8),
          error: err instanceof Error ? err.message : "Unknown",
        });
        return {
          recipientId,
          success: false,
          reason: err instanceof Error ? err.message : "Unknown error",
        };
      }
    });

    const allResults = await Promise.allSettled(sendPromises);

    for (const result of allResults) {
      if (result.status === "fulfilled") {
        results.push(result.value);
      } else {
        // Promise rejected (shouldn't happen with our try/catch, but just in case)
        results.push({
          recipientId: "unknown",
          success: false,
          reason: result.reason?.message || "Promise rejected",
        });
      }
    }

    const sent = results.filter((r) => r.success).length;
    const skipped = results.filter((r) => r.skipped).length;
    const queued = results.filter((r) => r.queued).length;
    const failed = results.filter((r) =>
      !r.success && !r.skipped && !r.queued
    ).length;

    log.info("Batch notification complete", { sent, skipped, queued, failed });

    return new Response(
      JSON.stringify({
        success: true,
        results,
        sent,
        skipped,
        queued,
        failed,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    log.error("Batch notification error", {
      error: error instanceof Error ? error.message : "Unknown",
    });
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
