// MindFriend Chat Edge Function
// Handles AI conversation with quota enforcement and crisis detection

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";

// Type alias for untyped Supabase client (no generated database types)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;
import { getCorsHeaders } from "../_shared/cors.ts";
// SEC-CRIT-007: Use multi-language crisis detection instead of legacy crisis.ts
import {
  detectCrisis as detectCrisisMultiLang,
  getMatchedKeyword as getMatchedCrisisKeyword,
} from "../_shared/crisis-detection.ts";
import { CRISIS_RESPONSE } from "../_shared/crisis.ts"; // Keep response template
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";
import { sanitizeErrorMessage } from "../_shared/security.ts";
import { sanitizeForPrompt } from "../_shared/sanitize.ts";
import { generateChatText, trimChatContext } from "../_shared/openai-chat.ts";
import { openAIBudgetReservation } from "../_shared/openai-budget.ts";
import {
  MonthlyAIBudgetExhaustedError,
  MonthlyAIBudgetUnavailableError,
} from "../_shared/monthly-ai-budget.ts";
// Cognitive Bias Coach imports
import {
  detectDistortion,
  getSensitivityThreshold,
} from "../_shared/distortion-detection.ts";
import { getReframe } from "../_shared/reframe-templates.ts";

// Security constants
const MAX_MESSAGE_LENGTH = 4000; // ~1000 tokens
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function retainBackground(task: Promise<unknown>): void {
  const runtime = (globalThis as typeof globalThis & { EdgeRuntime?: { waitUntil(task: Promise<unknown>): void } }).EdgeRuntime;
  runtime?.waitUntil(task);
}

// Coach settings cache (5-minute TTL)
const coachSettingsCache = new Map<
  string,
  {
    data: any;
    expiresAt: number;
  }
>();
const COACH_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Get coach settings with 5-minute cache
 * Reduces database queries by ~90% for power users
 */
async function getCachedCoachSettings(
  supabase: UntypedSupabaseClient,
  userId: string,
): Promise<any> {
  // Check cache
  const cached = coachSettingsCache.get(userId);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.data;
  }

  // Cache miss - fetch from database
  const { data: coachSettings } = await supabase
    .from("coach_settings")
    .select(
      "is_enabled, sensitivity_level, silent_hours_start, silent_hours_end, disabled_distortions, timezone",
    )
    .eq("user_id", userId)
    .maybeSingle();

  // Store in cache
  coachSettingsCache.set(userId, {
    data: coachSettings,
    expiresAt: Date.now() + COACH_CACHE_TTL_MS,
  });

  return coachSettings;
}


const SYSTEM_PROMPT = `You are MindFriend, a supportive and empathetic AI companion focused on mental wellness. Your role is to:

1. Listen actively and validate feelings
2. Offer gentle, practical coping strategies
3. Encourage healthy habits and self-care
4. Support users in their mental wellness journey
5. Be warm, friendly, and non-judgmental

Guidelines:
- Keep responses concise but caring (2-4 paragraphs max)
- Ask thoughtful follow-up questions to show engagement
- Never diagnose conditions or replace professional help
- If someone mentions serious concerns, gently suggest professional resources
- Celebrate small wins and progress
- Use a warm, conversational tone`;

interface ChatRequest {
  conversationId: string;
  content: string;
  requestId?: string;
  retryFailed?: boolean;
}

interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}

interface ChatExecution {
  receipt?: { userId: string; requestId: string };
  userMessageId?: string;
  messageSaved?: boolean | null;
}

function failedChatResponse(data: Record<string, unknown>, execution: ChatExecution): Record<string, unknown> {
  const userMessageId = execution.userMessageId ?? data.userMessageId;
  const messageSaved = execution.userMessageId ? true
    : execution.messageSaved !== undefined ? execution.messageSaved
    : typeof data.messageSaved === "boolean" ? data.messageSaved : null;
  return {
    ...data,
    code: data.code ?? "chat_request_unconfirmed",
    retryable: data.retryable === true,
    ...(execution.receipt ? { requestId: execution.receipt.requestId, failureId: crypto.randomUUID() } : {}),
    messageSaved,
    ...(messageSaved && userMessageId ? { userMessageId } : {}),
  };
}

async function handleChat(req: Request, execution: ChatExecution, onDelta?: (text: string) => void): Promise<Response> {
  console.log("======== CHAT FUNCTION START ========");
  console.log("[1] Method:", req.method);

  // Get origin first for consistent CORS handling
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);
  let knownProviderFailure = false;

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    console.log("[2] Processing request...");

    // Validate required environment variables (rule-032)
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

    if (
      !SUPABASE_URL ||
      !SUPABASE_ANON_KEY ||
      !SUPABASE_SERVICE_ROLE_KEY ||
      !OPENAI_API_KEY
    ) {
      console.error("CRITICAL: Missing required environment variables");
      return new Response(
        JSON.stringify({ error: "Service configuration error" }),
        {
          status: 503,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get auth header first
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    // Create user-scoped client with the JWT token
    // This is the recommended Supabase pattern for Edge Functions
    const supabaseUser = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: {
        headers: { Authorization: `Bearer ${token}` },
      },
    });

    // Initialize admin client for operations that need elevated privileges
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Get authenticated user with timeout
    let user;
    let userAuthError;
    let authTimeout: ReturnType<typeof setTimeout> | undefined;
    try {
      const authTimeoutPromise = new Promise<never>((_resolve, reject) =>
        authTimeout = setTimeout(() => reject(new Error("Auth timeout")), 5000),
      );

      const authPromise = (async () => {
        return await supabaseUser.auth.getUser();
      })();

      const authResult = await Promise.race([authPromise, authTimeoutPromise]);
      user = authResult.data?.user;
      userAuthError = authResult.error;
    } catch (error) {
      console.error(
        "Auth error:",
        error instanceof Error ? error.message : String(error),
      );
      return new Response(JSON.stringify({ error: "Authentication failed" }), {
        status: 401,
        headers: baseCorsHeaders,
      });
    } finally {
      clearTimeout(authTimeout);
    }

    if (userAuthError || !user) {
      // SEC-CRIT-006: Log details server-side only, don't expose to client
      console.error(
        "Auth validation failed:",
        userAuthError?.message || "No user returned",
        "Code:",
        userAuthError?.code,
      );
      return new Response(
        JSON.stringify({
          error: "Invalid token",
          message:
            "Session validation failed. Please sign out and sign back in.",
          // Don't expose internal error details or codes to clients
        }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log("Authentication succeeded");

    // Rate limiting check (10 requests per minute)
    console.log("[4] Checking rate limit...");
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "chat",
    );
    console.log("[4] Rate limit result:", JSON.stringify(rateLimitResult));

    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          message: "Please wait a moment before sending more messages.",
          retryAfter: rateLimitResult.retryAfter,
          code: "chat_rate_limited",
          retryable: true,
        }),
        {
          status: 429,
          headers: {
            ...baseCorsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    // Use base CORS headers with additional response headers
    const responseHeaders = {
      ...baseCorsHeaders,
      "Content-Type": "application/json",
      ...getRateLimitHeaders(rateLimitResult),
    };

    // Parse request body
    let requestBody: ChatRequest;
    try {
      requestBody = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    let { conversationId, requestId } = requestBody;
    const { content, retryFailed = false } = requestBody;
    if (typeof retryFailed !== "boolean" || (retryFailed && !requestId)) {
      return new Response(JSON.stringify({ error: "Invalid retry request" }), { status: 400, headers: responseHeaders });
    }
    if (requestId !== undefined && (typeof requestId !== "string" || !UUID_REGEX.test(requestId))) {
      return new Response(JSON.stringify({ error: "Invalid request identifier" }), { status: 400, headers: responseHeaders });
    }

    // Input validation - presence
    if (!conversationId || !content) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: responseHeaders },
      );
    }

    // Input validation - types
    if (typeof conversationId !== "string" || typeof content !== "string") {
      return new Response(JSON.stringify({ error: "Invalid field types" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    // Input validation - UUID format
    if (!UUID_REGEX.test(conversationId)) {
      return new Response(
        JSON.stringify({ error: "Invalid conversation identifier" }),
        { status: 400, headers: responseHeaders },
      );
    }

    // PostgreSQL renders UUIDs in lowercase; retries must compare canonical IDs.
    conversationId = conversationId.toLowerCase();
    requestId = requestId?.toLowerCase();

    // Input validation - content length
    const trimmedContent = content.trim();
    if (trimmedContent.length === 0) {
      return new Response(
        JSON.stringify({ error: "Message cannot be empty" }),
        { status: 400, headers: responseHeaders },
      );
    }

    if (trimmedContent.length > MAX_MESSAGE_LENGTH) {
      return new Response(
        JSON.stringify({
          error: "Message too long",
          maxLength: MAX_MESSAGE_LENGTH,
        }),
        { status: 400, headers: responseHeaders },
      );
    }

    // Verify conversation ownership - SECURITY CRITICAL
    console.log("Verifying conversation ownership");
    const { data: conversation, error: convError } = await supabaseAdmin
      .from("conversations")
      .select("id, user_id")
      .eq("id", conversationId)
      .single();
    console.log(
      "[5] Conversation lookup:",
      conversation ? "found" : "not found",
      convError?.message || "",
    );

    if (convError || !conversation) {
      return new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
        headers: responseHeaders,
      });
    }

    if (conversation.user_id !== user.id) {
      // Log potential attack attempt (without PII)
      console.error("Conversation ownership rejected");
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: responseHeaders,
      });
    }

    let userMessage: { id: string; created_at: string | null } | null = null;
    // Claim before quota/provider work. A lost response never authorizes replay.
    if (requestId) {
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest(
        "SHA-256", new TextEncoder().encode(trimmedContent),
      ))).map((b) => b.toString(16).padStart(2, "0")).join("");
      const { error: claimError } = await supabaseAdmin.from("chat_requests").insert({
        user_id: user.id, request_id: requestId, conversation_id: conversationId, content_hash: hash,
      });
      if (claimError) {
        if (claimError.code !== "23505") {
          return new Response(JSON.stringify({ error: "Unable to start request" }), { status: 503, headers: responseHeaders });
        }
        const { data: receipt } = await supabaseAdmin.from("chat_requests")
          .select("conversation_id, content_hash, response, response_status")
          .eq("user_id", user.id).eq("request_id", requestId).single();
        if (!receipt || receipt.conversation_id !== conversationId || receipt.content_hash !== hash) {
          return new Response(JSON.stringify({ error: "Request identifier already used" }), { status: 409, headers: responseHeaders });
        }
        if (receipt.response) {
          const previous = receipt.response;
          if (!(retryFailed && receipt.response_status >= 400 && receipt.response_status <= 599 &&
            previous.retryable === true && previous.requestId === requestId)) {
            return new Response(JSON.stringify(previous), { status: receipt.response_status, headers: responseHeaders });
          }
          // Only one explicit retry may promote a tagged failed receipt to pending.
          let retryClaim = supabaseAdmin.from("chat_requests")
            .update({ response: null, response_status: null })
            .eq("user_id", user.id).eq("request_id", requestId)
            .eq("response_status", receipt.response_status).not("response", "is", null);
          // Also match this failure, so a delayed competitor cannot claim a newer
          // failure with the same HTTP status after the first retry has finished.
          retryClaim = typeof previous.failureId === "string"
            ? retryClaim.eq("response->>failureId", previous.failureId)
            : retryClaim.is("response->>failureId", null);
          const { data: claimed, error: retryError } = await retryClaim.select("request_id").maybeSingle();
          if (retryError) {
            return new Response(JSON.stringify({ error: "Unable to confirm retry claim" }), { status: 503, headers: responseHeaders });
          }
          if (!claimed) {
            return new Response(JSON.stringify({ error: "Request outcome pending. Reload history before sending again." }), { status: 409, headers: responseHeaders });
          }
          execution.receipt = { userId: user.id, requestId };
          execution.messageSaved = previous.messageSaved === false ? false : null;
          if (previous.messageSaved === true) {
            if (previous.userMessageId !== requestId) throw new Error("RETRY_MESSAGE_UNCONFIRMED");
            // Messages have no user_id: ownership comes from the checked conversation.
            const { data: saved, error: savedError } = await supabaseAdmin.from("messages")
              .select("id, conversation_id, role, content, created_at")
              .eq("id", requestId).eq("conversation_id", conversationId).eq("role", "user").single();
            if (savedError || !saved || saved.content !== trimmedContent) throw new Error("RETRY_MESSAGE_UNCONFIRMED");
            userMessage = saved;
            execution.userMessageId = saved.id;
          } else if (previous.messageSaved !== false || previous.userMessageId != null) {
            throw new Error("RETRY_MESSAGE_UNCONFIRMED");
          }
        } else {
          return new Response(JSON.stringify({ error: "Request outcome pending. Reload history before sending again." }), { status: 409, headers: responseHeaders });
        }
      }
      if (!claimError) execution.messageSaved = false;
      execution.receipt = { userId: user.id, requestId };
    } else {
      execution.messageSaved = false;
    }

    // Get user profile to check subscription tier
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("subscription_tier, preferred_language")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      // Generic error - don't leak internal details
      console.error("Profile fetch failed:", profileError?.code);
      return new Response(
        JSON.stringify({ error: "Unable to process request" }),
        { status: 500, headers: responseHeaders },
      );
    }

    // Privacy settings must be available before any history reaches a provider.
    const { data: userSettings, error: settingsError } = await supabaseAdmin
      .from("user_settings")
      .select("privacy_mode, ai_tone")
      .eq("user_id", user.id)
      .maybeSingle();
    if (settingsError || !userSettings) {
      return new Response(JSON.stringify({ error: "Unable to load privacy settings" }), {
        status: 503,
        headers: responseHeaders,
      });
    }

    // PRIVACY FIX #005: Schema uses TEXT ('standard' | 'enhanced'), not boolean
    const privacyMode = (userSettings?.privacy_mode || "standard") as
      | "standard"
      | "enhanced";
    const privacyModeEnabled = privacyMode === "enhanced";

    // PRIVACY FIX #005: Normalize schema values (friendly|professional) to code values (supportive|direct)
    const aiToneRaw = (userSettings?.ai_tone || "friendly") as string;
    const aiTone =
      aiToneRaw === "friendly"
        ? "supportive"
        : aiToneRaw === "professional"
          ? "direct"
          : aiToneRaw; // gentle and motivational map directly

    const now = new Date();
    const { data: sponsoredAccess, error: sponsoredError } = await supabaseAdmin
      .rpc("refresh_sponsored_entitlement", { p_user_id: user.id });
    if (sponsoredError || typeof sponsoredAccess !== "boolean") {
      return new Response(JSON.stringify({ error: "Unable to verify access" }), {
        status: 503,
        headers: responseHeaders,
      });
    }
    const isPremium = profile.subscription_tier === "premium" || sponsoredAccess;

    // Crisis detection - SAFETY CRITICAL
    // SEC-CRIT-007: Use multi-language crisis detection with English fallback
    // Language preference already fetched above in userSettings query
    const userLanguage = profile.preferred_language || "en";

    if (detectCrisisMultiLang(trimmedContent, userLanguage)) {
      // Log crisis event WITHOUT storing user's actual content (PII protection)
      const matchedKeyword = getMatchedCrisisKeyword(
        trimmedContent,
        userLanguage,
      );
      await supabaseAdmin.from("crisis_events").insert({
        user_id: user.id,
        conversation_id: conversationId,
        trigger_content: matchedKeyword, // Only store which keyword matched, not actual content
        detected_at: now.toISOString(),
      });

      // Alert connected therapists (if crisis_alerts_enabled)
      try {
        const { data: connections } = await supabaseAdmin
          .from("therapy_connections")
          .select(
            `
            id,
            therapist_id,
            therapist_accounts!inner (
              user_id,
              practice_name
            ),
            profiles!therapy_connections_client_id_fkey (
              display_name
            )
          `,
          )
          .eq("client_id", user.id)
          .eq("status", "active")
          .eq("crisis_alerts_enabled", true);

        if (connections && connections.length > 0) {
          // Get client name for notification
          const clientName =
            (Array.isArray(connections[0]?.profiles) ? connections[0]?.profiles[0] : connections[0]?.profiles)?.display_name || "A client";

          // Send notification to each connected therapist
          for (const connection of connections) {
            const therapistUserId = Array.isArray(connection.therapist_accounts)
              ? connection.therapist_accounts[0]?.user_id
              : (connection.therapist_accounts as { user_id?: string } | null)?.user_id;

            if (therapistUserId) {
              // Send push notification
              await supabaseAdmin.from("notification_history").insert({
                user_id: therapistUserId,
                title: `Crisis Alert: ${clientName}`,
                body: "Immediate attention needed - crisis keywords detected",
                type: "therapist_crisis_alert",
                data: {
                  clientId: user.id,
                  clientName: clientName,
                  timestamp: now.toISOString(),
                  severity: "high",
                },
                is_read: false,
              });

              // Log to audit trail
              await supabaseAdmin.from("therapy_access_log").insert({
                connection_id: connection.id,
                therapist_id: connection.therapist_id,
                action: "crisis_alert_sent",
                resource_type: "crisis_event",
                created_at: now.toISOString(),
              });
            }
          }
        }
      } catch (alertError) {
        // Log error but don't block crisis response
        console.error("Failed to send therapist crisis alerts:", alertError);
      }

      let crisisUserMessage = userMessage;
      if (!crisisUserMessage) {
        // A lost insert response cannot establish whether the row was saved.
        execution.messageSaved = null;
        const { data: saved, error: saveError } = await supabaseAdmin
          .from("messages")
          .insert({
            ...(requestId ? { id: requestId } : {}),
            conversation_id: conversationId,
            role: "user",
            content: trimmedContent,
          }).select().single();
        if (saveError || !saved) throw new Error("USER_MESSAGE_NOT_SAVED");
        crisisUserMessage = saved;
      }
      if (!crisisUserMessage) throw new Error("USER_MESSAGE_NOT_SAVED");
      execution.userMessageId = crisisUserMessage.id;

      // Save crisis response
      const { data: crisisMessage, error: crisisMessageError } = await supabaseAdmin
        .from("messages")
        .insert({
          conversation_id: conversationId,
          role: "assistant",
          content: CRISIS_RESPONSE,
        })
        .select()
        .single();
      if (crisisMessageError || !crisisMessage) throw new Error("ASSISTANT_MESSAGE_NOT_SAVED");

      // Update conversation timestamp
      await supabaseAdmin
        .from("conversations")
        .update({ updated_at: now.toISOString() })
        .eq("id", conversationId);

      // Helper to convert date to Unix timestamp (seconds) for iOS Swift Codable
      const toUnixTs = (dateStr: string | null | undefined): number => {
        if (!dateStr) return now.getTime() / 1000;
        return new Date(dateStr).getTime() / 1000;
      };

      return new Response(
        JSON.stringify({
          // EXE-007: Return full message objects for both user and assistant
          userMessage: {
            id: crisisUserMessage?.id,
            role: "user",
            content: trimmedContent,
            createdAt: toUnixTs(crisisUserMessage?.created_at),
            blocked: false,
          },
          assistantMessage: {
            id: crisisMessage?.id,
            role: "assistant",
            content: CRISIS_RESPONSE,
            createdAt: toUnixTs(crisisMessage?.created_at),
            blocked: true,
          },
          // Legacy field for backward compatibility
          message: {
            id: crisisMessage?.id,
            role: "assistant",
            content: CRISIS_RESPONSE,
            createdAt: toUnixTs(crisisMessage?.created_at),
            blocked: true,
          },
          isCrisisResponse: true,
        }),
        { headers: responseHeaders },
      );
    }

    // Get conversation history for context
    const { data: history } = await supabaseAdmin
      .from("messages")
      .select("id, role, content")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: false })
      .limit(20); // Fetch the newest context, then put it in chronological order.
    // A retry appends the current user input below, so omit its saved copy here.
    const messages = (history as (Message & { id: string })[] | null)
      ?.filter((message) => message.id !== userMessage?.id);
    messages?.reverse();

    // Fetch relevant memories for context injection ONLY if privacy mode is OFF
    let memoryContext = "";
    if (!privacyModeEnabled) {
      const { data: memories } = await supabaseAdmin
        .from("memory_fragments")
        .select("fragment_type, key, value, confidence, scheduled_time")
        .eq("user_id", user.id)
        .or(`expires_at.is.null,expires_at.gt.${now.toISOString()}`)
        .order("confidence", { ascending: false })
        .limit(10);

      // Build memory context string for system prompt (format: key: value)
      if (memories && memories.length > 0) {
        const grouped: Record<string, string[]> = {
          person: [],
          fact: [],
          preference: [],
        };
        const upcomingEvents: string[] = [];
        const pastEvents: string[] = [];

        for (const mem of memories) {
          if (mem.fragment_type === "event") {
            // For events, check scheduled_time to determine if past or upcoming
            if (mem.scheduled_time) {
              const eventTime = new Date(mem.scheduled_time);
              const timeDiff = eventTime.getTime() - now.getTime();
              const hoursDiff = timeDiff / (1000 * 60 * 60);

              if (timeDiff > 0) {
                // Upcoming event - format relative to now
                let timeDesc: string;
                if (hoursDiff < 1) {
                  const mins = Math.round(timeDiff / (1000 * 60));
                  timeDesc = `in ${mins} minute${mins !== 1 ? "s" : ""}`;
                } else if (hoursDiff < 24) {
                  const hrs = Math.round(hoursDiff * 10) / 10;
                  timeDesc = `in ${hrs} hour${hrs !== 1 ? "s" : ""}`;
                } else {
                  const days = Math.round(hoursDiff / 24);
                  timeDesc = `in ${days} day${days !== 1 ? "s" : ""}`;
                }
                upcomingEvents.push(`${mem.value} (${timeDesc})`);
              } else {
                // Past event - format for follow-up
                const hoursAgo = Math.abs(hoursDiff);
                let timeDesc: string;
                if (hoursAgo < 1) {
                  const minsAgo = Math.round(Math.abs(timeDiff) / (1000 * 60));
                  timeDesc = `${minsAgo} minute${minsAgo !== 1 ? "s" : ""} ago`;
                } else if (hoursAgo < 24) {
                  const hrs = Math.round(hoursAgo * 10) / 10;
                  timeDesc = `${hrs} hour${hrs !== 1 ? "s" : ""} ago`;
                } else {
                  const days = Math.round(hoursAgo / 24);
                  timeDesc = `${days} day${days !== 1 ? "s" : ""} ago`;
                }
                pastEvents.push(`${mem.value} (${timeDesc})`);
              }
            } else {
              // No scheduled_time (legacy data), show as-is
              upcomingEvents.push(`${mem.key}: ${mem.value}`);
            }
          } else {
            // Non-event memories
            if (!grouped[mem.fragment_type]) grouped[mem.fragment_type] = [];
            grouped[mem.fragment_type].push(`${mem.key}: ${mem.value}`);
          }
        }

        memoryContext = "\n\n## What you know about this user:\n";
        if (grouped.person && grouped.person.length > 0) {
          memoryContext += `- People in their life: ${grouped.person.join(
            ", ",
          )}\n`;
        }
        if (grouped.fact && grouped.fact.length > 0) {
          memoryContext += `- Facts about them: ${grouped.fact.join(", ")}\n`;
        }
        if (grouped.preference && grouped.preference.length > 0) {
          memoryContext += `- Their preferences: ${grouped.preference.join(
            ", ",
          )}\n`;
        }
        if (upcomingEvents.length > 0) {
          memoryContext += `- Upcoming events: ${upcomingEvents.join(", ")}\n`;
        }
        if (pastEvents.length > 0) {
          memoryContext += `- Recent events to ask about (follow up warmly): ${pastEvents.join(", ")}\n`;
        }
        memoryContext +=
          "\nUse this context naturally in conversation when relevant. For past events, warmly ask how they went. Reference details to show you remember and care.";
      }
    }

    // Fetch companion memories (user-curated Memory Vault) ONLY if privacy mode is OFF
    let companionMemoryContext = "";
    let memoryIdsUsed: string[] = [];

    if (!privacyModeEnabled) {
      try {
        // Fetch active companion memories and current daily intent
        const { data: companionMemories } = await supabaseAdmin
          .from("companion_memory")
          .select("id, category, content")
          .eq("user_id", user.id)
          .is("deleted_at", null)
          .order("last_used_at", { ascending: false, nullsFirst: false })
          .limit(20);

        const { data: dailyIntent } = await supabaseAdmin
          .from("daily_intents")
          .select("intent")
          .eq("user_id", user.id)
          .gt("expires_at", now.toISOString())
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        // Build companion memory context if any exist
        if (
          (companionMemories && companionMemories.length > 0) ||
          dailyIntent?.intent
        ) {
          companionMemoryContext =
            "\n\n## User-defined companion context (Memory Vault):\n";

          // Add daily intent if set
          if (dailyIntent?.intent) {
            // Sanitize intent to prevent prompt injection
            const sanitizedIntent = sanitizeForPrompt(dailyIntent.intent);
            companionMemoryContext += `**Today's focus:** "${sanitizedIntent}"\n\n`;
          }

          // Group memories by category
          if (companionMemories && companionMemories.length > 0) {
            const categoryLabels: Record<string, string> = {
              boundaries: "Boundaries to respect",
              preferences: "Preferences",
              triggers: "Topics that may be sensitive",
              avoid_topics: "Topics to avoid",
              positive_reinforcement:
                "Things that help (positive reinforcement)",
              life_context: "Life context",
            };

            const grouped: Record<string, string[]> = {};
            for (const mem of companionMemories) {
              if (!grouped[mem.category]) grouped[mem.category] = [];
              // Sanitize each memory content to prevent prompt injection
              const sanitizedContent = sanitizeForPrompt(mem.content);
              grouped[mem.category].push(sanitizedContent);
              memoryIdsUsed.push(mem.id);
            }

            for (const [category, items] of Object.entries(grouped)) {
              const label = categoryLabels[category] || category;
              companionMemoryContext += `- ${label}: ${items.join("; ")}\n`;
            }

            companionMemoryContext +=
              "\nHonor these user-defined preferences and boundaries in all interactions.";
          }
        }
      } catch (memoryError) {
        // Non-critical: continue chat without companion memory if fetch fails
        console.error(
          "Companion memory fetch failed (non-critical):",
          memoryError,
        );
      }
    }

    // Fetch re-engagement context (for returning users after absence)
    let reengagementContext = "";
    const { data: profileExtended } = await supabaseAdmin
      .from("profiles")
      .select("last_absence_days")
      .eq("id", user.id)
      .single();

    if (
      profileExtended?.last_absence_days &&
      profileExtended.last_absence_days >= 3
    ) {
      const days = profileExtended.last_absence_days;
      reengagementContext = "\n\n## Important context - Returning user:\n";
      reengagementContext += `The user is returning after ${days} days away. `;

      if (days >= 30) {
        reengagementContext +=
          "This is a significant return after a long hiatus. Be very welcoming and supportive. Help them ease back in without any pressure. ";
      } else if (days >= 14) {
        reengagementContext +=
          "They've been away for a while. Be especially warm and supportive. Don't ask why they were away - focus on being glad they're back. ";
      } else if (days >= 7) {
        reengagementContext +=
          "They've been away for about a week. Acknowledge their return positively and gently check in on how they're doing. ";
      } else {
        reengagementContext +=
          "They took a brief break. Welcome them back warmly but don't make a big deal of it. ";
      }
      reengagementContext +=
        "Do not mention specific day counts. Focus on the present moment and supporting their wellness journey.";
    }

    // Build AI tone instruction based on user preference
    let toneInstruction = "";
    switch (aiTone) {
      case "gentle":
        toneInstruction =
          "\n\n## Tone preference:\nUse an extra gentle, soft, and comforting tone. Be especially delicate with feedback and focus on nurturing support.";
        break;
      case "direct":
        toneInstruction =
          "\n\n## Tone preference:\nBe clear and straightforward. The user prefers honest, practical advice without excessive softening.";
        break;
      case "motivational":
        toneInstruction =
          "\n\n## Tone preference:\nBe encouraging and energizing. Use motivational language and help the user see their potential.";
        break;
      case "supportive":
      default:
        toneInstruction =
          "\n\n## Tone preference:\nUse a warm, balanced, supportive tone that validates feelings while offering practical guidance.";
        break;
    }

    const enhancedSystemPrompt =
      SYSTEM_PROMPT +
      toneInstruction +
      memoryContext +
      companionMemoryContext +
      reengagementContext;

    // Sanitize user content to prevent prompt injection attacks
    // This removes role impersonation attempts and prompt manipulation patterns
    const sanitizedContent = sanitizeForPrompt(trimmedContent);

    // Build message history for AI
    const messageHistory: Message[] = trimChatContext([
      { role: "system", content: enhancedSystemPrompt },
      ...(messages || []).map((m) => ({
        role: m.role as "user" | "assistant",
        // Sanitize historical messages too for defense in depth
        content: m.role === "user" ? sanitizeForPrompt(m.content) : m.content,
      })),
      { role: "user", content: sanitizedContent },
    ]);

    req.signal.throwIfAborted();
    let quotaUsed = 0;
    let quotaLimit = 0;
    const assistantContent = await generateChatText(messageHistory, {
      apiKey: OPENAI_API_KEY,
      reserveBudget: openAIBudgetReservation(supabaseAdmin, user.id, "chat.response", req.signal),
      maxOutputTokens: 500,
      onDelta,
      signal: req.signal,
      beforeProvider: async () => {
        // Atomically check and increment quota (prevents race conditions)
        console.log("[6] Checking AI quota, isPremium:", isPremium);
        const { data: quotaResult, error: quotaError } = await supabaseAdmin.rpc(
          "check_and_increment_ai_quota",
          {
            p_user_id: user.id,
            p_is_premium: isPremium,
          },
        );
        console.log(
          "[6] Quota result:",
          JSON.stringify(quotaResult),
          quotaError?.message || "",
        );

        if (quotaError) {
          console.error("Quota check failed:", quotaError.code);
          throw new Response(
            JSON.stringify({ error: "Unable to process request" }),
            { status: 500, headers: responseHeaders },
          );
        }

        // Handle both TABLE (array) and JSON (object) return types
        const quotaData = Array.isArray(quotaResult)
          ? quotaResult?.[0]
          : quotaResult;
        if (!quotaData || typeof quotaData.allowed !== "boolean" ||
          !Number.isInteger(quotaData.quota_used) || quotaData.quota_used < 0 ||
          !Number.isInteger(quotaData.quota_limit) ||
          (quotaData.quota_limit < 0 && !(isPremium && quotaData.quota_limit === -1))) {
          throw new Error("QUOTA_ADMISSION_UNCONFIRMED");
        }
        if (!quotaData.allowed) {
          throw new Response(
            JSON.stringify({
              error: "AI_QUOTA_EXCEEDED",
              message:
                "You've reached your daily AI chat allowance.",
              quotaUsed: quotaData.quota_used,
              quotaLimit: quotaData.quota_limit,
              code: "chat_quota_exhausted",
              retryable: true,
            }),
            { status: 429, headers: responseHeaders },
          );
        }

        quotaUsed = quotaData.quota_used;
        quotaLimit = quotaData.quota_limit;
        req.signal.throwIfAborted();
        // Save only after both spending and atomic user-quota admission succeed.
        if (!userMessage) {
          execution.messageSaved = null;
          const { data: saved, error: saveError } = await supabaseAdmin.from("messages")
            .insert({
              ...(requestId ? { id: requestId } : {}),
              conversation_id: conversationId,
              role: "user",
              content: trimmedContent,
            }).select().single();
          if (saveError || !saved) throw new Error("USER_MESSAGE_NOT_SAVED");
          userMessage = saved;
          execution.userMessageId = saved.id;
        }
      },
    }).catch((error: unknown) => {
      knownProviderFailure = error instanceof Error &&
        (/^AI_HTTP_\d{3}$/.test(error.message) || ["AI_EMPTY_RESPONSE", "AI_TERMINAL_FAILED", "AI_STREAM_FAILED"].includes(error.message));
      throw error;
    });
    req.signal.throwIfAborted();

    // Save assistant message
    const { data: assistantMessage, error: assistantSaveError } = await supabaseAdmin
      .from("messages")
      .insert({
        conversation_id: conversationId,
        role: "assistant",
        content: assistantContent,
      })
      .select()
      .single();

    if (assistantSaveError || !assistantMessage) throw new Error("ASSISTANT_MESSAGE_NOT_SAVED");

    // Update conversation timestamp
    await supabaseAdmin
      .from("conversations")
      .update({ updated_at: now.toISOString() })
      .eq("id", conversationId);

    // Cognitive Bias Coach detection (after AI response, before title generation)
    let coachData: any = null;
    let conversationTitle: string | null = null; // TODO: Implement title generation

    try {
      // Fetch coach settings for this user (with 5-minute cache)
      const coachSettings = await getCachedCoachSettings(
        supabaseAdmin,
        user.id,
      );

      // Fetch user's language preference
      const { data: userProfile } = await supabaseAdmin
        .from("profiles")
        .select("preferred_language")
        .eq("id", user.id)
        .single();

      const userLanguage = userProfile?.preferred_language || "en";

      // Check if coach is enabled
      const isCoachEnabled = coachSettings?.is_enabled !== false; // Default to enabled

      if (isCoachEnabled) {
        // Check silent hours - convert current time to user's timezone
        const userTimezone = coachSettings?.timezone || "UTC";
        const now = new Date();

        // Use Intl API to get time in user's timezone
        const formatter = new Intl.DateTimeFormat("en-US", {
          timeZone: userTimezone,
          hour: "numeric",
          minute: "numeric",
          hour12: false,
        });

        const parts = formatter.formatToParts(now);
        const currentHour = parseInt(
          parts.find((p) => p.type === "hour")?.value || "0",
        );
        const currentMinute = parseInt(
          parts.find((p) => p.type === "minute")?.value || "0",
        );
        const currentTimeMinutes = currentHour * 60 + currentMinute;

        let inSilentHours = false;
        if (
          coachSettings?.silent_hours_start &&
          coachSettings?.silent_hours_end
        ) {
          const parseTime = (timeStr: string) => {
            const [h, m] = timeStr.split(":").map(Number);
            return h * 60 + m;
          };
          const startMinutes = parseTime(coachSettings.silent_hours_start);
          const endMinutes = parseTime(coachSettings.silent_hours_end);

          // Handle midnight wrap (e.g., 22:00 to 02:00)
          if (startMinutes > endMinutes) {
            inSilentHours =
              currentTimeMinutes >= startMinutes ||
              currentTimeMinutes < endMinutes;
          } else {
            inSilentHours =
              currentTimeMinutes >= startMinutes &&
              currentTimeMinutes < endMinutes;
          }
        }

        if (!inSilentHours) {
          // Check if this is a new topic (first 3 messages)
          const messageCount = (messages?.length || 0) + 2; // +2 for current user + assistant messages
          const isNewTopic = messageCount <= 6; // First 3 exchanges = 6 messages (user + assistant pairs)

          if (!isNewTopic) {
            // Get sensitivity threshold
            const sensitivityLevel =
              coachSettings?.sensitivity_level || "balanced";
            const threshold = getSensitivityThreshold(sensitivityLevel);

            // Run detection on user's message
            const detection = detectDistortion(
              trimmedContent,
              userLanguage,
              threshold,
            );

            if (detection) {
              // Check if this distortion is disabled
              const disabledDistortions =
                coachSettings?.disabled_distortions || [];
              if (!disabledDistortions.includes(detection.distortionCode)) {
                // Fetch reframe
                const reframe = await getReframe(
                  supabaseAdmin,
                  detection.distortionCode,
                  trimmedContent,
                  userLanguage,
                );

                if (reframe) {
                  // Log encounter using atomic RPC function
                  const { data: rawEncounterResult, error: encounterError } =
                    await supabaseAdmin
                      .rpc("log_coach_encounter", {
                        p_user_id: user.id,
                        p_distortion_code: detection.distortionCode,
                        p_conversation_id: conversationId,
                        p_original_message_preview: trimmedContent.substring(
                          0,
                          200,
                        ),
                        p_reframe_text: reframe.reframeText,
                        p_confidence: detection.confidence,
                        p_encounter_type: "chat",
                      })
                      .single();

                  const encounterResult = rawEncounterResult as { success?: boolean; error_message?: string; encounter_id?: string } | null;
                  if (encounterError || !encounterResult?.success) {
                    console.error(
                      "Failed to log encounter:",
                      encounterError || encounterResult?.error_message,
                    );
                    // Continue anyway - don't block coach from showing
                  }

                  // Build coach data for response
                  coachData = {
                    encounterId: encounterResult?.encounter_id || null,
                    distortionCode: detection.distortionCode,
                    distortionName: reframe.distortionName,
                    shortDescription: reframe.shortDescription,
                    reframeText: reframe.reframeText,
                    educationalContent: reframe.educationalContent,
                    socraticQuestions: reframe.socraticQuestions,
                    confidence: detection.confidence,
                  };
                }
              }
            }
          }
        }
      }
    } catch (coachError) {
      // Non-critical: log but don't fail the chat
      console.error("Coach detection failed (non-critical):", coachError);
    }

    // Auto-generate conversation title if this is the first message
    const isFirstMessage = !messages || messages.length === 0;

    if (isFirstMessage) {
      // Generate title in background (fire-and-forget)
      retainBackground(generateConversationTitle(
        supabaseAdmin,
        user.id,
        conversationId,
        trimmedContent,
        assistantContent,
        OPENAI_API_KEY,
      ).catch(() => console.error("Title generation failed")));
    }

    // Quota was incremented atomically immediately before the provider request.

    // Extract memories in background ONLY if privacy mode is OFF
    if (!privacyModeEnabled) {
      retainBackground(extractMemories(
        supabaseAdmin,
        user.id,
        conversationId,
        trimmedContent,
        assistantContent,
        OPENAI_API_KEY,
      ).catch(() => console.error("Memory extraction failed")));
    }

    // Update companion memory usage stats (fire-and-forget with error logging)
    if (memoryIdsUsed.length > 0) {
      supabaseAdmin
        .rpc("update_companion_memory_usage", {
          memory_ids: memoryIdsUsed,
          used_at: now.toISOString(),
          for_user_id: user.id, // Pass user ID for ownership validation
        })
        .then(({ error }: { error: unknown }) => {
          if (error) {
            console.error("Failed to update companion memory usage:", error);
          } else {
            console.log(
              `Updated usage for ${memoryIdsUsed.length} companion memories`,
            );
          }
        });
    }

    // Helper to convert date to Unix timestamp (seconds) for iOS Swift Codable
    const toUnixTimestamp = (
      dateStr: string | null | undefined,
      fallback: Date,
    ): number => {
      if (!dateStr) return fallback.getTime() / 1000;
      return new Date(dateStr).getTime() / 1000;
    };

    return new Response(
      JSON.stringify({
        // EXE-007: Return full message objects for both user and assistant
        userMessage: {
          id: userMessage?.id,
          role: "user",
          content: trimmedContent,
          createdAt: toUnixTimestamp(userMessage?.created_at, now),
          blocked: false,
        },
        assistantMessage: {
          id: assistantMessage?.id,
          role: "assistant",
          content: assistantContent,
          createdAt: toUnixTimestamp(assistantMessage?.created_at, now),
          blocked: false,
        },
        // Legacy field for backward compatibility during transition
        message: {
          id: assistantMessage?.id,
          role: "assistant",
          content: assistantContent,
          createdAt: toUnixTimestamp(assistantMessage?.created_at, now),
          blocked: false,
        },
        userMessageId: userMessage?.id, // Legacy field for backward compatibility
        quotaUsed: quotaUsed,
        quotaLimit: quotaLimit,
        conversationTitle: conversationTitle,
        memoryUsed: memoryIdsUsed.length > 0,
        memoryIdsUsed: memoryIdsUsed,
        coachData: coachData,
      }),
      { headers: responseHeaders },
    );
  } catch (error) {
    if (error instanceof Response) return error;
    if (!req.signal.aborted && error instanceof MonthlyAIBudgetExhaustedError) {
      return new Response(JSON.stringify({ error: "AI_MONTHLY_BUDGET_REACHED", message: "The shared monthly AI spending allowance is exhausted.", code: "chat_shared_budget_exhausted", retryable: true }), { status: 503, headers: { ...baseCorsHeaders, "Content-Type": "application/json" } });
    }
    if (!req.signal.aborted && error instanceof MonthlyAIBudgetUnavailableError) {
      return new Response(JSON.stringify({ error: "AI_MONTHLY_BUDGET_UNAVAILABLE", message: "AI spending approval is temporarily unavailable. Please try again later.", code: "chat_shared_budget_unavailable", retryable: true }), { status: 503, headers: { ...baseCorsHeaders, "Content-Type": "application/json" } });
    }
    if (!req.signal.aborted && knownProviderFailure) {
      return new Response(JSON.stringify({ error: "AI provider unavailable", message: "The AI response could not be completed. You can explicitly retry this message.", code: "chat_provider_unavailable", retryable: true }), { status: 503, headers: { ...baseCorsHeaders, "Content-Type": "application/json" } });
    }
    // Log full error for debugging
    console.error("======== CHAT FUNCTION ERROR ========");
    console.error("Error type:", typeof error);
    console.error("Error name:", error instanceof Error ? error.name : "N/A");
    console.error(
      "Error message:",
      error instanceof Error ? error.message : String(error),
    );
    console.error("Error stack:", error instanceof Error ? error.stack : "N/A");
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      { status: 500, headers: baseCorsHeaders },
    );
  }
}

// Keep the JSON contract for installed releases. SSE is opt-in for the new client.
Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return handleChat(request, {});
  if (request.method !== "POST") return new Response(JSON.stringify(failedChatResponse({ error: "Method not allowed" }, {})), { status: 405, headers: { ...getCorsHeaders(request.headers.get("Origin")), "Content-Type": "application/json", Allow: "POST, OPTIONS" } });
  const execution: ChatExecution = {};
  const wantsStream = request.headers.get("Accept")?.includes("text/event-stream") && request.method === "POST";
  const abort = new AbortController();
  const req = new Request(request, { signal: AbortSignal.any([request.signal, abort.signal]) });
  let controller: ReadableStreamDefaultController<Uint8Array>;
  let started = false;
  let closed = false;
  let startStream: () => void;
  const ready = new Promise<void>((resolve) => { startStream = resolve; });
  const encoder = new TextEncoder();
  const emit = (event: unknown) => {
    if (!closed) controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
  };
  const stream = new ReadableStream<Uint8Array>({
    start(value) { controller = value; },
    cancel() { closed = true; abort.abort(); },
  });
  const result = handleChat(req, execution, wantsStream ? (text) => {
    if (!started) { started = true; startStream(); }
    emit({ type: "delta", text });
  } : undefined).then(async (response) => {
    let data = await response.json();
    if (!response.ok) data = failedChatResponse(data, execution);
    if (execution.receipt) {
      try {
        const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
        const { data: persisted, error } = await admin.from("chat_requests").update({ response: data, response_status: response.status })
          .eq("user_id", execution.receipt.userId).eq("request_id", execution.receipt.requestId)
          .select("request_id").maybeSingle();
        if (error || !persisted) throw new Error("RECEIPT_NOT_SAVED");
      } catch {
        // Keep the claim on any persistence ambiguity; it cannot authorize replay.
        console.error("Chat receipt persistence failed");
        data = failedChatResponse({ error: "Request outcome unconfirmed. Reload history before sending again." }, execution);
        response = new Response(null, { status: 503, headers: response.headers });
      }
    }
    response = new Response(JSON.stringify(data), { status: response.status, headers: response.headers });
    if (started) {
      emit({ type: response.ok ? "result" : "error", status: response.status, data });
      if (!closed) { closed = true; controller.close(); }
    }
    return response;
  });
  if (!wantsStream) return await result;
  const first = await Promise.race([
    result.then((response) => ({ response })),
    ready.then(() => ({ response: null })),
  ]);
  if (first.response) return first.response; // Auth/ownership/errors retain their HTTP status.
  return new Response(stream, {
    headers: { ...getCorsHeaders(request.headers.get("Origin")), "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
  });
});

// Title generation function - runs in background, non-blocking
async function generateConversationTitle(
  supabaseAdmin: UntypedSupabaseClient,
  userId: string,
  conversationId: string,
  userMessage: string,
  assistantMessage: string,
  openaiKey: string,
): Promise<void> {
  try {
    // Committed chat work may finish after the response, with its own bound.
    const signal = AbortSignal.timeout(45_000);
    const title = (await generateChatText([
      { role: "system", content: "Generate a concise 3-6 word conversation title. Return only the title." },
      { role: "user", content: `User: ${userMessage.slice(0, 200)}\nAssistant: ${assistantMessage.slice(0, 200)}` },
    ], { apiKey: openaiKey, reserveBudget: openAIBudgetReservation(supabaseAdmin, userId, "chat.title", signal), maxOutputTokens: 30, signal })).trim();

    if (title && title.length > 0 && title.length <= 100) {
      const { error } = await supabaseAdmin
        .from("conversations")
        .update({ title })
        .eq("id", conversationId);

      if (error) {
        console.error("Failed to update conversation title:", error);
      } else {
        console.log("Conversation title saved");
      }
    }
  } catch (err) {
    console.error("Title generation error:", err instanceof Error ? err.message : "Unknown");
  }
}

// Parse relative time expressions to absolute timestamps
// Handles: "in X hours", "in X minutes", "tomorrow at X", "next Monday", etc.
function parseRelativeTime(
  timeExpression: string,
  referenceTime: Date,
): Date | null {
  if (!timeExpression) return null;

  const expr = timeExpression.toLowerCase().trim();

  // Pattern: "in X hours" or "in X.X hours"
  const inHoursMatch = expr.match(/in\s+(\d+(?:\.\d+)?)\s*hours?/);
  if (inHoursMatch) {
    const hours = parseFloat(inHoursMatch[1]);
    return new Date(referenceTime.getTime() + hours * 60 * 60 * 1000);
  }

  // Pattern: "in X minutes"
  const inMinutesMatch = expr.match(/in\s+(\d+)\s*min(?:utes?)?/);
  if (inMinutesMatch) {
    const minutes = parseInt(inMinutesMatch[1]);
    return new Date(referenceTime.getTime() + minutes * 60 * 1000);
  }

  // Pattern: "in X days"
  const inDaysMatch = expr.match(/in\s+(\d+)\s*days?/);
  if (inDaysMatch) {
    const days = parseInt(inDaysMatch[1]);
    return new Date(referenceTime.getTime() + days * 24 * 60 * 60 * 1000);
  }

  // Pattern: "tomorrow" (optionally with time)
  if (expr.includes("tomorrow")) {
    const tomorrow = new Date(referenceTime);
    tomorrow.setDate(tomorrow.getDate() + 1);

    // Try to extract time like "tomorrow at 2pm" or "tomorrow at 14:00"
    const timeMatch = expr.match(/at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
    if (timeMatch) {
      let hour = parseInt(timeMatch[1]);
      const minutes = timeMatch[2] ? parseInt(timeMatch[2]) : 0;
      const ampm = timeMatch[3]?.toLowerCase();
      if (ampm === "pm" && hour < 12) hour += 12;
      if (ampm === "am" && hour === 12) hour = 0;
      tomorrow.setHours(hour, minutes, 0, 0);
    } else {
      // Default to 9am if no time specified
      tomorrow.setHours(9, 0, 0, 0);
    }
    return tomorrow;
  }

  // Pattern: weekday names (next Monday, this Friday, etc.)
  const weekdays = [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ];
  for (let i = 0; i < weekdays.length; i++) {
    if (expr.includes(weekdays[i])) {
      const targetDay = i;
      const currentDay = referenceTime.getDay();
      let daysToAdd = targetDay - currentDay;
      if (daysToAdd <= 0) daysToAdd += 7; // Next occurrence
      if (expr.includes("next")) daysToAdd += 7; // "next Monday" means following week

      const targetDate = new Date(referenceTime);
      targetDate.setDate(targetDate.getDate() + daysToAdd);

      // Try to extract time
      const timeMatch = expr.match(/at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
      if (timeMatch) {
        let hour = parseInt(timeMatch[1]);
        const minutes = timeMatch[2] ? parseInt(timeMatch[2]) : 0;
        const ampm = timeMatch[3]?.toLowerCase();
        if (ampm === "pm" && hour < 12) hour += 12;
        if (ampm === "am" && hour === 12) hour = 0;
        targetDate.setHours(hour, minutes, 0, 0);
      } else {
        targetDate.setHours(9, 0, 0, 0);
      }
      return targetDate;
    }
  }

  // Pattern: specific time like "at 2pm" or "at 14:00" (assume today)
  const justTimeMatch = expr.match(
    /^(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i,
  );
  if (justTimeMatch) {
    const result = new Date(referenceTime);
    let hour = parseInt(justTimeMatch[1]);
    const minutes = justTimeMatch[2] ? parseInt(justTimeMatch[2]) : 0;
    const ampm = justTimeMatch[3]?.toLowerCase();
    if (ampm === "pm" && hour < 12) hour += 12;
    if (ampm === "am" && hour === 12) hour = 0;
    result.setHours(hour, minutes, 0, 0);
    // If time has passed today, assume tomorrow
    if (result <= referenceTime) {
      result.setDate(result.getDate() + 1);
    }
    return result;
  }

  // Could not parse - return null
  return null;
}

// Memory extraction function - runs in background, non-blocking
async function extractMemories(
  supabaseAdmin: UntypedSupabaseClient,
  userId: string,
  conversationId: string,
  userMessage: string,
  _assistantMessage: string,
  openaiKey: string,
): Promise<void> {
  // Sanitize user input to prevent prompt injection
  const sanitizedMessage = sanitizeForPrompt(userMessage);

  const extractionPrompt = `Analyze this user message and extract any facts they revealed about themselves.
Return a JSON array of objects with "type", "key", "value", and optionally "time_expression" fields.

Types:
- "person": Names of family members, friends, pets, coworkers
- "event": Upcoming events, plans, or recent experiences with dates if mentioned
- "preference": Likes, dislikes, communication preferences
- "fact": Job, location, hobbies, other personal facts

Format:
- key: short snake_case identifier (e.g., "dog_name", "partner_name", "work_presentation", "favorite_exercise")
- value: a clean description of the event/item (e.g., "Max", "Sarah", "Job Interview", "Therapy Appointment")
- time_expression: (ONLY for events) the exact time phrase the user used (e.g., "in 1.5 hours", "tomorrow at 2pm", "next Monday", "Friday at 10am")

Rules:
- Only extract clear, explicit information - don't infer or guess
- Keep key short (under 30 chars) and value concise (under 100 chars)
- For events, ALWAYS include "time_expression" with the exact time phrase from the message
- If nothing new is shared, return empty array []
- Don't extract emotional states or temporary feelings

<user_message>
${sanitizedMessage}
</user_message>

Return ONLY valid JSON array, no explanation. Example: [{"type": "person", "key": "sister_name", "value": "Emma"}, {"type": "event", "key": "job_interview", "value": "Job Interview", "time_expression": "next Monday at 10am"}]`;

  try {
    const signal = AbortSignal.timeout(45_000);
    const extracted = await generateChatText([
      { role: "system", content: "Extract structured personal facts. Return only a valid JSON array." },
      { role: "user", content: extractionPrompt },
    ], { apiKey: openaiKey, reserveBudget: openAIBudgetReservation(supabaseAdmin, userId, "chat.memory", signal), maxOutputTokens: 500, signal });

    // Parse JSON response
    let memories: Array<{
      type: string;
      key: string;
      value: string;
      time_expression?: string;
    }>;
    try {
      // Clean up response - sometimes models add markdown formatting
      const cleaned = extracted.replace(/```json\n?|\n?```/g, "").trim();
      memories = JSON.parse(cleaned);
    } catch {
      console.error("Memory extraction JSON parse failed");
      return;
    }

    if (!Array.isArray(memories) || memories.length === 0) return;

    // Filter valid types and sanitize content
    const validTypes = ["person", "event", "preference", "fact"];
    const now = new Date();

    // Sanitize helper function
    const sanitize = (str: string, maxLen: number): string =>
      str
        .replace(/<[^>]*>/g, "") // Remove HTML tags
        .replace(/[<>]/g, "") // Remove angle brackets
        .trim()
        .substring(0, maxLen);

    const candidates = memories
      .filter(
        (m) =>
          validTypes.includes(m.type) &&
          typeof m.key === "string" &&
          m.key.length > 0 &&
          typeof m.value === "string" &&
          m.value.length > 0,
      )
      .map((m) => ({
        type: m.type,
        key: sanitize(m.key.toLowerCase().replace(/\s+/g, "_"), 50),
        value: sanitize(m.value, 500),
        time_expression: m.time_expression
          ? sanitize(m.time_expression, 100)
          : undefined,
      }))
      .filter((m) => m.key.length > 0 && m.value.length > 0);

    if (candidates.length === 0) return;

    // Use upsert with the UNIQUE constraint (user_id, fragment_type, key)
    // This will update existing memories with same key instead of duplicating
    const upserts = candidates.map((m) => {
      // For events with time expressions, parse to absolute timestamp
      let scheduledTime: string | null = null;
      let expiresAt: string | null = null;

      if (m.type === "event") {
        if (m.time_expression) {
          const parsed = parseRelativeTime(m.time_expression, now);
          if (parsed) {
            scheduledTime = parsed.toISOString();
            // Expire 24 hours after the event for follow-up conversations
            expiresAt = new Date(
              parsed.getTime() + 24 * 60 * 60 * 1000,
            ).toISOString();
          } else {
            // Couldn't parse time, use 7-day default expiry
            expiresAt = new Date(
              Date.now() + 7 * 24 * 60 * 60 * 1000,
            ).toISOString();
          }
        } else {
          // No time expression, use 7-day default expiry
          expiresAt = new Date(
            Date.now() + 7 * 24 * 60 * 60 * 1000,
          ).toISOString();
        }
      }

      return {
        user_id: userId,
        fragment_type: m.type,
        key: m.key,
        value: m.value,
        confidence: 0.8,
        source_conversation_id: conversationId,
        extracted_at: now.toISOString(),
        updated_at: now.toISOString(),
        scheduled_time: scheduledTime,
        expires_at: expiresAt,
      };
    });

    const { error } = await supabaseAdmin
      .from("memory_fragments")
      .upsert(upserts, {
        onConflict: "user_id,fragment_type,key",
        ignoreDuplicates: false,
      });
    if (error) {
      console.error("Memory upsert error:", error.message);
    } else {
      console.log(
        `Extracted/updated ${upserts.length} memories from conversation`,
      );
    }
  } catch (err) {
    // Log but don't throw - extraction is non-critical
    console.error(
      "Memory extraction error:",
      err instanceof Error ? err.message : "Unknown",
    );
  }
}
