// MindFriend Chat Edge Function
// Handles AI conversation with quota enforcement and crisis detection

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { detectCrisis, CRISIS_RESPONSE } from "../_shared/crisis.ts";

const OPENAI_API_URL = "https://api.openai.com/v1/chat/completions";
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

    // Parse request body
    const { conversationId, content }: ChatRequest = await req.json();

    if (!conversationId || !content) {
      return new Response(
        JSON.stringify({ error: "Missing conversationId or content" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get user profile to check quota
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select(
        "subscription_tier, daily_ai_quota, daily_ai_used, quota_reset_at",
      )
      .eq("id", user.id)
      .single();

    if (profileError) {
      console.error("Profile error:", profileError);
      return new Response(JSON.stringify({ error: "User profile not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check if quota needs reset (new day)
    const now = new Date();
    const quotaResetAt = new Date(profile.quota_reset_at);
    let dailyAiUsed = profile.daily_ai_used;

    if (now.toDateString() !== quotaResetAt.toDateString()) {
      // Reset quota for new day
      dailyAiUsed = 0;
      await supabaseAdmin
        .from("profiles")
        .update({ daily_ai_used: 0, quota_reset_at: now.toISOString() })
        .eq("id", user.id);
    }

    // Check quota (premium users have unlimited, indicated by -1 or high quota)
    const isPremium = profile.subscription_tier === "premium";
    if (!isPremium && dailyAiUsed >= profile.daily_ai_quota) {
      return new Response(
        JSON.stringify({
          error: "AI_QUOTA_EXCEEDED",
          message:
            "You've reached your daily AI chat limit. Upgrade to Premium for unlimited chats!",
          quotaUsed: dailyAiUsed,
          quotaLimit: profile.daily_ai_quota,
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Crisis detection - SAFETY CRITICAL
    if (detectCrisis(content)) {
      // Log crisis event
      await supabaseAdmin.from("crisis_events").insert({
        user_id: user.id,
        conversation_id: conversationId,
        trigger_content: content.substring(0, 500), // Truncate for privacy
        detected_at: now.toISOString(),
      });

      // Save user message
      await supabaseAdmin.from("messages").insert({
        conversation_id: conversationId,
        role: "user",
        content: content,
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
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get conversation history for context
    const { data: messages } = await supabaseAdmin
      .from("messages")
      .select("role, content")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: true })
      .limit(20); // Last 20 messages for context

    // Build message history for OpenAI
    const messageHistory: Message[] = [
      { role: "system", content: SYSTEM_PROMPT },
      ...(messages || []).map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
      { role: "user", content: content },
    ];

    // Save user message first
    await supabaseAdmin.from("messages").insert({
      conversation_id: conversationId,
      role: "user",
      content: content,
    });

    // Call OpenAI
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      return new Response(JSON.stringify({ error: "OpenAI not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const openaiResponse = await fetch(OPENAI_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: messageHistory,
        max_tokens: 500,
        temperature: 0.7,
      }),
    });

    if (!openaiResponse.ok) {
      const errorText = await openaiResponse.text();
      console.error("OpenAI error:", errorText);
      return new Response(JSON.stringify({ error: "AI service unavailable" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const openaiData = await openaiResponse.json();
    const assistantContent =
      openaiData.choices?.[0]?.message?.content ||
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

    // Increment quota used
    await supabaseAdmin
      .from("profiles")
      .update({ daily_ai_used: dailyAiUsed + 1 })
      .eq("id", user.id);

    return new Response(
      JSON.stringify({
        message: {
          id: assistantMessage?.id,
          role: "assistant",
          content: assistantContent,
          createdAt: now.toISOString(),
          blocked: false,
        },
        quotaUsed: dailyAiUsed + 1,
        quotaLimit: isPremium ? -1 : profile.daily_ai_quota,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Chat function error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
