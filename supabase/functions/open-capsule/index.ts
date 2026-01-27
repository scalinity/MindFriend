// Open Time Capsule Edge Function
// Fetches capsule data, marks as opened, returns journey comparison

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  captureUserSnapshot,
  calculateHighlights,
  UserSnapshot,
  DEFAULT_SNAPSHOT,
} from "../_shared/capsule-utils.ts";
import {
  logError,
  createErrorResponse,
  createCustomErrorResponse,
} from "../_shared/error-logger.ts";
import {
  checkRateLimit,
  createRateLimitResponse,
} from "../_shared/rate-limiter.ts";

interface OpenCapsuleRequest {
  capsuleId: string;
}

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // SECURITY: Rate limiting (10 requests per minute)
    if (!checkRateLimit(user.id, 10, 60000)) {
      return createRateLimitResponse(60);
    }

    // Parse request
    const body: OpenCapsuleRequest = await req.json();

    // Fetch capsule with snapshots and media
    const { data: capsule, error: fetchError } = await supabase
      .from("time_capsules")
      .select(
        `
        *,
        capsule_snapshots (*),
        capsule_media (*)
      `,
      )
      .eq("id", body.capsuleId)
      .single();

    if (fetchError || !capsule) {
      logError(
        {
          function: "open-capsule",
          operation: "fetch_capsule",
          userId: user.id,
          metadata: { capsuleId: body.capsuleId },
        },
        fetchError || new Error("Capsule not found"),
      );
      return createCustomErrorResponse(
        "capsule_not_found",
        "Capsule not found",
        404,
      );
    }

    // Check if capsule is ready to open
    if (capsule.status === "sealed") {
      const deliverAt = new Date(capsule.deliver_at);
      const now = new Date();

      // Allow opening if within 1 hour of delivery time (delivery window tolerance)
      const deliveryWindowMs = 60 * 60 * 1000; // 1 hour
      if (now.getTime() < deliverAt.getTime() - deliveryWindowMs) {
        return new Response(
          JSON.stringify({
            error: "capsule_not_ready",
            message: "This capsule is not ready to open yet",
            deliverAt: capsule.deliver_at,
            daysRemaining: Math.ceil(
              (deliverAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000),
            ),
          }),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          },
        );
      }
    }

    // Capture current snapshot (with error handling)
    let nowSnapshot;
    try {
      nowSnapshot = await captureUserSnapshot(supabase, user.id);
    } catch (snapshotError) {
      console.error("Failed to capture current snapshot:", snapshotError);
      // Use default snapshot if capture fails
      nowSnapshot = DEFAULT_SNAPSHOT;
    }

    // Get creation snapshot (handle missing snapshots gracefully)
    const thenSnapshot = capsule.capsule_snapshots?.[0] || null;

    if (!thenSnapshot) {
      console.warn(
        `Capsule ${capsule.id} missing creation snapshot - using default`,
      );
    }

    // Mark as opened if not already (with error handling)
    // FIX: Use atomic UPDATE WHERE to prevent race condition
    // Only update if status is still 'delivered' or 'sealed' (idempotent)
    const { error: updateError } = await supabase
      .from("time_capsules")
      .update({
        status: "opened",
        opened_at: new Date().toISOString(),
      })
      .eq("id", capsule.id)
      .in("status", ["delivered", "sealed"]); // FIX: Atomic check in WHERE clause

    if (updateError) {
      logError(
        {
          function: "open-capsule",
          operation: "update_capsule_status",
          userId: user.id,
          metadata: { capsuleId: capsule.id },
        },
        updateError,
      );
      // Don't fail the request, just log the error
    }

    // Calculate journey highlights (handle null snapshot case)
    const highlights = thenSnapshot
      ? calculateHighlights(thenSnapshot, nowSnapshot)
      : [];

    // Return capsule data with journey comparison
    return new Response(
      JSON.stringify({
        capsule: {
          id: capsule.id,
          userId: capsule.user_id,
          title: capsule.title,
          contentEncrypted: capsule.content_encrypted,
          contentType: capsule.content_type,
          theme: capsule.theme,
          createdAt: capsule.created_at,
          deliverAt: capsule.deliver_at,
          deliveredAt: capsule.delivered_at,
          openedAt: capsule.opened_at || new Date().toISOString(),
          status: "opened",
          companionLetter: capsule.companion_letter,
          wordCount: capsule.word_count,
          mediaCount: capsule.media_count || 0,
          encryptionKeyId: capsule.encryption_key_id,
        },
        media: capsule.capsule_media || [],
        companionLetter: capsule.companion_letter || null,
        thenSnapshot: thenSnapshot || DEFAULT_SNAPSHOT,
        nowSnapshot,
        highlights,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    logError(
      {
        function: "open-capsule",
        operation: "request_execution",
      },
      error,
    );
    return createErrorResponse(error);
  }
});
