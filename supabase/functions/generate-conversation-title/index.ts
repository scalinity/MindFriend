// Generate a title for a conversation based on content
// Used by voice mode and other flows that bypass the main chat function

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

const XAI_API_URL = "https://api.x.ai/v1/chat/completions";
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface GenerateTitleRequest {
  conversationId: string;
  content: string;
}

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
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

    // Parse request
    const { conversationId, content }: GenerateTitleRequest = await req.json();

    if (!conversationId || !content) {
      return new Response(
        JSON.stringify({ error: "Missing conversationId or content" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate conversation ID format
    if (!UUID_REGEX.test(conversationId)) {
      return new Response(
        JSON.stringify({ error: "Invalid conversationId format" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify conversation belongs to user and has no title
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("id, user_id, title")
      .eq("id", conversationId)
      .single();

    if (convError || !conversation) {
      return new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (conversation.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // If conversation already has a title, return it
    if (conversation.title) {
      return new Response(
        JSON.stringify({ title: conversation.title, generated: false }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate title using AI
    const xaiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiKey) {
      console.error("XAI_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "Service temporarily unavailable" }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Truncate content for title generation (use first 500 chars)
    const truncatedContent = content.slice(0, 500);

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
              "Generate a very short title (3-5 words max) for this conversation based on the content. Return only the title, no quotes or punctuation. For voice conversations, focus on the main topic discussed.",
          },
          { role: "user", content: truncatedContent },
        ],
        max_tokens: 20,
        temperature: 0.5,
      }),
    });

    if (!titleResponse.ok) {
      const errorText = await titleResponse.text();
      console.error(
        "Title generation API error:",
        titleResponse.status,
        errorText,
      );
      return new Response(
        JSON.stringify({ error: "Failed to generate title" }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const titleData = await titleResponse.json();
    const generatedTitle =
      titleData.choices?.[0]?.message?.content?.trim() || "Voice Conversation";

    // Update conversation with generated title
    const { error: updateError } = await supabase
      .from("conversations")
      .update({ title: generatedTitle })
      .eq("id", conversationId);

    if (updateError) {
      console.error("Failed to update conversation title:", updateError);
      return new Response(JSON.stringify({ error: "Failed to save title" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ title: generatedTitle, generated: true }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Generate title error:", error);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
