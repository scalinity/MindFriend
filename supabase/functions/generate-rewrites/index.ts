import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { sanitizeForPrompt } from "../_shared/sanitize.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

interface GenerateRewritesRequest {
  conversationId: string;
  messageId: string;
  messageText: string;
  rewriteType: string;
  locale?: string;
}

interface RewriteOption {
  id: string;
  text: string;
  explanation: string;
}

// Crisis keywords for self-harm content detection
const CRISIS_PATTERNS = [
  /want.*(die|kill|hurt.*myself|end.*my.*life|not.*worth.*living)/i,
  /(suicid|self.?harm|self.?injur)/i,
  /hurting.*myself/i,
  /better.*(off|dead)/i,
  /(end|finish).*everything/i,
  /no.*reason.*to.*live/i,
  /kill.*(myself|me)/i,
];

function containsCrisisContent(text: string): boolean {
  return CRISIS_PATTERNS.some((pattern) => pattern.test(text));
}

function isValidUUID(str: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

// Premium rewrite types
const PREMIUM_TYPES = ["more_actionable", "more_compassionate"];

serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

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
  } = await supabase.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { conversationId, messageId, messageText, rewriteType, locale } =
      (await req.json()) as GenerateRewritesRequest;

    // Validate UUIDs
    if (!isValidUUID(conversationId) || !isValidUUID(messageId)) {
      return new Response(JSON.stringify({ error: "Invalid ID format" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate message content length
    if (messageText.length > 2000) {
      return new Response(
        JSON.stringify({ error: "Message exceeds maximum length" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Validate rewrite type
    const validTypes = [
      "less_catastrophic",
      "more_balanced",
      "more_actionable",
      "more_compassionate",
    ];
    if (!validTypes.includes(rewriteType)) {
      return new Response(JSON.stringify({ error: "Invalid rewrite type" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // CRITICAL: Check for crisis content BEFORE any AI processing
    if (containsCrisisContent(messageText)) {
      // Log crisis event for safety monitoring
      await supabase.from("crisis_events").insert({
        user_id: user.id,
        event_type: "rewrite_crisis_detected",
        event_data: {
          conversation_id: conversationId,
          message_id: messageId,
          rewrite_type: rewriteType,
          detected_at: new Date().toISOString(),
        },
      });

      return new Response(
        JSON.stringify({
          error: "crisis_content_detected",
          message:
            "It sounds like you're going through a really difficult time. If you're having thoughts of hurting yourself, please reach out for help immediately.",
          crisis_resources: true,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Verify conversation belongs to user
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", user.id)
      .single();

    if (convError || !conversation) {
      return new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check subscription status
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .in("status", ["active", "trialing"])
      .single();

    const isPremium =
      subscription?.status === "active" || subscription?.status === "trialing";

    // HIGH: Enforce premium rewrite type access server-side
    if (PREMIUM_TYPES.includes(rewriteType) && !isPremium) {
      return new Response(
        JSON.stringify({
          error: "premium_rewrite_type",
          message: "This rewrite type requires a premium subscription",
          upgradeRequired: true,
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!isPremium) {
      // Use database function to atomically check and increment quota
      const { data: quotaResult, error: quotaError } = await supabase.rpc(
        "check_and_increment_rewrite_quota",
        {
          p_user_id: user.id,
          max_daily: 5,
        },
      );

      if (quotaError) {
        console.error("Quota check error:", quotaError);
        return new Response(
          JSON.stringify({ error: "Failed to check quota" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (!quotaResult) {
        return new Response(
          JSON.stringify({
            error: "Daily rewrite limit reached",
            remainingQuota: 0,
            isPremiumUser: false,
            upgradeRequired: true,
          }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // Get rewrite type for system prompt
    const { data: rewriteTypeData } = await supabase
      .from("rewrite_types")
      .select("system_prompt_suffix")
      .eq("type_key", rewriteType)
      .single();

    if (!rewriteTypeData) {
      return new Response(JSON.stringify({ error: "Invalid rewrite type" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Generate rewrites using xAI
    const systemPrompt = `You are a cognitive restructuring assistant helping users reframe their thoughts in a healthier way.

Task: Rewrite the user's message using the following approach:
${rewriteTypeData.system_prompt_suffix}

Requirements:
- Preserve the core meaning and intent
- Sound natural and conversational
- Keep it concise (preferably shorter than original)
- Output JSON array with exactly 3 rewrite options, each with:
  - text: the rewritten message
  - explanation: 1-2 sentences on why this reframing helps

Format: JSON array [{"text": "...", "explanation": "..."}]`;

    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiApiKey) {
      return new Response(JSON.stringify({ error: "AI service unavailable" }), {
        status: 503,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const aiResponse = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${xaiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-2",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: sanitizeForPrompt(messageText) },
        ],
        temperature: 0.7,
        max_tokens: 500,
      }),
    });

    if (!aiResponse.ok) {
      console.error("xAI API error:", await aiResponse.text());
      return new Response(
        JSON.stringify({ error: "Failed to generate rewrites" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const aiData = await aiResponse.json();
    const content = aiData.choices?.[0]?.message?.content || "";

    // Parse JSON from response
    let rewrites: RewriteOption[];
    try {
      const jsonMatch = content.match(/\[[\s\S]*?\]/);
      if (jsonMatch) {
        rewrites = JSON.parse(jsonMatch[0]);
      } else {
        // Fallback parsing
        rewrites = JSON.parse(content);
      }
    } catch (parseError) {
      console.error("Failed to parse AI response:", content);
      return new Response(
        JSON.stringify({ error: "Invalid AI response format" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Create history record
    const { data: history, error: historyError } = await supabase
      .from("rewrite_history")
      .insert({
        user_id: user.id,
        conversation_id: conversationId,
        message_id: messageId,
        original_message: messageText,
        rewrite_type: rewriteType,
      })
      .select("id")
      .single();

    if (historyError) {
      console.error("Failed to create history record:", historyError);
    }

    // Get current quota for response
    let remainingQuota = -1;
    if (!isPremium) {
      const { data: quota } = await supabase
        .from("rewrite_quota")
        .select("daily_count")
        .eq("user_id", user.id)
        .single();
      remainingQuota = quota != null ? 5 - quota.daily_count : 4;
    }

    return new Response(
      JSON.stringify({
        rewrites: rewrites.slice(0, 3),
        remainingQuota: remainingQuota,
        isPremiumUser: isPremium,
        historyId: history?.id,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error generating rewrites:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
