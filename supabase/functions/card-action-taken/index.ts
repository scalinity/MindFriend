import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface CardActionRequest {
  cardId: string;
  actionType: string;
  additionalData?: Record<string, unknown>;
}

function isValidUUID(str: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

// Valid action types
const VALID_ACTION_TYPES = ["tap", "complete", "dismiss"];

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
    const { cardId, actionType, additionalData } =
      (await req.json()) as CardActionRequest;

    // Validate UUID format
    if (!isValidUUID(cardId)) {
      return new Response(JSON.stringify({ error: "Invalid card ID format" }), {
        status: 400,
      });
    }

    // Validate actionType at runtime
    if (!VALID_ACTION_TYPES.includes(actionType)) {
      return new Response(JSON.stringify({ error: "Invalid action type" }), {
        status: 400,
      });
    }

    // Verify user owns this card via conversation
    const { data: card, error: cardError } = await supabase
      .from("chat_action_cards")
      .select("id, session_id, is_completed, is_dismissed")
      .eq("id", cardId)
      .single();

    if (cardError || !card) {
      return new Response(JSON.stringify({ error: "Card not found" }), {
        status: 404,
      });
    }

    // Verify conversation belongs to user
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("id")
      .eq("id", card.session_id)
      .eq("user_id", user.id)
      .single();

    if (convError || !conversation) {
      return new Response(
        JSON.stringify({ error: "Unauthorized to modify this card" }),
        { status: 403 },
      );
    }

    // Update card based on action type
    const updates: Record<string, unknown> = {};
    if (actionType === "tap") {
      updates.action_taken_at = new Date().toISOString();
    } else if (actionType === "complete") {
      updates.is_completed = true;
      updates.completed_at = new Date().toISOString();
      if (additionalData) {
        updates.completion_data = additionalData;
      }
    } else if (actionType === "dismiss") {
      updates.is_dismissed = true;
      updates.dismissed_at = new Date().toISOString();
    }

    const { error: updateError } = await supabase
      .from("chat_action_cards")
      .update(updates)
      .eq("id", cardId);

    if (updateError) {
      return new Response(JSON.stringify({ error: "Failed to update card" }), {
        status: 500,
      });
    }

    // Log analytics event
    await supabase.from("card_analytics").insert({
      card_id: cardId,
      event_type: actionType === "dismiss" ? "dismiss" : "click",
      event_data: additionalData || {},
      device_type: "iOS",
    });

    return new Response(
      JSON.stringify({
        success: true,
        cardUpdated: updates,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error recording card action:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
    });
  }
});
