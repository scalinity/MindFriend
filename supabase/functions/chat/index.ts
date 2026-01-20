// MindFriend Chat Edge Function
// Handles AI conversation with quota enforcement and crisis detection

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

// Type alias for untyped Supabase client (no generated database types)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UntypedSupabaseClient = SupabaseClient<any, "public", any>;
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  CRISIS_RESPONSE,
  detectCrisis,
  getMatchedCrisisKeyword,
} from "../_shared/crisis.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

// Security constants
const MAX_MESSAGE_LENGTH = 4000; // ~1000 tokens
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const XAI_API_URL = "https://api.x.ai/v1/chat/completions";
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
}

interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}

serve(async (req) => {
  // Get origin first for consistent CORS handling
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
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
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    );

    // Initialize admin client for operations that need elevated privileges
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from the user-scoped client
    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      console.error(
        "Auth validation failed:",
        authError?.message || "No user returned",
        "Code:",
        authError?.code,
      );
      return new Response(
        JSON.stringify({
          error: "Invalid token",
          details:
            authError?.message ||
            "Session validation failed. Please sign out and sign back in.",
          code: authError?.code,
        }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting check (10 requests per minute)
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "chat",
    );

    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          message: "Please wait a moment before sending more messages.",
          retryAfter: rateLimitResult.retryAfter,
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

    const { conversationId, content } = requestBody;

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
    const { data: conversation, error: convError } = await supabaseAdmin
      .from("conversations")
      .select("id, user_id")
      .eq("id", conversationId)
      .single();

    if (convError || !conversation) {
      return new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
        headers: responseHeaders,
      });
    }

    if (conversation.user_id !== user.id) {
      // Log potential attack attempt (without PII)
      console.error("Unauthorized conversation access attempt", {
        attemptedConversationId: conversationId,
        userId: user.id,
      });
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: responseHeaders,
      });
    }

    // Get user profile to check subscription tier
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("subscription_tier")
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

    // Fetch user settings for privacy_mode and ai_tone
    const { data: userSettings } = await supabaseAdmin
      .from("user_settings")
      .select("privacy_mode, ai_tone")
      .eq("user_id", user.id)
      .maybeSingle();

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
    const isPremium = profile.subscription_tier === "premium";

    // Atomically check and increment quota (prevents race conditions)
    const { data: quotaResult, error: quotaError } = await supabaseAdmin.rpc(
      "check_and_increment_ai_quota",
      {
        p_user_id: user.id,
        p_is_premium: isPremium,
      },
    );

    if (quotaError) {
      console.error("Quota check failed:", quotaError.code);
      return new Response(
        JSON.stringify({ error: "Unable to process request" }),
        { status: 500, headers: responseHeaders },
      );
    }

    // Handle both TABLE (array) and JSON (object) return types
    const quotaData = Array.isArray(quotaResult)
      ? quotaResult?.[0]
      : quotaResult;
    if (!quotaData?.allowed) {
      return new Response(
        JSON.stringify({
          error: "AI_QUOTA_EXCEEDED",
          message:
            "You've reached your daily AI chat limit. Upgrade to Premium for unlimited chats!",
          quotaUsed: quotaData?.quota_used || 0,
          quotaLimit: quotaData?.quota_limit || 0,
        }),
        { status: 429, headers: responseHeaders },
      );
    }

    // Store quota info for response
    const quotaUsed = quotaData.quota_used;
    const quotaLimit = quotaData.quota_limit;

    // Crisis detection - SAFETY CRITICAL
    if (detectCrisis(trimmedContent)) {
      // Log crisis event WITHOUT storing user's actual content (PII protection)
      const matchedKeyword = getMatchedCrisisKeyword(trimmedContent);
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
            connections[0]?.profiles?.display_name || "A client";

          // Send notification to each connected therapist
          for (const connection of connections) {
            const therapistUserId = Array.isArray(connection.therapist_accounts)
              ? connection.therapist_accounts[0]?.user_id
              : connection.therapist_accounts?.user_id;

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

      // Save user message with full select to get all fields
      const { data: crisisUserMessage } = await supabaseAdmin
        .from("messages")
        .insert({
          conversation_id: conversationId,
          role: "user",
          content: trimmedContent,
        })
        .select()
        .single();

      // Save crisis response
      const { data: crisisMessage } = await supabaseAdmin
        .from("messages")
        .insert({
          conversation_id: conversationId,
          role: "assistant",
          content: CRISIS_RESPONSE,
        })
        .select()
        .single();

      // Update conversation timestamp
      await supabaseAdmin
        .from("conversations")
        .update({ updated_at: now.toISOString() })
        .eq("id", conversationId);

      return new Response(
        JSON.stringify({
          // EXE-007: Return full message objects for both user and assistant
          userMessage: {
            id: crisisUserMessage?.id,
            role: "user",
            content: trimmedContent,
            createdAt: crisisUserMessage?.created_at || now.toISOString(),
            blocked: false,
          },
          assistantMessage: {
            id: crisisMessage?.id,
            role: "assistant",
            content: CRISIS_RESPONSE,
            createdAt: crisisMessage?.created_at || now.toISOString(),
            blocked: true,
          },
          // Legacy field for backward compatibility
          message: {
            id: crisisMessage?.id,
            role: "assistant",
            content: CRISIS_RESPONSE,
            createdAt: crisisMessage?.created_at || now.toISOString(),
            blocked: true,
          },
          isCrisisResponse: true,
        }),
        { headers: responseHeaders },
      );
    }

    // Get conversation history for context
    const { data: messages } = await supabaseAdmin
      .from("messages")
      .select("role, content")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: true })
      .limit(20); // Last 20 messages for context

    // Fetch relevant memories for context injection ONLY if privacy mode is OFF
    let memoryContext = "";
    if (!privacyModeEnabled) {
      const { data: memories } = await supabaseAdmin
        .from("memory_fragments")
        .select("fragment_type, key, value, confidence")
        .eq("user_id", user.id)
        .or(`expires_at.is.null,expires_at.gt.${now.toISOString()}`)
        .order("confidence", { ascending: false })
        .limit(10);

      // Build memory context string for system prompt (format: key: value)
      if (memories && memories.length > 0) {
        const grouped: Record<string, string[]> = {};
        for (const mem of memories) {
          if (!grouped[mem.fragment_type]) grouped[mem.fragment_type] = [];
          // Format as "key: value" for cleaner display
          grouped[mem.fragment_type].push(`${mem.key}: ${mem.value}`);
        }

        memoryContext = "\n\n## What you know about this user:\n";
        if (grouped.person) {
          memoryContext += `- People in their life: ${grouped.person.join(
            ", ",
          )}\n`;
        }
        if (grouped.fact) {
          memoryContext += `- Facts about them: ${grouped.fact.join(", ")}\n`;
        }
        if (grouped.preference) {
          memoryContext += `- Their preferences: ${grouped.preference.join(
            ", ",
          )}\n`;
        }
        if (grouped.event) {
          memoryContext += `- Upcoming/recent events: ${grouped.event.join(
            ", ",
          )}\n`;
        }
        memoryContext +=
          "\nUse this context naturally in conversation when relevant. Reference past events or details to show you remember and care.";
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
      SYSTEM_PROMPT + toneInstruction + memoryContext + reengagementContext;

    // Sanitize user content to prevent prompt injection attacks
    // This removes role impersonation attempts and prompt manipulation patterns
    const sanitizedContent = sanitizeForPrompt(trimmedContent);

    // Build message history for AI
    const messageHistory: Message[] = [
      { role: "system", content: enhancedSystemPrompt },
      ...(messages || []).map((m) => ({
        role: m.role as "user" | "assistant",
        // Sanitize historical messages too for defense in depth
        content: m.role === "user" ? sanitizeForPrompt(m.content) : m.content,
      })),
      { role: "user", content: sanitizedContent },
    ];

    // Save user message first and capture all fields for response
    const { data: userMessage } = await supabaseAdmin
      .from("messages")
      .insert({
        conversation_id: conversationId,
        role: "user",
        content: trimmedContent,
      })
      .select()
      .single();

    // Call xAI (Grok)
    const xaiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiKey) {
      console.error("XAI_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "Service temporarily unavailable" }),
        { status: 503, headers: responseHeaders },
      );
    }

    const aiResponse = await fetch(XAI_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${xaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-4-1-fast-reasoning",
        messages: messageHistory,
        max_tokens: 500,
        temperature: 0.7,
      }),
    });

    if (!aiResponse.ok) {
      // Log error code only, not response body (may contain sensitive info)
      console.error("xAI API error:", aiResponse.status);
      return new Response(
        JSON.stringify({ error: "AI service temporarily unavailable" }),
        { status: 502, headers: responseHeaders },
      );
    }

    const aiData = await aiResponse.json();
    const assistantContent =
      aiData.choices?.[0]?.message?.content ||
      "I'm sorry, I couldn't generate a response. Please try again.";

    // Save assistant message
    const { data: assistantMessage } = await supabaseAdmin
      .from("messages")
      .insert({
        conversation_id: conversationId,
        role: "assistant",
        content: assistantContent,
      })
      .select()
      .single();

    // Update conversation timestamp
    await supabaseAdmin
      .from("conversations")
      .update({ updated_at: now.toISOString() })
      .eq("id", conversationId);

    // Auto-generate conversation title if this is the first message
    const isFirstMessage = !messages || messages.length === 0;
    let conversationTitle: string | null = null;
    console.log(
      `Title generation check: isFirstMessage=${isFirstMessage}, messagesCount=${messages?.length ?? 0}`,
    );

    if (isFirstMessage) {
      try {
        console.log("Generating conversation title...");
        const titleResponse = await fetch(XAI_API_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${xaiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "grok-4-1-fast-reasoning", // Same model as main chat - confirmed working
            messages: [
              {
                role: "system",
                content:
                  "Generate a very short title (3-5 words max) for this conversation based on the user's first message. Return only the title, no quotes or punctuation.",
              },
              { role: "user", content: trimmedContent },
            ],
            max_tokens: 20,
            temperature: 0.5,
          }),
        });

        if (titleResponse.ok) {
          const titleData = await titleResponse.json();
          const generatedTitle =
            titleData.choices?.[0]?.message?.content?.trim();
          console.log(`Generated title: "${generatedTitle}"`);
          if (generatedTitle && generatedTitle.length > 0) {
            conversationTitle = generatedTitle;
            const { error: updateError } = await supabaseAdmin
              .from("conversations")
              .update({ title: generatedTitle })
              .eq("id", conversationId);
            if (updateError) {
              console.error("Failed to save title:", updateError.message);
            } else {
              console.log(`Title saved to conversation ${conversationId}`);
            }
          }
        } else {
          // Log failed title generation for debugging
          const errorText = await titleResponse.text();
          console.error(
            "Title generation API error:",
            titleResponse.status,
            errorText,
          );
        }
      } catch (titleError) {
        // Non-critical: log but don't fail the request
        console.error("Title generation failed:", titleError);
      }
    }

    // Note: Quota was already incremented atomically at the start of the function

    // Extract memories in background ONLY if privacy mode is OFF
    if (!privacyModeEnabled) {
      extractMemories(
        supabaseAdmin,
        user.id,
        conversationId,
        trimmedContent,
        assistantContent,
        xaiKey,
      ).catch((err) => console.error("Memory extraction failed:", err));
    }

    return new Response(
      JSON.stringify({
        // EXE-007: Return full message objects for both user and assistant
        userMessage: {
          id: userMessage?.id,
          role: "user",
          content: trimmedContent,
          createdAt: userMessage?.created_at || now.toISOString(),
          blocked: false,
        },
        assistantMessage: {
          id: assistantMessage?.id,
          role: "assistant",
          content: assistantContent,
          createdAt: assistantMessage?.created_at || now.toISOString(),
          blocked: false,
        },
        // Legacy field for backward compatibility during transition
        message: {
          id: assistantMessage?.id,
          role: "assistant",
          content: assistantContent,
          createdAt: assistantMessage?.created_at || now.toISOString(),
          blocked: false,
        },
        userMessageId: userMessage?.id, // Legacy field for backward compatibility
        quotaUsed: quotaUsed,
        quotaLimit: quotaLimit,
        conversationTitle: conversationTitle,
      }),
      { headers: responseHeaders },
    );
  } catch (error) {
    // Generic error - don't leak internal details
    console.error(
      "Chat function error:",
      error instanceof Error ? error.message : "Unknown",
    );
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      { status: 500, headers: baseCorsHeaders },
    );
  }
});

// Sanitize user input to prevent prompt injection
function sanitizeForPrompt(input: string): string {
  // Limit length to prevent token stuffing
  const truncated = input.slice(0, 2000);
  // Escape characters that could be used for prompt manipulation
  return (
    truncated
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\n/g, " ")
      .replace(/\r/g, "")
      .replace(/\t/g, " ")
      // Remove potential prompt injection patterns - role impersonation
      .replace(/^(system|assistant|user):/gim, "[redacted]:")
      .replace(/\b(system|assistant|user)\s*:\s*/gi, "[redacted]: ")
      // Common LLM-specific delimiters and tokens
      .replace(/\[INST\]/gi, "[redacted]")
      .replace(/\[\/INST\]/gi, "[redacted]")
      .replace(/<<SYS>>/gi, "[redacted]")
      .replace(/<\|.*?\|>/g, "[redacted]")
      .replace(/\[\[.*?\]\]/g, (match) =>
        match.toLowerCase().includes("system") ||
        match.toLowerCase().includes("instruction")
          ? "[redacted]"
          : match,
      )
      // Instruction override attempts
      .replace(
        /ignore\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?)/gi,
        "[redacted]",
      )
      .replace(
        /forget\s+(everything|all|your)\s+(you('ve)?\s+)?(learned|know|were told)/gi,
        "[redacted]",
      )
      .replace(/disregard\s+(all\s+)?(previous|above|system)/gi, "[redacted]")
      .replace(/new\s+instructions?:\s*/gi, "[redacted]: ")
      .replace(/override\s+(system|instructions?|prompt)/gi, "[redacted]")
      // Jailbreak/DAN pattern indicators
      .replace(/\b(do\s+anything\s+now|DAN|jailbreak)\b/gi, "[redacted]")
      .replace(
        /pretend\s+(to\s+be|you\s+are)\s+(a\s+)?(different|evil|unrestricted)/gi,
        "[redacted]",
      )
      .replace(
        /you\s+are\s+now\s+(a\s+)?(different|evil|unrestricted|free)/gi,
        "[redacted]",
      )
      // Roleplay escape attempts
      .replace(/stop\s+being\s+(a\s+)?helpful/gi, "[redacted]")
      .replace(/exit\s+(character|roleplay|persona)/gi, "[redacted]")
      // Markdown/formatting abuse
      .replace(/```(system|instruction|prompt)/gi, "```[redacted]")
  );
}

// Memory extraction function - runs in background, non-blocking
async function extractMemories(
  supabaseAdmin: UntypedSupabaseClient,
  userId: string,
  conversationId: string,
  userMessage: string,
  _assistantMessage: string,
  xaiKey: string,
): Promise<void> {
  // Sanitize user input to prevent prompt injection
  const sanitizedMessage = sanitizeForPrompt(userMessage);

  const extractionPrompt = `Analyze this user message and extract any facts they revealed about themselves.
Return a JSON array of objects with "type", "key", and "value" fields.

Types:
- "person": Names of family members, friends, pets, coworkers
- "event": Upcoming events, plans, or recent experiences with dates if mentioned
- "preference": Likes, dislikes, communication preferences
- "fact": Job, location, hobbies, other personal facts

Format:
- key: short snake_case identifier (e.g., "dog_name", "partner_name", "work_presentation", "favorite_exercise")
- value: the actual information (e.g., "Max", "Sarah", "Friday at 2pm", "breathing")

Rules:
- Only extract clear, explicit information - don't infer or guess
- Keep key short (under 30 chars) and value concise (under 100 chars)
- If nothing new is shared, return empty array []
- Don't extract emotional states or temporary feelings

<user_message>
${sanitizedMessage}
</user_message>

Return ONLY valid JSON array, no explanation. Example: [{"type": "person", "key": "sister_name", "value": "Emma"}, {"type": "event", "key": "job_interview", "value": "Next Monday at 10am"}]`;

  try {
    const response = await fetch(XAI_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${xaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-4-1-fast-reasoning", // Same model as main chat - confirmed working
        messages: [
          {
            role: "system",
            content:
              "You extract structured personal facts from conversations. Return only valid JSON arrays.",
          },
          { role: "user", content: extractionPrompt },
        ],
        max_tokens: 500,
        temperature: 0.1,
      }),
    });

    if (!response.ok) {
      console.error("Memory extraction API error:", response.status);
      return;
    }

    const data = await response.json();
    const extracted = data.choices?.[0]?.message?.content;
    if (!extracted) return;

    // Parse JSON response
    let memories: Array<{ type: string; key: string; value: string }>;
    try {
      // Clean up response - sometimes models add markdown formatting
      const cleaned = extracted.replace(/```json\n?|\n?```/g, "").trim();
      memories = JSON.parse(cleaned);
    } catch {
      console.error("Memory extraction JSON parse failed:", extracted);
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
      }))
      .filter((m) => m.key.length > 0 && m.value.length > 0);

    if (candidates.length === 0) return;

    // Use upsert with the UNIQUE constraint (user_id, fragment_type, key)
    // This will update existing memories with same key instead of duplicating
    const upserts = candidates.map((m) => ({
      user_id: userId,
      fragment_type: m.type,
      key: m.key,
      value: m.value,
      confidence: 0.8, // Default confidence
      source_conversation_id: conversationId,
      extracted_at: now.toISOString(),
      updated_at: now.toISOString(),
      // Events expire in 7 days, others are permanent
      expires_at:
        m.type === "event"
          ? new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
          : null,
    }));

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
