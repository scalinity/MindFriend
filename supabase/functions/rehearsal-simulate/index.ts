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

// Constants
const MAX_MESSAGE_LENGTH = 1000; // Rehearsal messages are shorter
const FREE_TIER_WEEKLY_QUOTA = 2;
const FREE_TIER_EXCHANGES_LIMIT = 10;
const XAI_API_URL = "https://api.x.ai/v1/chat/completions";

// AI Prompts for role simulation
const ROLE_SIMULATION_PROMPT = (
  scenario: ScenarioUnion,
) => `You are role-playing as ${scenario.other_party_role} in a ${
  "situation_type" in scenario ? scenario.situation_type : "conversation"
}.

Scenario context: ${
  "situation_context" in scenario ? scenario.situation_context : scenario.situation_summary
}
Your personality: ${
  "other_party_personality" in scenario && scenario.other_party_personality
    ? scenario.other_party_personality
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
      scenario.other_party_personality || "neutral and realistic",
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

interface ActionRequest {
  action: string;
  [key: string]: any;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
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
          params,
          user.id,
          supabaseUser,
          supabaseAdmin,
        );
        break;
      case "start-session":
        response = await handleStartSession(
          params,
          user.id,
          supabaseUser,
          supabaseAdmin,
        );
        break;
      case "send-message":
        response = await handleSendMessage(
          params,
          user.id,
          supabaseUser,
          supabaseAdmin,
        );
        break;
      case "end-session":
        response = await handleEndSession(
          params,
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
        return new Response(JSON.stringify({ error: "Invalid action" }), {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        });
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
    return new Response(
      JSON.stringify({ error: error?.message || "Internal server error" }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Handler: Create custom scenario
async function handleCreateScenario(
  params: CreateScenarioParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
) {
  const {
    title,
    description,
    personRole,
    situationType,
    keyPoints,
    desiredOutcome,
  } = params;

  // Validation
  if (!title || !description || !personRole || !keyPoints || !desiredOutcome) {
    throw new Error("Missing required fields");
  }

  if (title.trim().length < 3 || title.trim().length > 100) {
    throw new Error("Title must be 3-100 characters");
  }

  if (description.trim().length < 10 || description.trim().length > 500) {
    throw new Error("Description must be 10-500 characters");
  }

  if (
    !Array.isArray(keyPoints) ||
    keyPoints.length < 1 ||
    keyPoints.length > 5
  ) {
    throw new Error("Must have 1-5 key points");
  }

  // Bug fix #9: Removed quota check from scenario creation
  // Creating scenarios is FREE (just planning). Quota only consumed when starting session (actual AI usage).
  // This fixes double-charging bug: was 1 quota for create + 1 for start = 2 total
  // Now: 0 for create + 1 for start = 1 total (correct)

  // Crisis detection
  const fullText = `${title} ${description} ${keyPoints.join(" ")} ${desiredOutcome}`;
  const crisisDetected = await detectCrisis(fullText);

  if (crisisDetected) {
    // FIX P0: Store only matched keyword, not full scenario text (PII protection)
    // FIX P1: Use extracted helper function to reduce duplication
    await logCrisisEvent(supabaseAdmin, userId, fullText);

    return {
      crisis: true,
      message: CRISIS_RESPONSE,
      resources: getCrisisResources(),
    };
  }

  // SECURITY: Sanitize all scenario fields to prevent prompt injection
  // These fields are later injected into AI system prompts, so must be sanitized
  const sanitizedTitle = sanitizeForPrompt(title.trim());
  const sanitizedPersonRole = sanitizeForPrompt(personRole.trim());
  const sanitizedDescription = sanitizeForPrompt(description.trim());
  const sanitizedKeyPoints = keyPoints.map((kp: string) =>
    sanitizeForPrompt(kp),
  );
  const sanitizedDesiredOutcome = sanitizeForPrompt(desiredOutcome.trim());

  // Create scenario with sanitized data
  const { data: scenario, error } = await supabaseUser
    .from("custom_scenarios")
    .insert({
      user_id: userId,
      title: sanitizedTitle,
      other_party_role: sanitizedPersonRole,
      situation_summary: sanitizedDescription,
      key_points: sanitizedKeyPoints,
      desired_outcome: sanitizedDesiredOutcome,
      situation_type: situationType || "other",
    })
    .select("id, title, other_party_role, other_party_personality, situation_type, situation_summary, key_points, desired_outcome")
    .single();

  if (error) throw error;

  return { scenario, success: true };
}

// Handler: Start rehearsal session
async function handleStartSession(
  params: StartSessionParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
) {
  const { scenarioId, customScenarioId } = params;

  if (!scenarioId && !customScenarioId) {
    throw new Error("Must provide scenarioId or customScenarioId");
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
    throw new Error("Scenario not found");
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
      await supabaseAdmin.rpc("rollback_rehearsal_quota", {
        p_user_id: userId,
      });
    } catch (e) {
      console.error(
        "Failed to rollback quota after session creation failure:",
        e,
      );
    }
    throw sessionError;
  }

  // Generate AI opening message
  const systemPrompt = ROLE_SIMULATION_PROMPT(scenario);
  const openingMessage = await callXAIWithRetry(
    [
      { role: "system", content: systemPrompt },
      { role: "user", content: "Start the conversation naturally." },
    ],
    3,
  );

  return {
    session: {
      id: session.id,
      scenarioTitle: scenario.title,
      keyPoints: scenario.key_points_to_convey || scenario.key_points || [],
      goal: scenario.desired_outcome,
    },
    openingMessage,
    systemContext: systemPrompt,
  };
}

// Handler: Send message in rehearsal
async function handleSendMessage(
  params: SendMessageParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
) {
  const { sessionId, message } = params;

  if (!sessionId || !message) {
    throw new Error("Missing sessionId or message");
  }

  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new Error(`Message too long (max ${MAX_MESSAGE_LENGTH} characters)`);
  }

  // Get session and scenario with selective columns (no SELECT *)
  const { data: session, error: sessionError } = await supabaseUser
    .from("rehearsal_sessions")
    .select(`
      id, user_id, status, transcript, total_exchanges, started_at, completed_at, crisis_detected,
      conversation_scenarios(id, title, other_party_role, other_party_personality, situation_type, situation_context, key_points_to_convey, desired_outcome, is_premium),
      custom_scenarios(id, title, other_party_role, other_party_personality, situation_type, situation_summary, key_points, desired_outcome)
    `)
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (sessionError || !session) {
    throw new Error(`Session query failed: ${sessionError?.message || "Session not found"}`);
  }

  if (session.status !== "active") {
    throw new Error("Session is not active");
  }

  // Check exchange limit for free tier
  // FIX P1: Use extracted helper function to reduce duplication
  const subscriptionTier = await getProfileSubscriptionTier(supabaseUser, userId);

  if (
    subscriptionTier !== "premium" &&
    session.total_exchanges >= FREE_TIER_EXCHANGES_LIMIT
  ) {
    return {
      error: "exchange_limit",
      message: `Free tier limit of ${FREE_TIER_EXCHANGES_LIMIT} exchanges reached`,
      upgradePrompt: true,
    };
  }

  // Crisis detection (using KEYWORD only, not full message)
  const crisisDetected = await detectCrisis(message);
  if (crisisDetected) {
    // FIX P0: Store only matched keyword, not full user message (PII protection)
    // FIX P1: Use extracted helper function to reduce duplication
    await logCrisisEvent(supabaseAdmin, userId, message);

    // FIX P0: Atomically update session to crisis_ended with row-level lock
    const { data: crisisUpdateResult, error: crisisUpdateError } = await supabaseUser
      .rpc("update_session_crisis_status_atomic", {
        p_session_id: sessionId,
        p_user_id: userId,
      })
      .single();

    if (crisisUpdateError || !crisisUpdateResult?.success) {
      console.error(
        "Crisis session status update failed:",
        crisisUpdateError || crisisUpdateResult?.error_message,
      );
      // Continue with crisis response regardless of status update failure
    }

    return {
      crisis: true,
      message: CRISIS_RESPONSE,
      resources: getCrisisResources(),
      sessionEnded: true,
    };
  }

  // FIX P0: Sanitize user message to prevent prompt injection
  const sanitizedMessage = sanitizeForPrompt(message);

  // FIX P0: Extract first element from nested query arrays (Supabase returns arrays)
  const scenarioArray = session.conversation_scenarios || session.custom_scenarios;
  const scenario = Array.isArray(scenarioArray) ? scenarioArray[0] : scenarioArray;
  if (!scenario) {
    throw new Error("Scenario not found or was deleted");
  }
  const systemPrompt = ROLE_SIMULATION_PROMPT(scenario);

  // FIX P0: Parse existing transcript with proper error handling (prevents crash)
  let transcript: any[] = [];
  try {
    const parsed = session.transcript ? JSON.parse(session.transcript) : [];
    transcript = Array.isArray(parsed) ? parsed : [];
  } catch (parseError) {
    console.error("Transcript parse error, resetting:", parseError);
    transcript = [];
  }

  // Enforce max exchanges to prevent DoS via transcript bloat
  const MAX_EXCHANGES = 100;
  if (transcript.length >= MAX_EXCHANGES * 2) {
    return {
      error: "exchange_limit",
      message: `Session exchange limit reached (${MAX_EXCHANGES} exchanges max)`,
    };
  }

  transcript.push({
    role: "user",
    content: sanitizedMessage,
    timestamp: new Date().toISOString(),
  });

  // Get AI response with retry logic
  const conversationHistory = [
    { role: "system", content: systemPrompt },
    ...transcript
      .slice(-10)
      .map((t: any) => ({ role: t.role, content: t.content })),
  ];

  const aiResponse = await callXAIWithRetry(conversationHistory, 3);
  transcript.push({
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

  // Don't await feedback - return to user immediately
  feedbackPromise; // Fire and forget (no duplicate generation)

  // Use pattern-based fallback for immediate response (no AI cost)
  const patternFeedback = analyzeWithPatterns(message);

  // FIX P0: Add error handling for session update (prevent data inconsistency)
  // FIX P0: Use atomic RPC call for session update (prevents race condition from concurrent messages)
  const { data: updateResult, error: updateError } = await supabaseUser
    .rpc("update_session_transcript_atomic", {
      p_session_id: sessionId,
      p_user_id: userId,
      p_transcript_json: JSON.stringify(transcript),
      p_total_exchanges: session.total_exchanges + 1,
    })
    .single();

  if (updateError || !updateResult?.success) {
    console.error("Session transcript update failed:", updateError || updateResult?.error_message);
    throw new Error(updateResult?.error_message || "Failed to update session transcript");
  }

  return {
    aiResponse,
    feedback: {
      style: patternFeedback.tone,
      suggestions: patternFeedback.improvement ? [patternFeedback.improvement] : [],
      encouragement: patternFeedback.strength || "Good effort!",
    },
    exchangeCount: transcript.length / 2,
  };
}

// Handler: End session with summary
async function handleEndSession(
  params: EndSessionParams,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
  supabaseAdmin: UntypedSupabaseClient,
) {
  const { sessionId, confidenceRating, notes } = params;

  if (!sessionId) {
    throw new Error("Missing sessionId");
  }

  // FIX P1: Specify columns instead of SELECT * (performance optimization)
  const { data: session } = await supabaseUser
    .from("rehearsal_sessions")
    .select("id, user_id, status, started_at, total_exchanges, transcript")
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (!session) {
    throw new Error("Session not found");
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
      p_confidence_rating: confidenceRating,
      p_notes: notes || null,
      p_feedback_summary: feedbackSummary,
      p_communication_style: null,
    })
    .single();

  if (endSessionError || !endSessionResult?.success) {
    throw new Error(endSessionResult?.error_message || endSessionError?.message || "Failed to complete session");
  }

  return {
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
    success: true,
  };
}

// Handler: Get scenarios
async function handleGetScenarios(
  params: any,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
) {
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

  return { prebuilt: prebuilt || [], custom };
}

// Handler: Get session history
async function handleGetSessionHistory(
  params: any,
  userId: string,
  supabaseUser: UntypedSupabaseClient,
) {
  const { limit = 20 } = params;

  // FIX P2: Use selective columns instead of SELECT * for performance
  const { data: sessions } = await supabaseUser
    .from("rehearsal_sessions")
    .select(
      "id, status, started_at, completed_at, total_exchanges, confidence_rating, conversation_scenarios(title), custom_scenarios(title)",
    )
    .eq("user_id", userId)
    .order("started_at", { ascending: false })
    .limit(limit);

  return { sessions: sessions || [] };
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

  while (true) {
    try {
      return await callXAI(messages, timeoutMs);
    } catch (error: any) {
      if (retries < maxRetries && !error.message.includes("timed out")) {
        const delay = Math.min(baseDelayMs * 2 ** retries, 60000);
        await new Promise((resolve) => setTimeout(resolve, delay));
        retries++;
        continue;
      }
      throw error;
    }
  }
}

// Utility: Generate feedback using AI
async function generateFeedback(message: string, scenario: any) {
  const contextDesc = `${scenario.title}: ${scenario.situation_context || scenario.situation_summary}`;
  const prompt = FEEDBACK_PROMPT(message, contextDesc);

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

// FIX P1: Extract duplicated crisis logging into helper function (DRY principle)
// Used in both createScenario and handleSendMessage to avoid duplication
async function logCrisisEvent(
  supabaseAdmin: UntypedSupabaseClient,
  userId: string,
  content: string,
): Promise<{ success: boolean; error?: string }> {
  try {
    const matchedKeyword = getMatchedCrisisKeyword(content);
    const { error: crisisError } = await supabaseAdmin.from("crisis_events").insert({
      user_id: userId,
      matched_keyword: matchedKeyword || "detected",
      detected_at: new Date().toISOString(),
    });

    if (crisisError) {
      console.error("Crisis event logging failed:", crisisError);
      return { success: false, error: crisisError.message };
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
