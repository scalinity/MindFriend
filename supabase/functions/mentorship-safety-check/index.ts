// Mentorship Safety Check - Monitors messages for concerning patterns
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Constant-time string comparison to prevent timing attacks
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

// Safety patterns to detect
const CRISIS_KEYWORDS = [
  "suicide",
  "kill myself",
  "end my life",
  "don't want to live",
  "want to die",
  "self-harm",
  "hurt myself",
];

const BOUNDARY_VIOLATION_PATTERNS = [
  // Personal info requests
  /\b(give me|share|what's|tell me) your (phone|email|address|social|instagram|facebook|twitter|snapchat)\b/i,
  /\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b/, // Phone numbers
  /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, // Email
  /\bmeet (in person|up|me|irl)\b/i,
  /\bcome over\b/i,
];

const INAPPROPRIATE_PATTERNS = [
  /\bstop taking (medication|meds|medicine)\b/i,
  /\bdon't need (therapy|therapist|counselor)\b/i,
  /\byou don't need (help|treatment)\b/i,
  /\bjust get over it\b/i,
  /\bman up\b/i,
  /\bstop being (dramatic|weak|sensitive)\b/i,
];

interface SafetyCheckResult {
  flagged: boolean;
  reason?: string;
  severity: "low" | "medium" | "high" | "critical";
  action: "none" | "flag" | "alert" | "escalate";
}

function checkMessage(content: string): SafetyCheckResult {
  const lowerContent = content.toLowerCase();

  // Check for crisis keywords (critical severity)
  for (const keyword of CRISIS_KEYWORDS) {
    if (lowerContent.includes(keyword)) {
      return {
        flagged: true,
        reason: "crisis_keywords",
        severity: "critical",
        action: "escalate",
      };
    }
  }

  // Check for boundary violations (high severity)
  for (const pattern of BOUNDARY_VIOLATION_PATTERNS) {
    if (pattern.test(content)) {
      return {
        flagged: true,
        reason: "boundary_violation",
        severity: "high",
        action: "alert",
      };
    }
  }

  // Check for inappropriate advice (medium severity)
  for (const pattern of INAPPROPRIATE_PATTERNS) {
    if (pattern.test(content)) {
      return {
        flagged: true,
        reason: "inappropriate_content",
        severity: "medium",
        action: "flag",
      };
    }
  }

  return {
    flagged: false,
    severity: "low",
    action: "none",
  };
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // This endpoint is called internally by triggers or scheduled jobs
  // Verify caller is either:
  // 1. Internal service call (via Supabase Functions invoke - has x-sb-webhook-signature)
  // 2. Valid authenticated user with admin role
  const authHeader = req.headers.get("Authorization");
  const webhookSignature = req.headers.get("x-sb-webhook-signature");

  // Allow internal webhook calls (from cron jobs or other edge functions)
  const isInternalCall = !!webhookSignature;

  if (!isInternalCall) {
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "UNAUTHORIZED" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      data: { user },
      error,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (error || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "UNAUTHORIZED" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if user is a moderator/admin (for manual triggering)
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (!profile || ![\"admin\", \"moderator\"].includes(profile.role || \"\")) {
      return new Response(
        JSON.stringify({ error: \"Forbidden\", code: \"FORBIDDEN\" }),
        {
          status: 403,
          headers: { ...corsHeaders, \"Content-Type\": \"application/json\" },
        },
      );
    }
  } else {
    // WEBHOOK: Verify HMAC signature for internal calls
    const signature = webhookSignature;
    const body = await req.clone().text();
    const secret = Deno.env.get("SUPABASE_WEBHOOK_SECRET");
    
    if (!secret || secret.trim() === "") {
      console.error("[SECURITY] SUPABASE_WEBHOOK_SECRET not configured");
      return new Response(
        JSON.stringify({ error: "Server misconfigured", code: "CONFIG_ERROR" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    
    const encoder = new TextEncoder();
    const keyBuf = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    
    const signatureBuf = await crypto.subtle.sign(
      "HMAC",
      keyBuf,
      encoder.encode(body),
    );
    
    const computedSignature = Array.from(new Uint8Array(signatureBuf))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    
    // Constant-time comparison to prevent timing attacks
    if (!timingSafeEqual(signature, computedSignature)) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "UNAUTHORIZED" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
  }

  try {
    // Get unflagged messages from the last hour that haven't been reviewed
    const timeoutPromise = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("Database query timeout")),
        10000, // 10 second timeout
      ),
    );

    const queryPromise = (async () => {
      return await supabase
        .from("mentorship_messages")
        .select(
          `
          id,
          match_id,
          sender_id,
          content,
          sent_at,
          flagged,
          reviewed
        `,
        )
        .eq("flagged", false)
        .eq("reviewed", false)
        .gte("sent_at", new Date(Date.now() - 60 * 60 * 1000).toISOString())
        .order("sent_at", { ascending: true })
        .limit(100);
    })();

    const { data: messages, error: fetchError } = await Promise.race([
      queryPromise,
      timeoutPromise,
    ]);

    if (fetchError) {
      console.error("Error fetching messages:", fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch messages", code: "DB_ERROR" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const flaggedMessages: Array<{
      id: string;
      matchId: string;
      senderId: string;
      reason: string;
      severity: string;
    }> = [];

    const escalations: Array<{
      matchId: string;
      senderId: string;
      messageId: string;
      reason: string;
    }> = [];

    // Check each message
    for (const msg of messages || []) {
      const result = checkMessage(msg.content);

      if (result.flagged) {
        // Update message as flagged
        await supabase
          .from("mentorship_messages")
          .update({
            flagged: true,
            flag_reason: result.reason,
          })
          .eq("id", msg.id);

        flaggedMessages.push({
          id: msg.id,
          matchId: msg.match_id,
          senderId: msg.sender_id,
          reason: result.reason || "unknown",
          severity: result.severity,
        });

        // Handle escalations (critical severity)
        if (result.action === "escalate") {
          escalations.push({
            matchId: msg.match_id,
            senderId: msg.sender_id,
            messageId: msg.id,
            reason: result.reason || "crisis_keywords",
          });

          // Trigger crisis intervention for the sender
          await triggerCrisisIntervention(supabase, msg.sender_id);
        }

        // Handle alerts (high severity)
        if (result.action === "alert") {
          await notifyModerators(
            supabase,
            msg,
            result.reason || "boundary_violation",
          );
        }
      }
    }

    // Create reports for escalated messages
    for (const escalation of escalations) {
      await supabase.from("mentorship_reports").insert({
        reporter_id: "00000000-0000-0000-0000-000000000000", // System reporter
        reported_id: escalation.senderId,
        match_id: escalation.matchId,
        reason: "crisis_mishandling",
        description: `Automated detection: ${escalation.reason}`,
        message_ids: [escalation.messageId],
        status: "investigating",
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed: messages?.length || 0,
        flagged: flaggedMessages.length,
        escalated: escalations.length,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function triggerCrisisIntervention(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  try {
    // Wrap in timeout to prevent job hangs
    const crisisTimeout = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("Crisis intervention timeout")),
        5000, // 5 second timeout
      ),
    );

    const crisisPromise = (async () => {
      // Log crisis event
      await supabase.from("crisis_events").insert({
        user_id: userId,
        trigger_type: "mentorship_message",
        severity: "high",
        ai_detected: true,
      });

      // Send crisis resources notification
      await supabase.functions.invoke("send-notification", {
        body: {
          userId,
          title: "We're Here For You",
          body: "If you're struggling, please reach out. Help is available 24/7.",
          data: {
            type: "crisis_support",
            action: "show_crisis_resources",
          },
        },
      });
    })();

    // Race against timeout
    await Promise.race([crisisPromise, crisisTimeout]);
  } catch (error) {
    // Log timeout separately from other errors to aid debugging
    if (error instanceof Error && error.message === "Crisis intervention timeout") {
      console.error("Crisis intervention timeout - job may need optimization");
    } else {
      console.error("Failed to trigger crisis intervention:", error);
    }
    // Don't re-throw - we want safety check to continue processing other messages
  }
}

async function notifyModerators(
  supabase: ReturnType<typeof createClient>,
  message: {
    id: string;
    match_id: string;
    sender_id: string;
    // Note: content intentionally not included to avoid PII in logs
  },
  reason: string,
) {
  try {
    // Wrap in timeout to prevent job hangs
    const notificationTimeout = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("Moderation notification timeout")),
        5000, // 5 second timeout
      ),
    );

    const notificationPromise = (async () => {
      // Create a moderation queue entry (no PII in logs)
      await supabase.from("mentorship_reports").insert({
        reporter_id: "00000000-0000-0000-0000-000000000000", // System reporter
        reported_id: message.sender_id,
        match_id: message.match_id,
        reason: reason === "boundary_violation" ? "boundary_violation" : "other",
        description: `Automated detection: ${reason}`,
        message_ids: [message.id],
        status: "pending",
      });

      // Log without PII (only message ID, not content)
      console.info(`[MODERATION] Message ${message.id} queued for review`);
    })();

    // Race against timeout
    await Promise.race([notificationPromise, notificationTimeout]);
  } catch (error) {
    // Log timeout separately to aid debugging
    if (error instanceof Error && error.message === "Moderation notification timeout") {
      console.warn("Moderation notification timeout - check database performance");
    } else {
      // Log error without exposing details
      console.error(
        "Failed to queue moderation:",
        error instanceof Error ? error.message : "Unknown error",
      );
    }
    // Don't re-throw - we want safety check to continue processing
  }
}
