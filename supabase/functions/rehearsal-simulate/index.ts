// MindFriend Conversation Rehearsal Edge Function
// Handles scenario creation, AI role-play simulation, and communication feedback

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;

import { getCorsHeaders } from "../_shared/cors.ts";
import { detectCrisis, getMatchedCrisisKeyword, CRISIS_RESPONSE } from "../_shared/crisis.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

// TYPE DEFINITIONS
interface PrebuiltScenario {
  id: string;
  category: string;
  title: string;
  description: string;
  situation_context: string;
  other_party_role: string;
  other_party_personality?: string;
  key_points_to_convey: string[];
  desired_outcome: string;
  difficulty_level: string;
  estimated_minutes: number;
  tips_for_user?: string[];
  tags?: string[];
  is_premium: boolean;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

interface CustomScenarioData {
  id: string;
  user_id: string;
  title: string;
  other_party_role: string;
  situation_summary: string;
  key_points: string[];
  desired_outcome: string;
  situation_type: string;
  context_details?: Record<string, string>;
  is_public: boolean;
  created_at: string;
  updated_at: string;
}

type ScenarioUnion = PrebuiltScenario | CustomScenarioData;

interface CreateScenarioParams {
  title: string;
  description: string;
  personRole: string;
  situationType: string;
  keyPoints: string[];
  desiredOutcome: string;
}

interface StartSessionParams {
  scenarioId?: string;
  customScenarioId?: string;
}

interface SendMessageParams {
  sessionId: string;
  message: string;
}

interface EndSessionParams {
  sessionId: string;
  confidenceRating?: number;
  notes?: string;
}

type SituationType = "conflict" | "feedback" | "boundary" | "request" | "other";

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface TranscriptEntry {
  role: "user" | "assistant";
  content: string;
  timestamp?: string;
}

interface GetScenariosParams {
  type?: "prebuilt" | "custom";
}

interface GetSessionHistoryParams {
  limit?: number;
  offset?: number;
  status?: "active" | "completed" | "abandoned" | "crisis_ended";
}

interface FeedbackResult {
  feedback: string;
  suggestions: string[];
  confidenceRating: number;
}

interface UpdateLayoutPreferencesRequest {
  layoutType?: string;
  hideCompletedSessions?: boolean;
  groupBySituation?: boolean;
}

// Constants
const MAX_MESSAGE_LENGTH = 1000; // Rehearsal messages are shorter
const FREE_TIER_WEEKLY_QUOTA = 2;
const FREE_TIER_EXCHANGES_LIMIT = 10;
const XAI_API_URL = "https://api.x.ai/v1/chat/completions";

// AI Prompts for role simulation
const ROLE_SIMULATION_PROMPT = (
  scenario: ScenarioUnion,
) => `You are role-playing as ${sanitizeForPrompt(scenario.other_party_role)} in a ${
  "situation_type" in scenario ? sanitizeForPrompt(scenario.situation_type) : "conversation"
}.

Scenario context: ${
  "situation_context" in scenario ? sanitizeForPrompt(scenario.situation_context) : sanitizeForPrompt(scenario.situation_summary)
}
Your personality: ${
  "other_party_personality" in scenario && scenario.other_party_personality
    ? sanitizeForPrompt(scenario.other_party_personality)
    : "neutral and realistic"
}

Guidelines:
-- Stay in character throughout the conversation
-- Respond naturally as this person would
-- Be realistic - don't make it too easy or too hard
-- Keep responses concise (1-3 sentences)
-- React to the user's tone and approach
-- Show appropriate emotions for the situation
-- If unclear, ask clarifying questions as the character would

Remember: You are helping the user practice. Be realistic but constructive.`;

const FEEDBACK_PROMPT = (
  userMessage: string,
  context: string,
) => `Analyze this message from a conversation practice scenario:

Context: ${context}
User's message: "${userMessage}"

Provide constructive feedback on:
1. Communication style (assertive/passive/aggressive/collaborative/empathetic/defensive)
2. Clarity (1-10)
3. Empathy shown (1-10)
4. Assertiveness balance (1-10)
5. One specific strength
6. One specific improvement suggestion

Format your response as JSON:
{
  "tone": "assertive|passive|aggressive|collaborative|empathetic|defensive",
  "clarity": 7.5,
  "empathy": 8.0,
  "assertiveness": 6.5,
  "strength": "Clear use of 'I' statements",
  "improvement": "Consider acknowledging their perspective first"
}`;

// Helper to normalize scenario fields across both types
function normalizeScenario(scenario: ScenarioUnion): {
  title: string;
  role: string;
  personality: string;
  context: string;
} {
  return {
    title: scenario.title,
    role: scenario.other_party_role,
    personality:
      ("other_party_personality" in scenario && scenario.other_party_personality)
        ? scenario.other_party_personality
        : "neutral and realistic",
    context:
      "situation_context" in scenario
        ? scenario.situation_context
        : scenario.situation_summary,
  };
}

// FIX P0: Sanitize AI responses to prevent XSS and prompt injection
// Removes control characters, HTML tags, and suspicious patterns
function sanitizeAIResponse(content: string): string {
  if (!content) return "";
  
  // Remove control characters and null bytes
  let sanitized = content.replace(/[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]/g, "");
  
  // Remove HTML tags to prevent injection if rendered in WebView
  sanitized = sanitized.replace(/<[^>]*>/g, "");
  
  // Remove common LLM markers that could be prompt injection attempts
  sanitized = sanitized
    .replace(/\[SYSTEM\]/gi, "")
    .replace(/\[INSTRUCTION\]/gi, "")
    .replace(/\[JAILBREAK\]/gi, "")
    .replace(/```[\s\S]*?```/g, ""); // Remove code blocks
  
  // Normalize unicode to prevent homoglyph attacks
  sanitized = sanitized.normalize("NFKC");
  
  // Truncate to max length (prevent memory exhaustion)
  const MAX_RESPONSE_LENGTH = 5000;
  return sanitized.slice(0, MAX_RESPONSE_LENGTH).trim();
}

// Helper: Parse transcript JSON with error recovery
function parseTranscript(transcriptRaw: string | null | undefined): any[] {
  if (!transcriptRaw) return [];
  try {
    const parsed = JSON.parse(transcriptRaw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (parseError) {
    console.error("Transcript parse error, resetting:", parseError);
    return [];
  }
}

interface ActionRequest {
  action: string;
  [key: string]: any;
}

// Helper: Build HTTP response with proper headers
function buildResponseHeaders(
  body: any,
  status: number,
  baseCorsHeaders: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...baseCorsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store, no-cache, must-revalidate, private",
      "Pragma": "no-cache",
      "Expires": "0",
    },
  });
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return buildResponseHeaders(
      { status: "ok" },
      200,
      baseCorsHeaders,
    );
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    );

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Rate limiting
    const { action, ...params } = (await req.json()) as ActionRequest;

    // FIX High: Implement per-action rate limits for granular protection
    const perActionLimits: Record<string, { maxRequests: number; windowMs: number }> = {
      "create-scenario": { maxRequests: 3, windowMs: 3600000 }, // 3/hour
      "start-session": { maxRequests: 5, windowMs: 3600000 }, // 5/hour (uses quota)
      "send-message": { maxRequests: 30, windowMs: 60000 }, // 30/min (frequent)
      "end-session": { maxRequests: 10, windowMs: 3600000 }, // 10/hour
      "get-scenarios": { maxRequests: 60, windowMs: 60000 }, // 60/min (read-only)
      "get-session-history": { maxRequests: 20, windowMs: 60000 }, // 20/min (read-only)
    };

    let rateLimitHeaders: Record<string, string> = {};
    const actionLimit = perActionLimits[action];
    if (actionLimit) {
      const actionRateLimitResult = await checkRateLimit(
        supabaseAdmin,
        user.id,
        `rehearsal:${action}`,
        actionLimit,
      );
      if (!actionRateLimitResult.allowed) {
        return new Response(
          JSON.stringify({
            error: "Rate limit exceeded for this action",
            retryAfter: actionRateLimitResult.retryAfter,
          }),
          {
            status: 429,
            headers: {
              ...baseCorsHeaders,
              ...getRateLimitHeaders(actionRateLimitResult),
              "Content-Type": "application/json",
            },
          },
        );
      }
      rateLimitHeaders = getRateLimitHeaders(actionRateLimitResult);
    }

    let response;
    switch (action) {
      case "create-scenario":
        response = await handleCreateScenario(
          params as CreateScenarioParams,
          user.id,
          supabaseUser,
        );
        break;
      case "start-session":
        response = await handleStartSession(
          params as StartSessionParams,
          user.id,
          supabaseUser,
          supabaseAdmin,
        );
        break;
      case "send-message":
        response = await handleSendMessage(
          req,
          params as SendMessageParams,
          user.id,
          supabaseUser,
          supabaseAdmin,
        );
        break;
      case "end-session":
        response = await handleEndSession(
          params as EndSessionParams,
          user.id,
          supabaseUser,
          supabaseAdmin,
        );
        break;
      case "get-scenarios":
        response = await handleGetScenarios(params, user.id, supabaseUser);
        break;
      case "get-session-history":
        response = await handleGetSessionHistory(params, user.id, supabaseUser);
        break;
      default:
        return buildResponseHeaders(
          {
            error: "Invalid action",
            message: "Invalid action provided",
          },
          400,
          baseCorsHeaders,
        );
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        ...baseCorsHeaders,
        ...rateLimitHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (error: any) {
    console.error("Rehearsal function error:", error);
    return buildResponseHeaders(
      {
        error: "unexpected_error",
        message: sanitizeError(error?.message || "Internal server error"),
      },
      500,
      baseCorsHeaders,
    );
  }
});

// Handler: Create custom scenario
async function handleCreateScenario(
  params: CreateScenarioParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
): Promise<SuccessResponse | ErrorResponse> {
  const { title, description, personRole, situationType, keyPoints, desiredOutcome } = params;

  // Validation
  if (!title || !personRole || !situationType || !desiredOutcome) {
    return {
      error: "Missing required fields",
      message: "title, personRole, situationType, and desiredOutcome are required",
      sessionEnded: false,
    };
  }

  try {
    const { data: scenario, error: scenarioError } = await supabaseUser
      .from("custom_scenarios")
      .insert({
        user_id: userId,
        title,
        other_party_role: personRole,
        situation_summary: description,
        key_points: keyPoints || [],
        desired_outcome: desiredOutcome,
        situation_type: situationType as SituationType,
        is_public: false,
      })
      .select()
      .single();

    if (scenarioError) {
      return {
        error: "create_failed",
        message: sanitizeError(scenarioError),
        sessionEnded: false,
      };
    }

    return {
      success: true,
      data: { scenario },
      sessionEnded: false,
    };
  } catch (error) {
    return {
      error: "unexpected_error",
      message: sanitizeError(error),
      sessionEnded: false,
    };
  }
}

// Handler: Start rehearsal session
async function handleStartSession(
  params: StartSessionParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
): Promise<SuccessResponse | ErrorResponse | CrisisResponse> {
  const { scenarioId, customScenarioId } = params;

  if (!scenarioId && !customScenarioId) {
    return {
      error: "invalid_input",
      message: "Must provide either scenarioId or customScenarioId",
      sessionEnded: false,
    } as ErrorResponse;
  }

  // FIX High: Use atomic RPC call for session limit check (prevents TOCTOU race)
  const { data: sessionLimitResult, error: sessionLimitError } = await supabaseAdmin
    .rpc("check_active_session_limit", { p_user_id: userId })
    .single();

  if (sessionLimitError || !sessionLimitResult) {
    return {
      error: "too_many_active",
      message: "Unable to check session limit. Please try again.",
    };
  }

  const sessionLimit = sessionLimitResult as { can_create: boolean; active_count: number };
  if (!sessionLimit.can_create) {
    return {
      error: "too_many_active",
      message: `Maximum 3 active sessions allowed. You have ${sessionLimit.active_count} active sessions.`,
    };
  }

  // Fetch scenario FIRST (before quota check) to validate early
  // FIX P2: Use selective columns instead of SELECT * for performance
  let scenario;
  if (scenarioId) {
    const { data } = await supabaseUser
      .from("conversation_scenarios")
      .select(
        "id, title, is_premium, other_party_role, other_party_personality, situation_type, situation_context, situation_summary, key_points_to_convey, desired_outcome",
      )
      .eq("id", scenarioId)
      .single();
    scenario = data;
  } else {
    const { data } = await supabaseUser
      .from("custom_scenarios")
      .select(
        "id, title, user_id, other_party_role, other_party_personality, situation_type, situation_summary, key_points, desired_outcome",
      )
      .eq("id", customScenarioId)
      .eq("user_id", userId)
      .single();
    scenario = data;
  }

  if (!scenario) {
    return {
      error: "scenario_not_found",
      message: "The specified scenario does not exist or has been deleted",
      sessionEnded: false,
    } as ErrorResponse;
  }

  // Check if premium scenario and user has entitlement
  // Type narrowing: is_premium only exists on PrebuiltScenario (scenarioId case)
  if (scenarioId && "is_premium" in scenario && scenario.is_premium) {
    const { data: profile } = await supabaseUser
      .from("profiles")
      .select("subscription_tier")
      .eq("id", userId)
      .single();

    if (profile?.subscription_tier !== "premium") {
      return {
        error: "premium_required",
        message: "This scenario requires a premium subscription",
      };
    }
  }

  // FIX P0: Use atomic RPC call for quota check+increment (prevents race condition)
  const { data: quotaResult, error: quotaError } = await supabaseAdmin
    .rpc("check_and_increment_rehearsal_quota", { p_user_id: userId })
    .single();

  if (quotaError || !quotaResult) {
    return {
      error: "quota_check_failed",
      message: "Unable to verify your quota. Please try again.",
    };
  }

  const quota = quotaResult as { can_create: boolean; used: number; quota_limit: number };
  if (!quota.can_create) {
    return {
      error: "quota_exceeded",
      message: "Weekly rehearsal limit reached",
      upgradePrompt: true,
      quotaUsed: quota.used,
      quotaLimit: quota.quota_limit,
    };
  }

  // Create session (quota already atomically incremented)
  const { data: session, error: sessionError } = await supabaseUser
    .from("rehearsal_sessions")
    .insert({
      user_id: userId,
      scenario_id: scenarioId || null,
      custom_scenario_id: customScenarioId || null,
      status: "active",
      transcript: "",
    })
    .select("id, user_id, status, started_at, completed_at, transcript, total_exchanges, crisis_detected")
    .single();

  if (sessionError) {
    // Rollback quota on session creation failure
    try {
      const { error: rollbackError } = await supabaseAdmin.rpc("rollback_rehearsal_quota", {
        p_user_id: userId,
      });
      if (rollbackError) {
        console.error(
          "CRITICAL: Quota rollback failed after session creation failure. User may be overcharged.",
          { userId, rollbackError, originalError: sessionError }
        );
      }
    } catch (rollbackException) {
      console.error(
        "CRITICAL: Quota rollback exception after session creation failure. User may be overcharged.",
        { userId, rollbackException, originalError: sessionError }
      );
    }
    throw sessionError;
  }

  // Generate AI opening message with error handling and quota rollback
  const systemPrompt = ROLE_SIMULATION_PROMPT(scenario);
  let openingMessage: string;
  try {
    openingMessage = await callXAIWithRetry(
      [
        { role: "system", content: systemPrompt },
        { role: "user", content: "Start the conversation naturally." },
      ],
      3,
    );
  } catch (messageError) {
    // Rollback quota on opening message generation failure
    try {
      const { error: rollbackError } = await supabaseAdmin.rpc("rollback_rehearsal_quota", { p_user_id: userId });
      if (rollbackError) {
        console.error(
          "CRITICAL: Quota rollback failed after opening message failure. User may be overcharged.",
          { userId, rollbackError, originalError: messageError }
        );
      }
    } catch (rollbackException) {
      console.error(
        "CRITICAL: Quota rollback exception after opening message failure. User may be overcharged.",
        { userId, rollbackException, originalError: messageError }
      );
    }
    return {
      error: "ai_api_error",
      message: `Failed to generate opening message: ${sanitizeError(messageError)}`,
      sessionEnded: false,
    } as ErrorResponse;
  }

  return {
    success: true,
    data: {
      session: {
        id: session.id,
        scenarioTitle: scenario.title,
        keyPoints: scenario.key_points_to_convey || scenario.key_points || [],
        goal: scenario.desired_outcome,
      },
      openingMessage,
      systemContext: systemPrompt,
    },
    sessionEnded: false,
  } as SuccessResponse;
}

// Handler: Send message in rehearsal
async function handleSendMessage(
  req: Request,
  params: SendMessageParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
): Promise<ErrorResponse | SuccessResponse<SendMessageData> | CrisisResponse> {
  const { sessionId, message } = params;

  if (!sessionId || !message) {
    return {
      error: "invalid_input",
      message: "sessionId and message are required",
      sessionEnded: false,
    } as ErrorResponse;
  }

  if (message.length > MAX_MESSAGE_LENGTH) {
    return {
      error: "message_too_long",
      message: `Message must be ${MAX_MESSAGE_LENGTH} characters or less`,
      sessionEnded: false,
    } as ErrorResponse;
  }

  // Get session and scenario with selective columns (no SELECT *)
  const { data: sessionBase, error: sessionError } = await supabaseUser
    .from("rehearsal_sessions")
    .select("id, user_id, status, transcript, total_exchanges, started_at, completed_at, crisis_detected, scenario_id, custom_scenario_id")
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (sessionError || !sessionBase) {
    return {
      error: "session_error",
      message: "Unable to retrieve session. Please try again.",
      sessionEnded: false,
    } as ErrorResponse;
  }

  if (sessionBase.status !== "active") {
    return {
      error: "session_inactive",
      message: "This session is no longer active",
      sessionEnded: true,
    } as ErrorResponse;
  }

  // FIX CA1: Optimize query to fetch only needed scenario table (not both)
  // Check which scenario type is used, fetch only that table
  let scenario: ScenarioUnion | null = null;
  
  if (sessionBase.scenario_id) {
    // Fetch prebuilt scenario
    const { data: scenarios } = await supabaseUser
      .from("conversation_scenarios")
      .select("id, title, other_party_role, other_party_personality, situation_type, situation_context, key_points_to_convey, desired_outcome, is_premium")
      .eq("id", sessionBase.scenario_id)
      .single();
    scenario = scenarios as unknown as ScenarioUnion;
  } else if (sessionBase.custom_scenario_id) {
    // Fetch custom scenario
    const { data: scenarios } = await supabaseUser
      .from("custom_scenarios")
      .select("id, title, other_party_role, other_party_personality, situation_type, situation_summary, key_points, desired_outcome")
      .eq("id", sessionBase.custom_scenario_id)
      .eq("user_id", userId)
      .single();
    scenario = scenarios as unknown as ScenarioUnion;
  }

  if (!scenario) {
    return {
      error: "scenario_deleted",
      message: "The scenario for this session has been deleted",
      sessionEnded: true,
    } as ErrorResponse;
  }

  // Rebuild session object with fetched scenario
  const session = {
    ...sessionBase,
    scenario,
  };

  // MOVE CRISIS DETECTION HERE - BEFORE ALL OTHER CHECKS (line 577)
  // Crisis is safety-critical and must be detected on ANY message, regardless of quota
  const crisisDetected = await detectCrisis(message);
  
  if (crisisDetected) {
    // Log crisis event (fire-and-forget) - pass all required parameters
    const crisisResult = await logCrisisEvent(
      supabaseAdmin,
      userId,
      message,
      sessionId,
      "other" as SituationType,
    );
    
    // Return crisis response immediately - this overrides all other logic
    return {
      crisis: true,
      message: CRISIS_RESPONSE,
      resources: getCrisisResources(),
      sessionEnded: true,
    } as CrisisResponse;
  }

  // NOW check exchange limit (after crisis safety check)
  const transcript = session.transcript || [];
  const subscriptionTier = await getProfileSubscriptionTier(supabaseUser, userId);
  
  // Parse transcript to check actual exchange count (not string length)
  const transcriptArray = parseTranscript(session.transcript);
  
  // Free tier allows exactly 10 exchanges (20 entries: user + AI response each)
  // Block when trying to exceed limit: transcriptArray.length >= 21
  if (subscriptionTier !== "premium" && transcriptArray.length >= FREE_TIER_EXCHANGES_LIMIT * 2) {
    return {
      error: "exchange_limit",
      message: `Free tier limit of ${FREE_TIER_EXCHANGES_LIMIT} exchanges reached`,
      upgradePrompt: true,
    } as ErrorResponse;
  }

  // FIX P0: Sanitize user message to prevent prompt injection
  const sanitizedMessage = sanitizeForPrompt(message);
  
  // Generate system prompt from scenario
  const systemPrompt = ROLE_SIMULATION_PROMPT(session.scenario);

  // Enforce max exchanges to prevent DoS via transcript bloat
  // Use >= to block when at or exceeding limit (for free tier only, checked above)
  // Allows exactly 10 exchanges (20 entries), blocks on 11th exchange
  if (transcriptArray.length >= FREE_TIER_EXCHANGES_LIMIT * 2) {
    return {
      error: sanitizeError("Session exchange limit reached"),
      message: "This rehearsal session has reached its maximum exchanges",
      sessionEnded: true,
    } as ErrorResponse;
  }

  transcriptArray.push({
    role: "user",
    content: sanitizedMessage,
    timestamp: new Date().toISOString(),
  });

  // Get AI response with retry logic
  const conversationHistory = [
    { role: "system", content: systemPrompt },
    ...transcriptArray
      .slice(-10)
      .map((t: any) => ({ role: t.role, content: t.content })),
  ];

  const aiResponse = await callXAIWithRetry(conversationHistory, 3);

  // Validate subscription status mid-session before generating AI response
  const isPremium = "is_premium" in scenario && scenario.is_premium;
  if (isPremium && subscriptionTier !== "premium") {
    throw new Error("Subscription expired during session. Please renew.");
  }

  transcriptArray.push({
    role: "assistant",
    content: aiResponse,
    timestamp: new Date().toISOString(),
  });

  // Generate feedback asynchronously (don't block response)
  const feedbackPromise = generateFeedback(message, scenario)
    .then((feedback) =>
      supabaseAdmin.from("rehearsal_feedback").insert({
        session_id: sessionId,
        feedback_type: "per_message",
        tone: feedback.tone,
        clarity_score: feedback.clarity,
        empathy_score: feedback.empathy,
        assertiveness_score: feedback.assertiveness,
        strengths: [feedback.strength],
        improvements: [feedback.improvement],
      }),
    )
    .catch((error) => {
      console.error("Feedback generation failed:", error);
      // Continue - don't block user response
    });

  // Don't await feedback - return to user immediately (void marks intentional fire-and-forget)
  void feedbackPromise;

  // Use pattern-based fallback for immediate response (no AI cost)
  const patternFeedback = analyzeWithPatterns(message);

  // FIX P0: Add error handling for session update (prevent data inconsistency)
  // FIX P0: Use atomic RPC call for session update (prevents race condition from concurrent messages)
  // FIX P1: Calculate total exchanges correctly: each exchange = 2 entries (user + AI response)
  const totalExchanges = Math.floor(transcriptArray.length / 2);
  const { data: updateResult, error: updateError } = await supabaseUser
    .rpc("update_session_transcript_atomic", {
      p_session_id: sessionId,
      p_user_id: userId,
      p_transcript_json: JSON.stringify(transcriptArray),
      p_total_exchanges: totalExchanges,
    })
    .single();

  const result = updateResult as RPCSuccessResult;
  if (updateError || !result?.success) {
    console.error("Session transcript update failed:", updateError || result?.error_message);
    return {
      error: "transcript_update_failed",
      message: "Failed to save conversation. Please try again.",
      sessionEnded: false,
    } as ErrorResponse;
  }

  return {
    success: true,
    data: {
      aiResponse,
      feedback: {
        style: patternFeedback.tone,
        suggestions: patternFeedback.improvement ? [patternFeedback.improvement] : [],
        encouragement: patternFeedback.strength || "Good effort!",
      },
      exchangeCount: totalExchanges,
    },
    sessionEnded: false,
  } as SuccessResponse<SendMessageData>;
}

// Handler: End session with summary
async function handleEndSession(
  params: EndSessionParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
): Promise<SuccessResponse | ErrorResponse> {
  const { sessionId, confidenceRating, notes } = params;

  if (!sessionId) {
    return {
      error: "invalid_input",
      message: "sessionId is required",
      sessionEnded: false,
    } as ErrorResponse;
  }

  // FIX P0: Add bounds validation on confidenceRating (1-10 scale)
  const validatedConfidenceRating = confidenceRating
    ? Math.min(Math.max(confidenceRating, 1), 10)
    : undefined;

  // FIX P1: Specify columns instead of SELECT * (performance optimization)
  const { data: session } = await supabaseUser
    .from("rehearsal_sessions")
    .select("id, user_id, status, started_at, total_exchanges, transcript")
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (!session) {
    return {
      error: "session_not_found",
      message: "Session does not exist or has already ended",
      sessionEnded: true,
    } as ErrorResponse;
  }

  // Calculate duration
  const startedAt = new Date(session.started_at);
  const completedAt = new Date();
  const durationSeconds = Math.floor(
    (completedAt.getTime() - startedAt.getTime()) / 1000,
  );

  // Get feedback summary
  // FIX P1: Specify columns instead of SELECT * (performance optimization)
  const { data: feedbacks } = await supabaseAdmin
    .from("rehearsal_feedback")
    .select("id, clarity_score, empathy_score, assertiveness_score, strengths, improvements")
    .eq("session_id", sessionId);

  // FIX P0: Guard against undefined feedbacks and NaN in calculations
  const feedbackCount = feedbacks?.length || 0;
  const avgClarity = feedbackCount > 0
    ? feedbacks!.reduce((sum, f) => sum + (f.clarity_score || 0), 0) / feedbackCount
    : 0;
  const avgEmpathy = feedbackCount > 0
    ? feedbacks!.reduce((sum, f) => sum + (f.empathy_score || 0), 0) / feedbackCount
    : 0;
  const avgAssertiveness = feedbackCount > 0
    ? feedbacks!.reduce((sum, f) => sum + (f.assertiveness_score || 0), 0) / feedbackCount
    : 0;

  const allStrengths = feedbacks?.flatMap((f) => f.strengths || []) || [];
  const allImprovements = feedbacks?.flatMap((f) => f.improvements || []) || [];

  // Update session
  // FIX P0: Use atomic RPC to prevent session finalization race conditions
  const feedbackSummary = JSON.stringify({
    avgClarity: Number(avgClarity.toFixed(1)),
    avgEmpathy: Number(avgEmpathy.toFixed(1)),
    avgAssertiveness: Number(avgAssertiveness.toFixed(1)),
    strengths: allStrengths.slice(0, 3),
    improvements: allImprovements.slice(0, 2),
  });

  const { data: endSessionResult, error: endSessionError } = await supabaseUser
    .rpc("end_session_atomic", {
      p_session_id: sessionId,
      p_user_id: userId,
      p_status: "completed",
      p_confidence_rating: validatedConfidenceRating,
      p_notes: notes || null,
      p_feedback_summary: feedbackSummary,
      p_communication_style: null,
    })
    .single();

  const result = endSessionResult as RPCSuccessResult;
  if (endSessionError || !result?.success) {
    throw new Error(result?.error_message || endSessionError?.message || "Failed to complete session");
  }

  if (result?.error_message) {
    return {
      error: "session_end_failed",
      message: "Failed to end session. Please try again.",
      sessionEnded: false,
    } as ErrorResponse;
  }

  return {
    success: true,
    data: {
      summary: {
        duration: durationSeconds,
        exchangesCount: session.total_exchanges,
        avgScores: {
          clarity: Number(avgClarity.toFixed(1)),
          empathy: Number(avgEmpathy.toFixed(1)),
          assertiveness: Number(avgAssertiveness.toFixed(1)),
        },
        strengths: allStrengths.slice(0, 3),
        growthAreas: allImprovements.slice(0, 2),
      },
    },
    sessionEnded: true,
  } as SuccessResponse;
}

// Handler: Get scenarios
async function handleGetScenarios(
  params: any,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
): Promise<SuccessResponse<{ prebuilt: any[]; custom: any[] }>> {
  const { category, includeCustom } = params;

  // FIX P2: Use selective columns instead of SELECT * for performance
  let query = supabaseUser
    .from("conversation_scenarios")
    .select(
      "id, title, category, description, is_premium, other_party_role, situation_type, difficulty_level, estimated_minutes",
    )
    .eq("is_active", true);

  if (category) {
    query = query.eq("category", category);
  }

  const { data: prebuilt } = await query.order("title");

  let custom: any[] = [];
  if (includeCustom) {
    const { data } = await supabaseUser
      .from("custom_scenarios")
      .select(
        "id, title, user_id, other_party_role, situation_type, situation_summary, key_points, desired_outcome, created_at",
      )
      .eq("user_id", userId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false });
    custom = data || [];
  }

  return {
    success: true,
    data: { prebuilt: prebuilt || [], custom },
  } as SuccessResponse<{ prebuilt: any[]; custom: any[] }>;
}

// Handler: Get session history
async function handleGetSessionHistory(
  params: any,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
): Promise<SuccessResponse<{ sessions: any[] }> | ErrorResponse> {
  // FIX P0: Add bounds validation to prevent DoS via unbounded queries
  const rawLimit = params.limit || 20;
  const limit = Math.min(Math.max(rawLimit, 1), 100); // Clamp between 1 and 100

  // FIX P2: Use selective columns instead of SELECT * for performance
  const { data: sessions, error } = await supabaseUser
    .from("rehearsal_sessions")
    .select(
      "id, status, started_at, completed_at, total_exchanges, confidence_rating, conversation_scenarios(title), custom_scenarios(title)",
    )
    .eq("user_id", userId)
    .order("started_at", { ascending: false })
    .limit(limit);

  if (error) {
    console.error("Session history query failed:", error);
    return {
      error: "session_history_failed",
      message: "Failed to load session history. Please try again.",
      sessionEnded: false,
    } as ErrorResponse;
  }

  return {
    success: true,
    data: { sessions: sessions || [] },
    sessionEnded: false,
  } as SuccessResponse<{ sessions: any[] }>;
}

// Utility: Call xAI API with timeout
async function callXAI(messages: any[], timeoutMs = 30000): Promise<string> {
  const controller = new AbortController();
  const signal = controller.signal;

  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(XAI_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`,
      },
      body: JSON.stringify({
        model: "grok-2-latest",
        messages,
        temperature: 0.7,
        max_tokens: 300,
      }),
      signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`xAI API error: ${response.statusText}`);
    }

    const data = await response.json();
    const rawContent = data.choices[0]?.message?.content || "I'm processing that...";
    
    // FIX P0: Sanitize AI response to prevent XSS/prompt injection
    return sanitizeAIResponse(rawContent);
  } catch (error: any) {
    clearTimeout(timeoutId);
    if (error.name === "AbortError") {
      throw new Error("xAI API request timed out");
    }
    throw error;
  }
}

// Utility: Call xAI API with retry logic and timeout
async function callXAIWithRetry(
  messages: any[],
  maxRetries: number,
  baseDelayMs = 1000,
  timeoutMs = 30000,
): Promise<string> {
  let retries = 0;

  while (retries < maxRetries) {
    try {
      return await callXAI(messages, timeoutMs);
    } catch (error: any) {
      retries++;
      if (retries >= maxRetries) {
        throw error;
      }
      console.warn(`xAI API retry ${retries}/${maxRetries}:`, error);
      await new Promise((resolve) => setTimeout(resolve, baseDelayMs * Math.pow(2, retries - 1)));
    }
  }

  // This should not be reached due to throw above
  throw new Error("xAI API request failed");
}

// Utility: Generate feedback using AI
async function generateFeedback(message: string, scenario: any) {
  const contextDesc = `${scenario.title}: ${scenario.situation_context || scenario.situation_summary}`;
  const sanitizedMessage = sanitizeForPrompt(message);
  const prompt = FEEDBACK_PROMPT(sanitizedMessage, contextDesc);

  const response = await callXAIWithRetry([
    {
      role: "system",
      content: "You are a communication coach analyzing conversation practice.",
    },
    { role: "user", content: prompt },
  ], 2, 1000, 15000);

  try {
    // Parse AI response as JSON
    const feedback = JSON.parse(response);
    return feedback;
  } catch {
    // Fallback to pattern matching
    return analyzeWithPatterns(message);
  }
}

// Utility: Pattern-based feedback fallback
function analyzeWithPatterns(message: string) {
  // Simple keyword-based analysis
  const lower = message.toLowerCase();

  let tone = "assertive";
  if (
    lower.includes("maybe") ||
    lower.includes("sort of") ||
    lower.includes("i guess")
  ) {
    tone = "passive";
  } else if (lower.includes("you always") || lower.includes("you never")) {
    tone = "aggressive";
  } else if (lower.includes("we could") || lower.includes("let's")) {
    tone = "collaborative";
  } else if (lower.includes("i understand") || lower.includes("i hear")) {
    tone = "empathetic";
  }

  return {
    tone,
    clarity: 7.0,
    empathy: 7.0,
    assertiveness: 7.0,
    strength: "Clear communication",
    improvement: "Consider adding more specific examples",
  };
}

interface CrisisResource {
  name: string;
  phone?: string;
  sms?: string;
  available: string;
}

// RESPONSE TYPES - Unified format for all API responses
interface ErrorResponse {
  error: string;
  message: string;
  sessionEnded?: boolean;
  upgradePrompt?: boolean;
  quotaUsed?: number;
  quotaLimit?: number;
}

interface SuccessResponse<T = Record<string, unknown>> {
  success: true;
  data: T;
  sessionEnded?: boolean;
}

interface CrisisResponse {
  crisis: true;
  message: string;
  resources: CrisisResource[];
  sessionEnded?: boolean;
}

// RPC Return Types
interface RPCSuccessResult {
  success: boolean;
  error_message?: string;
}

// Utility: Get crisis resources
function getCrisisResources(): CrisisResource[] {
  return [
    {
      name: "National Suicide Prevention Lifeline",
      phone: "988",
      available: "24/7",
    },
    {
      name: "Crisis Text Line",
      sms: "Text HOME to 741741",
      available: "24/7",
    },
  ];
}

// Sanitize user input before using in AI prompts to prevent prompt injection
function sanitizeForPrompt(input: string): string {
  const MAX_LENGTH = 1000;
  return input
    .replace(/[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]/g, "") // Remove control chars except \t, \n, \r
    .replace(/\{system\}/gi, "[system]") // Escape system markers
    .replace(/\{assistant\}/gi, "[assistant]") // Escape assistant markers
    .replace(/\{user\}/gi, "[user]") // Escape user markers
    .replace(/\[(INST|\/INST)\]/gi, "[$1]") // Escape LLM instruction markers
    .replace(/<\|?(im_start|im_end)\|?>/gi, "[$1]") // Escape xAI tokens
    .replace(/<\/?s>/gi, "[s]") // Escape sentence markers
    .normalize("NFKC") // Normalize unicode to prevent homoglyph attacks
    .slice(0, MAX_LENGTH); // Enforce length limit
}

// SANITIZATION UTILITIES (prevent error leakage)
function sanitizeError(error: unknown): string {
  const errorMsg = String(error || 'Unknown error');
  
  // Never leak database details, SQL, or internal paths to client
  if (errorMsg.includes('UNIQUE') || errorMsg.includes('duplicate')) {
    return 'This resource already exists';
  }
  if (errorMsg.includes('foreign key') || errorMsg.includes('constraint')) {
    return 'Invalid reference to required data';
  }
  if (errorMsg.includes('column') || errorMsg.includes('table') || errorMsg.includes('schema')) {
    return 'Internal validation failed';
  }
  if (errorMsg.includes('timeout') || errorMsg.includes('connection')) {
    return 'Service temporarily unavailable';
  }
  // Default safe message
  return 'Operation failed';
}

// FIX P1: Extract duplicated crisis logging into helper function (DRY principle)
// Used in both createScenario and handleSendMessage to avoid duplication
// CRITICAL: Only logs matched keyword, NOT raw user content (GDPR Art. 32 - data minimization)
async function logCrisisEvent(
  supabaseAdmin: UntypedSupabaseClient,
  userId: string,
  content: string,
  sessionId: string,
  situationType: SituationType,
): Promise<{ success: boolean; error?: string }> {
  try {
    const matchedKeyword = getMatchedCrisisKeyword(content);
    // Only store matched keyword + metadata, NOT raw user content (prevents unencrypted PII exposure)
    const { error: crisisError } = await supabaseAdmin
      .from("crisis_events")
      .insert({
        user_id: userId,
        session_id: sessionId,
        detected_at: new Date().toISOString(),
        matched_keyword: matchedKeyword || "unknown", // Store only the matched keyword, not full content
      });

    if (crisisError) {
      // Don't let crisis logging failure block the response - log and continue
      console.error("Crisis event logging failed:", crisisError);
    }

    return { success: true };
  } catch (crisisLogError) {
    console.error("Crisis event insertion error:", crisisLogError);
    return { success: false, error: String(crisisLogError) };
  }
}

// FIX P1: Extract duplicated profile query into helper function
// Subscription tier check is repeated in multiple handlers
async function getProfileSubscriptionTier(
  supabaseUser: UntypedSupabaseClient,
  userId: string,
): Promise<string | undefined> {
  const { data: profile } = await supabaseUser
    .from("profiles")
    .select("subscription_tier")
    .eq("id", userId)
    .single();

  return profile?.subscription_tier;
}

// Add response data types for handlers
interface SendMessageData {
  aiResponse: string;
  feedback: any;
  exchangeCount: number;
}

interface StartSessionData {
  session: any;
  openingMessage: string;
  systemContext: string;
}

interface CreateScenarioData {
  scenario: any;
  scenarioId: string;
}

interface EndSessionData {
  summary: string;
  totalExchanges: number;
  completedAt: string;
}

// Top-level error handler - sanitize all errors before sending to client
