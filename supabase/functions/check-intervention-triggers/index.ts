// Contextual Micro-Interventions: Trigger Evaluation and Intervention Selection
// Evaluates trigger conditions and selects best intervention for user context

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { logSanitized, sanitizeForLogging } from "../_shared/logging-sanitization.ts";
import { authenticateRequest, isAuthError } from "../_shared/auth.ts";

// Configuration Constants
const RETRY_MAX_ATTEMPTS = 3;
const RETRY_BASE_DELAY_MS = 1000;
const COOLDOWN_HOURS = 4;
const HEART_RATE_ELEVATED_THRESHOLD = 100; // BPM
const HRV_LOW_THRESHOLD = 30; // Milliseconds
const HEART_RATE_MIN = 40; // BPM
const HEART_RATE_MAX = 220; // BPM
const HRV_MIN = 10; // Milliseconds
const HRV_MAX = 200; // Milliseconds
const HR_CONFIDENCE_BASE = 100; // BPM baseline for confidence calculation
const HR_CONFIDENCE_RANGE = 30; // BPM range for scaling confidence
const HRV_CONFIDENCE_RANGE = 60; // ms range for scaling confidence
const MOOD_PATTERN_THRESHOLD = 2; // 1-5 scale, <= triggers pattern
const MOOD_CONFIDENCE_BASE = 1.6;
const MOOD_CONFIDENCE_MULTIPLIER = 0.3;

// Circuit Breaker Configuration
const CIRCUIT_BREAKER_FAILURE_THRESHOLD = 5;
const CIRCUIT_BREAKER_TIMEOUT_MS = 60000; // 1 minute
const CIRCUIT_BREAKER_RESET_TIMEOUT_MS = 30000; // 30 seconds

/**
 * LOGGING POLICY:
 * - NEVER log raw biometric values (HR, HRV)
 * - NEVER log calendar event titles
 * - Use logSanitized() for all context logging
 * - Use sanitizeForLogging() when logging context separately
 * - Only log error.message, never full error objects
 */

// corsHeaders are now dynamic — set per-request inside serve()

interface TriggerContext {
  biometrics?: {
    heartRate?: number; // BPM
    hrv?: number; // Milliseconds
  };
  timeOfDay?: string; // 'morning' | 'afternoon' | 'evening'
  recentMood?: number; // 1-5 scale
  upcomingEvents?: Array<{
    id: string;
    title: string;
    startDate: string;
    classification: string;
    stressScore: number;
    needsArmor: boolean;
  }>;
  timingConfidence?: number; // -0.5 to +0.5 from ML analysis
}

interface CheckTriggersRequest {
  context?: TriggerContext;
}

type TriggerType = "time_based" | "biometric" | "pattern" | "calendar" | "manual";

interface CheckTriggersResponse {
  shouldTrigger: boolean;
  triggerType?: TriggerType;
  intervention?: any; // MicroMomentTemplate
  contextMessage?: string;
  suppressionReason?:
    | "quiet_hours"
    | "daily_limit"
    | "cooldown"
    | "no_matching_templates"
    | "disabled";
}

// Circuit Breaker State
enum CircuitState {
  CLOSED = "CLOSED",   // Normal operation
  OPEN = "OPEN",       // Reject requests
  HALF_OPEN = "HALF_OPEN", // Testing recovery
}

class CircuitBreaker {
  private state: CircuitState = CircuitState.CLOSED;
  private failureCount = 0;
  private lastFailureTime: number | null = null;
  private successCount = 0;

  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.state === CircuitState.OPEN) {
      if (
        this.lastFailureTime &&
        Date.now() - this.lastFailureTime > CIRCUIT_BREAKER_RESET_TIMEOUT_MS
      ) {
        this.state = CircuitState.HALF_OPEN;
        this.successCount = 0;
      } else {
        throw new Error("Circuit breaker is OPEN");
      }
    }

    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess() {
    this.failureCount = 0;
    
    if (this.state === CircuitState.HALF_OPEN) {
      this.successCount++;
      if (this.successCount >= 2) {
        this.state = CircuitState.CLOSED;
      }
    }
  }

  private onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.failureCount >= CIRCUIT_BREAKER_FAILURE_THRESHOLD) {
      this.state = CircuitState.OPEN;
    }
  }

  getState(): CircuitState {
    return this.state;
  }
}

// Global circuit breaker instance
const circuitBreaker = new CircuitBreaker();

// Retry helper with exponential backoff
async function withRetry<T>(
  operation: () => Promise<T>,
  maxRetries = RETRY_MAX_ATTEMPTS,
  baseDelay = RETRY_BASE_DELAY_MS
): Promise<T> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error as Error;
      if (attempt < maxRetries - 1) {
        const delay = baseDelay * Math.pow(2, attempt);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError;
}

// Input validation
function validateBiometrics(biometrics?: {
  heartRate?: number;
  hrv?: number;
}): void {
  if (!biometrics) return;
  
  if (biometrics.heartRate !== undefined) {
    if (
      typeof biometrics.heartRate !== "number" ||
      biometrics.heartRate < HEART_RATE_MIN ||
      biometrics.heartRate > HEART_RATE_MAX
    ) {
      throw new Error(`Invalid heart rate: must be between ${HEART_RATE_MIN}-${HEART_RATE_MAX} BPM`);
    }
  }
  
  if (biometrics.hrv !== undefined) {
    if (
      typeof biometrics.hrv !== "number" ||
      biometrics.hrv < HRV_MIN ||
      biometrics.hrv > HRV_MAX
    ) {
      throw new Error(`Invalid HRV: must be between ${HRV_MIN}-${HRV_MAX}ms`);
    }
  }
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Wrap main logic in circuit breaker
    return await circuitBreaker.execute(async () => {
      // Authenticate using shared helper (creates fresh client per request)
      const authResult = await authenticateRequest(req);
      if (isAuthError(authResult)) {
        return authResult.response;
      }

      const { user, supabaseAdmin: supabase } = authResult;

      const userId = user.id;

      // Parse request body
      const { context } = (await req.json()) as {
        context?: TriggerContext;
      };

      // Validate biometric inputs
      if (context?.biometrics) {
        validateBiometrics(context.biometrics);
      }

      // Get user timezone (default to UTC if not set)
      const { data: settings } = await withRetry(() =>
        supabase
          .from("user_settings")
          .select("timezone")
          .eq("user_id", userId)
          .maybeSingle()
      );
      
      const userTimezone = settings?.timezone || "UTC";

      // CRITICAL FIX: Use Intl.DateTimeFormat instead of toLocaleString + new Date()
      // to avoid timezone re-interpretation bugs
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: userTimezone,
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: false,
      });
      
      const parts = formatter.formatToParts(new Date());
      const hour = parts.find(p => p.type === "hour")?.value || "00";
      const minute = parts.find(p => p.type === "minute")?.value || "00";
      const second = parts.find(p => p.type === "second")?.value || "00";
      const currentTime = `${hour}:${minute}:${second}`;

      // 1. Load user preferences
      const { data: prefs, error: prefsError } = await withRetry(() =>
        supabase
          .from("intervention_preferences")
          .select("*")
          .eq("user_id", userId)
          .maybeSingle()
      );

      if (prefsError && prefsError.code !== "PGRST116") {
        // Error other than "no rows"
        throw prefsError;
      }

      // If no preferences exist, create defaults
      if (!prefs) {
        const { data: newPrefs, error: insertError } = await withRetry(() =>
          supabase
            .from("intervention_preferences")
            .insert({
              user_id: userId,
              enabled: true,
              max_daily: 5,
              quiet_hours_start: null,
              quiet_hours_end: null,
            })
            .select()
            .single()
        );

        if (insertError) throw insertError;

        // Use new default preferences
        return evaluateTriggers(
          supabase,
          userId,
          newPrefs,
          userTimezone,
          req.headers.get("Authorization") || "",
          context
        );
      }

      // Check if interventions are enabled
      if (!prefs.enabled) {
        return new Response(
          JSON.stringify({
            shouldTrigger: false,
            suppressionReason: "disabled",
          } as CheckTriggersResponse),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // Evaluate triggers with user preferences
      const response = await evaluateTriggers(
        supabase,
        userId,
        prefs,
        userTimezone,
        req.headers.get("Authorization") || "",
        context
      );

      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    });
  } catch (error) {
    // Circuit breaker open
    if ((error as Error).message === "Circuit breaker is OPEN") {
      return new Response(
        JSON.stringify({
          error: "Service temporarily unavailable",
          suppressionReason: "circuit_breaker_open"
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Sanitize error logs - don't log request body (may contain PHI)
    logSanitized("error", "Error in check-intervention-triggers", {
      error,
      metadata: {
        circuitState: circuitBreaker.getState(),
      },
    });

    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

async function evaluateTriggers(
  supabase: any,
  userId: string,
  prefs: any,
  userTimezone: string,
  authHeader: string,
  context?: TriggerContext,
): Promise<CheckTriggersResponse> {
  // CRITICAL FIX: Use same timezone-aware approach
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTimezone,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  
  const parts = formatter.formatToParts(new Date());
  const hour = parts.find(p => p.type === "hour")?.value || "00";
  const minute = parts.find(p => p.type === "minute")?.value || "00";
  const second = parts.find(p => p.type === "second")?.value || "00";
  const currentTime = `${hour}:${minute}:${second}`;

  // 2. Check quiet hours
  if (prefs.quiet_hours_start && prefs.quiet_hours_end) {
    const { data: isQuiet, error: quietError } = await withRetry(() =>
      supabase.rpc("is_in_quiet_hours", {
        check_time: currentTime,
        quiet_start: prefs.quiet_hours_start,
        quiet_end: prefs.quiet_hours_end,
      })
    );

    if (quietError) {
      console.error("Error checking quiet hours:", quietError.message);
    } else if (isQuiet) {
      return {
        shouldTrigger: false,
        suppressionReason: "quiet_hours",
      };
    }
  }

  // 3. Check daily limit using user's local date
  const now = new Date();
  const formatterDate = new Intl.DateTimeFormat("en-US", {
    timeZone: userTimezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  
  const dateParts = formatterDate.formatToParts(now);
  const year = dateParts.find(p => p.type === "year")?.value || "2024";
  const month = dateParts.find(p => p.type === "month")?.value || "01";
  const day = dateParts.find(p => p.type === "day")?.value || "01";
  
  // Construct start and end of day in user's timezone
  const todayStart = new Date(`${year}-${month}-${day}T00:00:00`);
  const todayEnd = new Date(`${year}-${month}-${day}T23:59:59.999`);

  const { count: todayCount, error: countError } = await withRetry(() =>
    supabase
      .from("intervention_deliveries")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("delivered_at", todayStart.toISOString())
      .lte("delivered_at", todayEnd.toISOString())
  );

  if (countError) {
    console.error("Error checking daily limit:", countError.message);
  } else if ((todayCount || 0) >= prefs.max_daily) {
    return {
      shouldTrigger: false,
      suppressionReason: "daily_limit",
    };
  }

  // 4. Check cooldown (4 hours after last dismissal)
  const cooldownHours = COOLDOWN_HOURS;
  const nowCooldown = new Date();
  const cooldownCutoff = new Date(
    nowCooldown.getTime() - cooldownHours * 60 * 60 * 1000,
  );

  const { data: recentDismissal, error: dismissError } = await withRetry(() =>
    supabase
      .from("intervention_deliveries")
      .select("dismissed_at")
      .eq("user_id", userId)
      .not("dismissed_at", "is", null)
      .gte("dismissed_at", cooldownCutoff.toISOString())
      .order("dismissed_at", { ascending: false })
      .limit(1)
      .maybeSingle()
  );

  if (dismissError) {
    console.error("Error checking cooldown:", dismissError.message);
  } else if (recentDismissal) {
    return {
      shouldTrigger: false,
      suppressionReason: "cooldown",
    };
  }

  // 5. Evaluate trigger conditions
  const triggerType = determineTriggerType(context);

  if (!triggerType) {
    return {
      shouldTrigger: false,
      suppressionReason: "no_matching_templates",
    };
  }

  // 6. Select best intervention (use function-to-function auth)
  const confidence = calculateConfidence(context, triggerType);
  
  const suggestionResponse = await withRetry(() =>
    fetch(
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/get-micro-suggestions`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": Deno.env.get("SUPABASE_ANON_KEY")!,
          "Authorization": authHeader,
        },
        body: JSON.stringify({
          triggerType,
          triggerConfidence: confidence,
          limit: 1,
        }),
      }
    )
  );

  if (!suggestionResponse.ok) {
    console.error("Error getting suggestions:", suggestionResponse.statusText);
    return {
      shouldTrigger: false,
      suppressionReason: "no_matching_templates",
    };
  }

  const suggestions = await suggestionResponse.json();

  if (!suggestions?.suggestions || suggestions.suggestions.length === 0) {
    return {
      shouldTrigger: false,
      suppressionReason: "no_matching_templates",
    };
  }

  const intervention = suggestions.suggestions[0];

  // Generate context message
  const contextMessage = generateContextMessage(triggerType, context);

  // Create sanitized context snapshot (NO PHI)
  const sanitizedContext = {
    timeOfDay: context?.timeOfDay,
    triggerType,
    confidence,
    // DO NOT store biometric data
  };

  return {
    shouldTrigger: true,
    triggerType,
    intervention,
    contextMessage,
  };
}

function determineTriggerType(context?: TriggerContext): TriggerType | null {
  if (!context) {
    // Default to time-based if no context provided
    return "time_based";
  }

  // Priority: calendar > biometric > time_based > pattern
  // Calendar events get highest priority (proactive armor)
  if (context.upcomingEvents && context.upcomingEvents.length > 0) {
    // Check if any event warrants intervention
    const highStressEvent = context.upcomingEvents.find(
      event => event.stressScore >= 0.7 || event.needsArmor
    );
    if (highStressEvent) {
      return "calendar";
    }
  }
  
  if (context.biometrics) {
    const { heartRate, hrv } = context.biometrics;

    // Elevated heart rate threshold
    if (heartRate && heartRate > HEART_RATE_ELEVATED_THRESHOLD) {
      return "biometric";
    }

    // Low HRV threshold
    if (hrv && hrv < HRV_LOW_THRESHOLD) {
      return "biometric";
    }
  }

  // Time-based trigger
  if (context.timeOfDay) {
    return "time_based";
  }

  // Pattern-based (low recent mood)
  if (context.recentMood && context.recentMood <= MOOD_PATTERN_THRESHOLD) {
    return "pattern";
  }

  return "time_based"; // Default fallback
}

function calculateConfidence(
  context?: TriggerContext,
  triggerType?: TriggerType,
): number {
  if (!context || !triggerType) return 0.5;
  
  let baseConfidence = 0.5;

  if (triggerType === "calendar" && context.upcomingEvents) {
    // Find the highest stress event
    const highestStressEvent = context.upcomingEvents.reduce((max, event) => 
      event.stressScore > max.stressScore ? event : max
    );
    
    // Use stress score as base confidence
    // User-marked "needs armor" events get max confidence
    baseConfidence = highestStressEvent.needsArmor ? 1.0 : highestStressEvent.stressScore;
  } else if (triggerType === "biometric" && context.biometrics) {
    const { heartRate, hrv } = context.biometrics;

    if (heartRate) {
      // Scale confidence: 100 BPM = 0.5, 130+ BPM = 1.0
      baseConfidence = Math.min(1.0, (heartRate - HR_CONFIDENCE_BASE) / HR_CONFIDENCE_RANGE + 0.5);
    } else if (hrv) {
      // Scale confidence: 30 ms = 0.5, 0 ms = 1.0
      baseConfidence = Math.min(1.0, 1.0 - hrv / HRV_CONFIDENCE_RANGE);
    }
  } else if (triggerType === "time_based") {
    baseConfidence = 1.0; // Time-based triggers are always high confidence
  } else if (triggerType === "pattern" && context.recentMood) {
    // Scale confidence: mood 2 = 0.6, mood 1 = 1.0
    baseConfidence = Math.min(1.0, MOOD_CONFIDENCE_BASE - context.recentMood * MOOD_CONFIDENCE_MULTIPLIER);
  } else {
    baseConfidence = 0.7; // Default moderate confidence
  }
  
  // Apply ML timing confidence boost/suppression (-0.5 to +0.5)
  if (context.timingConfidence !== undefined) {
    const adjustedConfidence = baseConfidence + context.timingConfidence;
    return Math.max(0.0, Math.min(1.0, adjustedConfidence)); // Clamp to [0, 1]
  }

  return baseConfidence;
}

function generateContextMessage(
  triggerType: TriggerType,
  context?: TriggerContext,
): string {
  switch (triggerType) {
    case "calendar":
      if (context?.upcomingEvents && context.upcomingEvents.length > 0) {
        const nextEvent = context.upcomingEvents[0];
        const eventDate = new Date(nextEvent.startDate);
        const minutesUntil = Math.round((eventDate.getTime() - Date.now()) / (1000 * 60));
        
        // User-marked "needs armor" events get special message
        if (nextEvent.needsArmor) {
          return `You marked your upcoming event as needing support. Let's armor up before it starts.`;
        }
        
        // Classification-specific messages
        switch (nextEvent.classification) {
          case "meeting":
            return `You have a meeting in ${minutesUntil} minutes. A quick centering practice can help you show up focused.`;
          case "deadline":
            return `Important deadline approaching in ${minutesUntil} minutes. Let's manage any pre-deadline stress.`;
          case "medical":
            return `Medical appointment coming up in ${minutesUntil} minutes. A calming practice can help ease any nerves.`;
          case "travel":
            return `Travel starting in ${minutesUntil} minutes. A grounding exercise can help you feel prepared.`;
          case "social":
            return `Social event in ${minutesUntil} minutes. Take a moment to center yourself first.`;
          default:
            return `You have an event coming up in ${minutesUntil} minutes. Let's prepare mindfully.`;
        }
      }
      return "Let's prepare for what's ahead.";
    
    case "biometric":
      if (
        context?.biometrics?.heartRate &&
        context.biometrics.heartRate > HEART_RATE_ELEVATED_THRESHOLD
      ) {
        return "I noticed your heart rate is elevated. A quick breathing exercise might help.";
      }
      if (context?.biometrics?.hrv && context.biometrics.hrv < HRV_LOW_THRESHOLD) {
        return "Your stress levels seem high. Let's take a moment to reset.";
      }
      return "I sensed you might need a quick wellness break.";

    case "time_based":
      if (context?.timeOfDay === "morning") {
        return "Good morning! Perfect time to set a positive intention.";
      }
      if (context?.timeOfDay === "afternoon") {
        return "Afternoon slump? A quick reset can help you refocus.";
      }
      if (context?.timeOfDay === "evening") {
        return "Good time to reflect and release the day.";
      }
      return "Good time for a mindful break.";

    case "pattern":
      return "I noticed you might be experiencing a challenging moment. This could help.";

    default:
      return "A moment of wellness for you.";
  }
}
