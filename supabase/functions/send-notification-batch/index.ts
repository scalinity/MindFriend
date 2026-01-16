// MindFriend Batch Notification Edge Function
// Sends notifications to multiple recipients in a single request
// Used by iOS for circle activity notifications to reduce N+1 calls
// See: specs/04-smart-notifications.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
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
  reason?: string;
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
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate authorization
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
    } = await supabaseAdmin.auth.getUser(token);

    if (!user) {
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

    // For circle_activity notifications, validate sender is a member of the circle
    if (body.type === "circle_activity" && body.data?.circleId) {
      const { data: membership, error: membershipError } = await supabaseAdmin
        .from("circle_members")
        .select("id")
        .eq("circle_id", body.data.circleId)
        .eq("user_id", user.id)
        .maybeSingle();

      if (membershipError || !membership) {
        log.warn("Circle membership validation failed", {
          userId: user.id.slice(0, 8),
          circleId: body.data.circleId.slice(0, 8),
        });
        return new Response(
          JSON.stringify({
            error: "Not authorized to send notifications for this circle",
            code: "NOT_CIRCLE_MEMBER",
          }),
          { status: 403, headers },
        );
      }
    }

    // Call send-notification for each recipient in parallel
    // Using the internal Edge Function invoke (which bypasses rate limiting for service calls)
    const results: BatchResult[] = [];
    const sendPromises = body.recipientIds.map(async (recipientId) => {
      try {
        const response = await supabaseAdmin.functions.invoke(
          "send-notification",
          {
            body: {
              type: body.type,
              recipientId,
              data: {
                ...body.data,
                senderId: user.id, // Always set sender from authenticated user
              },
            },
          },
        );

        if (response.error) {
          return {
            recipientId,
            success: false,
            reason: response.error.message,
          };
        }

        const result = response.data as {
          success: boolean;
          skipped?: boolean;
          reason?: string;
        };
        return {
          recipientId,
          success: result.success && !result.skipped,
          skipped: result.skipped,
          reason: result.reason,
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
    const failed = results.filter((r) => !r.success && !r.skipped).length;

    log.info("Batch notification complete", { sent, skipped, failed });

    return new Response(
      JSON.stringify({
        success: true,
        results,
        sent,
        skipped,
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
