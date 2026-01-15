// MindFriend Chat Edge Function
// Handles AI conversation with quota enforcement and crisis detection

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders, corsHeaders } from "../_shared/cors.ts";
import {
  detectCrisis,
  getMatchedCrisisKeyword,
  CRISIS_RESPONSE,
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
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client with service role for admin operations
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
            ...corsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    // Get origin for CORS
    const origin = req.headers.get("Origin");
    const responseHeaders = {
      ...getCorsHeaders(origin),
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

    const quotaData = quotaResult?.[0];
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

      // Save user message
      await supabaseAdmin.from("messages").insert({
        conversation_id: conversationId,
        role: "user",
        content: trimmedContent,
      });

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
          message: {
            id: crisisMessage?.id,
            role: "assistant",
            content: CRISIS_RESPONSE,
            createdAt: now.toISOString(),
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

    // Fetch relevant memories for context injection (ordered by confidence per spec)
    const { data: memories } = await supabaseAdmin
      .from("memory_fragments")
      .select("fragment_type, key, value, confidence")
      .eq("user_id", user.id)
      .or(`expires_at.is.null,expires_at.gt.${now.toISOString()}`)
      .order("confidence", { ascending: false })
      .limit(10);

    // Build memory context string for system prompt (format: key: value)
    let memoryContext = "";
    if (memories && memories.length > 0) {
      const grouped: Record<string, string[]> = {};
      for (const mem of memories) {
        if (!grouped[mem.fragment_type]) grouped[mem.fragment_type] = [];
        // Format as "key: value" for cleaner display
        grouped[mem.fragment_type].push(`${mem.key}: ${mem.value}`);
      }

      memoryContext = "\n\n## What you know about this user:\n";
      if (grouped.person)
        memoryContext += `- People in their life: ${grouped.person.join(", ")}\n`;
      if (grouped.fact)
        memoryContext += `- Facts about them: ${grouped.fact.join(", ")}\n`;
      if (grouped.preference)
        memoryContext += `- Their preferences: ${grouped.preference.join(", ")}\n`;
      if (grouped.event)
        memoryContext += `- Upcoming/recent events: ${grouped.event.join(", ")}\n`;
      memoryContext +=
        "\nUse this context naturally in conversation when relevant. Reference past events or details to show you remember and care.";
    }

    const enhancedSystemPrompt = SYSTEM_PROMPT + memoryContext;

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

    // Save user message first
    await supabaseAdmin.from("messages").insert({
      conversation_id: conversationId,
      role: "user",
      content: trimmedContent,
    });

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
    if (isFirstMessage) {
      try {
        const titleResponse = await fetch(XAI_API_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${xaiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "grok-3-mini-fast",
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
          if (generatedTitle && generatedTitle.length > 0) {
            conversationTitle = generatedTitle;
            await supabaseAdmin
              .from("conversations")
              .update({ title: generatedTitle })
              .eq("id", conversationId);
          }
        }
      } catch (titleError) {
        // Non-critical: log but don't fail the request
        console.error("Title generation failed:", titleError);
      }
    }

    // Note: Quota was already incremented atomically at the start of the function

    // Extract memories in background (non-blocking)
    extractMemories(
      supabaseAdmin,
      user.id,
      conversationId,
      trimmedContent,
      assistantContent,
      xaiKey,
    ).catch((err) => console.error("Memory extraction failed:", err));

    return new Response(
      JSON.stringify({
        message: {
          id: assistantMessage?.id,
          role: "assistant",
          content: assistantContent,
          createdAt: now.toISOString(),
          blocked: false,
        },
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
      { status: 500, headers: corsHeaders },
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
      // Remove potential prompt injection patterns
      .replace(/^(system|assistant|user):/gi, "[redacted]:")
      .replace(/\[INST\]/gi, "[redacted]")
      .replace(/<<SYS>>/gi, "[redacted]")
      .replace(/<\|.*?\|>/g, "[redacted]")
  );
}

// Memory extraction function - runs in background, non-blocking
async function extractMemories(
  supabaseAdmin: ReturnType<typeof createClient>,
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
        model: "grok-3-mini-fast",
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
