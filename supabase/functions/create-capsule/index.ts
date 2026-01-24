// Create Time Capsule Edge Function
// Handles capsule creation with quota enforcement and snapshot capture

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { captureUserSnapshot } from "../_shared/capsule-utils.ts";

interface CreateCapsuleRequest {
  title?: string;
  theme: string;
  contentEncrypted: string;
  contentType: "text" | "audio" | "photo" | "mixed";
  deliverAt: string;
  encryptionKeyId: string;
  wordCount?: number;
}

// Validation constants
const VALIDATION = {
  MAX_CONTENT_SIZE: 100 * 1024, // 100KB for encrypted content
  MAX_TITLE_LENGTH: 100,
  MIN_DELIVERY_DAYS: 7,
  MAX_DELIVERY_DAYS: 5 * 365,
  VALID_CONTENT_TYPES: ["text", "audio", "photo", "mixed"],
  VALID_THEMES: [
    "milestone",
    "goal",
    "gratitude",
    "advice",
    "encouragement",
    "anniversary",
    "custom",
  ],
} as const;

serve(async (req) => {
  try {
    // Initialize Supabase client
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

    // Parse request body
    const body: CreateCapsuleRequest = await req.json();

    // === INPUT VALIDATION ===

    // Validate required fields
    if (!body.contentEncrypted || typeof body.contentEncrypted !== "string") {
      return new Response(
        JSON.stringify({
          error: "invalid_input",
          message: "Content is required and must be a string",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (!body.encryptionKeyId || typeof body.encryptionKeyId !== "string") {
      return new Response(
        JSON.stringify({
          error: "invalid_input",
          message: "Encryption key ID is required",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Validate content size (prevent DoS)
    if (body.contentEncrypted.length > VALIDATION.MAX_CONTENT_SIZE) {
      return new Response(
        JSON.stringify({
          error: "content_too_large",
          message: `Content exceeds maximum size of ${VALIDATION.MAX_CONTENT_SIZE / 1024}KB`,
        }),
        {
          status: 413,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Validate and sanitize title
    if (body.title !== undefined) {
      if (typeof body.title !== "string") {
        return new Response(
          JSON.stringify({
            error: "invalid_input",
            message: "Title must be a string",
          }),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          },
        );
      }

      body.title = body.title.trim();

      if (body.title.length > VALIDATION.MAX_TITLE_LENGTH) {
        return new Response(
          JSON.stringify({
            error: "title_too_long",
            message: `Title cannot exceed ${VALIDATION.MAX_TITLE_LENGTH} characters`,
          }),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          },
        );
      }
    }

    // Validate content type
    if (!VALIDATION.VALID_CONTENT_TYPES.includes(body.contentType)) {
      return new Response(
        JSON.stringify({
          error: "invalid_content_type",
          message: `Content type must be one of: ${VALIDATION.VALID_CONTENT_TYPES.join(", ")}`,
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Validate theme
    if (!VALIDATION.VALID_THEMES.includes(body.theme)) {
      return new Response(
        JSON.stringify({
          error: "invalid_theme",
          message: `Theme must be one of: ${VALIDATION.VALID_THEMES.join(", ")}`,
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Validate word count if provided
    if (
      body.wordCount !== undefined &&
      (typeof body.wordCount !== "number" || body.wordCount < 0 ||
        body.wordCount > 10000)
    ) {
      return new Response(
        JSON.stringify({
          error: "invalid_word_count",
          message: "Word count must be between 0 and 10000",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Validate delivery date
    if (!body.deliverAt || typeof body.deliverAt !== "string") {
      return new Response(
        JSON.stringify({
          error: "invalid_input",
          message: "Delivery date is required",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Parse and validate delivery date
    const deliverAt = new Date(body.deliverAt);
    const now = new Date();

    // Check if date is valid
    if (isNaN(deliverAt.getTime())) {
      return new Response(
        JSON.stringify({
          error: "invalid_delivery_date",
          message: "Delivery date is not a valid ISO 8601 date string",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Check minimum delivery time (7 days)
    const minDeliveryDate = new Date(
      now.getTime() + VALIDATION.MIN_DELIVERY_DAYS * 24 * 60 * 60 * 1000,
    );
    if (deliverAt < minDeliveryDate) {
      return new Response(
        JSON.stringify({
          error: "invalid_delivery_date",
          message: `Delivery date must be at least ${VALIDATION.MIN_DELIVERY_DAYS} days in the future`,
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Check maximum delivery time (5 years)
    const maxDeliveryDate = new Date(
      now.getTime() + VALIDATION.MAX_DELIVERY_DAYS * 24 * 60 * 60 * 1000,
    );
    if (deliverAt > maxDeliveryDate) {
      return new Response(
        JSON.stringify({
          error: "invalid_delivery_date",
          message: `Delivery date cannot be more than ${VALIDATION.MAX_DELIVERY_DAYS / 365} years in the future`,
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Check quota (pre-flight check; actual enforcement via database trigger)
    const { data: quotaCheck, error: quotaError } = await supabase.rpc(
      "check_capsule_quota",
      {
        p_user_id: user.id,
        p_file_size_bytes: 0, // Media files checked separately on upload
      },
    );

    if (quotaError) {
      console.error("Quota check failed:", quotaError);
      return new Response(JSON.stringify({ error: "Failed to check quota" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!quotaCheck.allowed) {
      return new Response(
        JSON.stringify({
          error: quotaCheck.reason,
          message: quotaCheck.message,
          limit: {
            count: quotaCheck.max_count,
            storage: quotaCheck.max_storage,
          },
          current: {
            count: quotaCheck.current_count,
            storage: quotaCheck.current_storage,
          },
        }),
        {
          status: 402, // Payment Required
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Capture user snapshot
    const snapshot = await captureUserSnapshot(supabase, user.id);

    // Insert capsule (quota enforced by database trigger)
    const { data: capsule, error: capsuleError } = await supabase
      .from("time_capsules")
      .insert({
        user_id: user.id,
        title: body.title,
        content_encrypted: body.contentEncrypted,
        content_type: body.contentType,
        theme: body.theme,
        deliver_at: body.deliverAt,
        encryption_key_id: body.encryptionKeyId,
        word_count: body.wordCount,
        status: "sealed",
      })
      .select()
      .single();

    if (capsuleError) {
      console.error("Failed to create capsule:", capsuleError);

      // Handle quota violation from trigger
      if (
        capsuleError.message?.includes("capsule_quota_exceeded") ||
        capsuleError.message?.includes("storage_quota_exceeded")
      ) {
        return new Response(
          JSON.stringify({
            error: "quota_exceeded",
            message: capsuleError.message,
          }),
          {
            status: 402,
            headers: { "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({ error: "Failed to create capsule" }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Insert snapshot
    const { error: snapshotError } = await supabase
      .from("capsule_snapshots")
      .insert({
        capsule_id: capsule.id,
        ...snapshot,
      });

    if (snapshotError) {
      console.error("Failed to save snapshot:", snapshotError);
      // Don't fail the entire request, snapshot is non-critical
    }

    // Calculate days until delivery
    const daysUntilDelivery = Math.ceil(
      (deliverAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000),
    );

    return new Response(
      JSON.stringify({
        id: capsule.id,
        status: "sealed",
        deliverAt: capsule.deliver_at,
        daysUntilDelivery,
        snapshot: {
          currentStreak: snapshot.current_streak,
          level: snapshot.level,
          totalXP: snapshot.total_xp,
          badgesEarned: snapshot.badges_earned,
        },
      }),
      {
        status: 201,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error in create-capsule:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error.message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
