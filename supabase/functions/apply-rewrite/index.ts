import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ApplyRewriteRequest {
  conversationId: string;
  messageId: string;
  rewrittenText: string;
  rewriteHistoryId: string;
}

function isValidUUID(str: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

serve(async (req: Request): Promise<Response> => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
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
    });
  }

  try {
    const { conversationId, messageId, rewrittenText, rewriteHistoryId } =
      (await req.json()) as ApplyRewriteRequest;

    // Validate UUIDs
    if (
      !isValidUUID(conversationId) ||
      !isValidUUID(messageId) ||
      !isValidUUID(rewriteHistoryId)
    ) {
      return new Response(JSON.stringify({ error: "Invalid ID format" }), {
        status: 400,
      });
    }

    // Validate rewritten text length
    if (rewrittenText.length > 2000) {
      return new Response(
        JSON.stringify({ error: "Rewritten text exceeds maximum length" }),
        {
          status: 400,
        },
      );
    }

    // Verify message ownership via conversation
    const { data: message, error: msgError } = await supabase
      .from("messages")
      .select("id, conversation_id, user_id")
      .eq("id", messageId)
      .single();

    if (msgError || !message) {
      return new Response(JSON.stringify({ error: "Message not found" }), {
        status: 404,
      });
    }

    // Verify conversation belongs to user
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("id")
      .eq("id", message.conversation_id)
      .eq("user_id", user.id)
      .single();

    if (convError || !conversation) {
      return new Response(
        JSON.stringify({ error: "Unauthorized to modify this message" }),
        {
          status: 403,
        },
      );
    }

    // Verify rewrite history belongs to user
    const { data: history, error: historyError } = await supabase
      .from("rewrite_history")
      .select("id, user_id, rewritten_message")
      .eq("id", rewriteHistoryId)
      .eq("user_id", user.id)
      .single();

    if (historyError || !history) {
      return new Response(
        JSON.stringify({ error: "Rewrite history not found" }),
        {
          status: 404,
        },
      );
    }

    // Update message with rewritten text
    const { error: messageError } = await supabase
      .from("messages")
      .update({
        content: rewrittenText,
        is_rewritten: true,
        rewritten_from_message_id: messageId,
      })
      .eq("id", messageId);

    if (messageError) {
      return new Response(
        JSON.stringify({ error: "Failed to update message" }),
        {
          status: 500,
        },
      );
    }

    // Update history record
    const { error: updateHistoryError } = await supabase
      .from("rewrite_history")
      .update({
        rewritten_message: rewrittenText,
        was_applied: true,
        applied_at: new Date().toISOString(),
      })
      .eq("id", rewriteHistoryId);

    if (updateHistoryError) {
      console.error("Failed to update history:", updateHistoryError);
      // Don't fail the request, message was updated successfully
    }

    return new Response(
      JSON.stringify({
        success: true,
        updatedMessageId: messageId,
        appliedAt: new Date().toISOString(),
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error applying rewrite:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
    });
  }
});
