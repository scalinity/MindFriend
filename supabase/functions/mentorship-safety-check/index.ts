import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { detectPII, sanitizeInput } from "../_shared/validation.ts";

interface SafetyFlags {
  crisis_keywords: boolean;
  boundary_violation: boolean;
  inappropriate_request: boolean;
  pii_exposure: boolean;
  severity: "low" | "medium" | "high" | "critical";
  reasons: string[];
}

// Crisis keywords requiring immediate escalation
const CRISIS_KEYWORDS = [
  "suicide",
  "suicidal",
  "kill myself",
  "end my life",
  "hurt myself",
  "self harm",
  "self-harm",
  "overdose",
  "jump off",
  "hanging",
  "never going to make it",
  "no point in living",
  "want to die",
  "going to die",
  "better off dead",
  "can't take it anymore",
  "final goodbye",
  "goodbye everyone",
  "last time",
];

// Boundary violation patterns
const BOUNDARY_VIOLATIONS = [
  /\b(romantic|dating|love)\b/i,
  /\b(sexual|sex|intimate|seduce)\b/i,
  /\b(meet in person|meet up|coffee|dinner)\b/i,
  /\b(naked|nude|picture|photo)\b/i,
  /\b(money|payment|send cash|wire transfer)\b/i,
  /\b(illegal|drug|prescription|medicine)\b/i,
  /\b(hug|kiss|touch|physical contact)\b/i,
];

// Inappropriate request patterns
const INAPPROPRIATE_PATTERNS = [
  /\b(scam|fraud|scheme|pyramid)\b/i,
  /\b(click here|click link|download|install)\b/i,
  /\b(verify|confirm|password|credentials)\b/i,
  /\b(investment|cryptocurrency|bitcoin)\b/i,
  /\b(affiliate|referral|commission)\b/i,
];

interface MessageToCheck {
  id: string;
  sender_id: string;
  content: string;
  match_id: string;
  created_at: string;
}

interface FlaggedMessage {
  message_id: string;
  match_id: string;
  sender_id: string;
  flags: SafetyFlags;
  flagged_at: string;
}

serve(async (req: Request) => {
  // Only allow POST (can be triggered by cron or manual call)
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Initialize Supabase client with service role (for admin access)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Optional: Check for auth header to restrict to trusted services
    const authHeader = req.headers.get("Authorization");
    const validSecret = Deno.env.get("MENTORSHIP_SAFETY_SECRET");

    if (authHeader && validSecret) {
      const providedSecret = authHeader.replace("Bearer ", "");
      if (providedSecret !== validSecret) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // Parse request body
    const body = await req.json();
    const { batch_size = 100, check_recent_only = true } = body;

    // Get unflagged messages from the last hour (if check_recent_only)
    const hoursAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();

    let query = supabase
      .from("mentorship_messages")
      .select("id, sender_id, content, match_id, created_at")
      .is("flagged_at", null)
      .eq("is_flagged", false);

    if (check_recent_only) {
      query = query.gte("created_at", hoursAgo);
    }

    const { data: messages, error: fetchError } = await query.limit(batch_size);

    if (fetchError) {
      console.error("Error fetching messages:", fetchError);
      return new Response(
        JSON.stringify({
          error: "Failed to fetch messages for safety check",
          details: fetchError.message,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Analyze each message
    const flaggedMessages: FlaggedMessage[] = [];
    const criticalEscalations: FlaggedMessage[] = [];

    for (const message of messages || []) {
      const flags = analyzeMessageSafety(message.content);

      if (flags.reasons.length > 0) {
        const flaggedMessage: FlaggedMessage = {
          message_id: message.id,
          match_id: message.match_id,
          sender_id: message.sender_id,
          flags,
          flagged_at: new Date().toISOString(),
        };

        flaggedMessages.push(flaggedMessage);

        // Track critical escalations separately
        if (flags.severity === "critical") {
          criticalEscalations.push(flaggedMessage);
        }
      }
    }

    // Update database with flagged messages
    if (flaggedMessages.length > 0) {
      const flagIds = flaggedMessages.map((fm) => fm.message_id);

      const { error: updateError } = await supabase
        .from("mentorship_messages")
        .update({
          is_flagged: true,
          flagged_at: new Date().toISOString(),
        })
        .in("id", flagIds);

      if (updateError) {
        console.error("Error updating flagged messages:", updateError);
      }
    }

    // Handle critical escalations
    if (criticalEscalations.length > 0) {
      await handleCriticalEscalations(supabase, criticalEscalations);
    }

    // Return check results
    return new Response(
      JSON.stringify({
        success: true,
        messages_checked: (messages || []).length,
        messages_flagged: flaggedMessages.length,
        critical_escalations: criticalEscalations.length,
        flagged_details: flaggedMessages.map((fm) => ({
          message_id: fm.message_id,
          severity: fm.flags.severity,
          reasons: fm.flags.reasons,
        })),
        timestamp: new Date().toISOString(),
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Unexpected error in mentorship-safety-check:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});

/**
 * Analyzes message content for safety concerns
 */
function analyzeMessageSafety(content: string): SafetyFlags {
  const contentLower = content.toLowerCase();
  const reasons: string[] = [];
  let severity: "low" | "medium" | "high" | "critical" = "low";

  // Check for crisis keywords
  let hasCrisisKeywords = false;
  for (const keyword of CRISIS_KEYWORDS) {
    if (contentLower.includes(keyword.toLowerCase())) {
      hasCrisisKeywords = true;
      reasons.push(`Contains crisis keyword: "${keyword}"`);
      severity = "critical";
    }
  }

  // Check for boundary violations
  let hasBoundaryViolation = false;
  for (const pattern of BOUNDARY_VIOLATIONS) {
    if (pattern.test(content)) {
      hasBoundaryViolation = true;
      reasons.push("Potential boundary violation detected");
      if (severity === "low") severity = "high";
      break;
    }
  }

  // Check for inappropriate requests
  let hasInappropriate = false;
  for (const pattern of INAPPROPRIATE_PATTERNS) {
    if (pattern.test(content)) {
      hasInappropriate = true;
      reasons.push("Potentially inappropriate request detected");
      if (severity !== "critical") severity = "high";
      break;
    }
  }

  // Check for PII exposure
  const piiCheck = detectPII(content);
  let hasPIIExposure = false;
  if (piiCheck.hasPII) {
    hasPIIExposure = true;
    reasons.push(`PII exposure detected: ${piiCheck.types.join(", ")}`);
    if (severity === "low") severity = "medium";
  }

  // Check for excessive length (spam indicator)
  if (content.length > 5000) {
    reasons.push("Message is unusually long (possible spam)");
    if (severity === "low") severity = "low";
  }

  // Check for excessive repetition
  if (/(.)\1{19,}/.test(content)) {
    reasons.push("Excessive character repetition detected (possible spam)");
    if (severity === "low") severity = "low";
  }

  return {
    crisis_keywords: hasCrisisKeywords,
    boundary_violation: hasBoundaryViolation,
    inappropriate_request: hasInappropriate,
    pii_exposure: hasPIIExposure,
    severity,
    reasons,
  };
}

/**
 * Handles critical safety escalations (crisis keywords, severe violations)
 */
async function handleCriticalEscalations(
  supabase: any,
  escalations: FlaggedMessage[]
) {
  try {
    // Create escalation records
    const escalationRecords = escalations.map((escalation) => ({
      message_id: escalation.message_id,
      match_id: escalation.match_id,
      reporter_id: escalation.sender_id, // Auto-flagged by system
      reason: escalation.flags.reasons.join("; "),
      severity: escalation.flags.severity,
      status: "pending_review",
      created_at: new Date().toISOString(),
    }));

    const { error: escalationError } = await supabase
      .from("mentorship_escalations")
      .insert(escalationRecords);

    if (escalationError) {
      console.error("Error creating escalation records:", escalationError);
    }

    // Get match IDs for notification
    const matchIds = [...new Set(escalations.map((e) => e.match_id))];

    // Send crisis notifications to moderators (stored in a moderators table or via notification service)
    for (const escalation of escalations) {
      if (escalation.flags.crisis_keywords) {
        // CRITICAL: Send immediate crisis notification
        try {
          await supabase.functions.invoke("send-notification", {
            body: {
              user_id: "moderator-group", // Broadcast to moderators
              title: "CRISIS ALERT - Mentorship Message",
              body: "Suicide-related keywords detected in mentorship conversation",
              type: "crisis_escalation",
              priority: "urgent",
              data: {
                match_id: escalation.match_id,
                message_id: escalation.message_id,
                severity: escalation.flags.severity,
              },
            },
          });
        } catch (notifError) {
          console.error("Error sending crisis notification:", notifError);
        }
      }
    }
  } catch (error) {
    console.error("Error handling critical escalations:", error);
  }
}
