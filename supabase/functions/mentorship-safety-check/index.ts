import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { detectPII } from "../_shared/validation.ts";

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
  "killing myself",
  "end my life",
  "hurt myself",
  "hurting myself",
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

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const secret = Deno.env.get("MENTORSHIP_SAFETY_SECRET");
  if (!secret) return json({ error: "Safety checks are not configured" }, 503);
  if (req.headers.get("Authorization") !== `Bearer ${secret}`) {
    return json({ error: "Unauthorized" }, 401);
  }
  let body: { batch_size?: number; check_recent_only?: boolean };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "Invalid request" }, 400);
  }
  const { batch_size = 100, check_recent_only = true } = body;
  if (
    !Number.isInteger(batch_size) || batch_size < 1 || batch_size > 500 ||
    typeof check_recent_only !== "boolean"
  ) {
    return json({ error: "Invalid batch size or time filter" }, 400);
  }
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      {
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    let query = supabase.from("mentorship_messages")
      .select("id, sender_id, content, match_id, created_at")
      .is("safety_checked_at", null)
      .order("created_at", { ascending: true }).order("id", {
        ascending: true,
      });
    if (check_recent_only) {
      query = query.gte(
        "created_at",
        new Date(Date.now() - 60 * 60 * 1000).toISOString(),
      );
    }
    const { data: messages, error: fetchError } = await query.limit(batch_size);
    if (fetchError) {
      return json({ error: "Failed to fetch messages for safety check" }, 500);
    }

    let checked = 0;
    let critical = 0;
    const flagged: {
      message_id: string;
      severity: string;
      reasons: string[];
    }[] = [];
    for (const message of (messages ?? []) as MessageToCheck[]) {
      const flags = analyzeMessageSafety(message.content);
      const { data: saved, error } = await supabase.rpc(
        "record_mentorship_safety_check",
        {
          p_message_id: message.id,
          p_expected_content: message.content,
          p_reasons: flags.reasons,
          p_severity: flags.severity,
        },
      );
      if (error) return json({ error: "Failed to persist safety check" }, 500);
      if (saved !== true) continue; // Changed or already checked; never claim an unsaved result.
      checked++;
      if (flags.reasons.length > 0) {
        flagged.push({
          message_id: message.id,
          severity: flags.severity,
          reasons: flags.reasons,
        });
      }
      if (flags.severity === "critical") critical++;
    }
    return json({
      success: true,
      messages_checked: checked,
      messages_flagged: flagged.length,
      critical_escalations: critical,
      flagged_details: flagged,
      timestamp: new Date().toISOString(),
    });
  } catch {
    return json({ error: "Internal server error" }, 500);
  }
}

if (import.meta.main) Deno.serve(handler);

/**
 * Analyzes message content for safety concerns
 */
export function analyzeMessageSafety(content: string): SafetyFlags {
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
