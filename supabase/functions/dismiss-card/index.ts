import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface DismissCardRequest {
  cardId: string;
  reason?: string;
  snoozeMinutes?: number;
  suppressSimilar: boolean;
}

function isValidUUID(str: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

// Valid dismissal reasons
const VALID_DISMISS_REASONS = [
  "not_interested",
  "already_done",
  "wrong_timing",
  "not_relevant",
  "other",
];

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
    const { cardId, reason, snoozeMinutes, suppressSimilar } =
      (await req.json()) as DismissCardRequest;

    // Validate UUID format
    if (!isValidUUID(cardId)) {
      return new Response(JSON.stringify({ error: "Invalid card ID format" }), {
        status: 400,
      });
    }

    // Validate reason if provided
    if (reason && !VALID_DISMISS_REASONS.includes(reason)) {
      return new Response(
        JSON.stringify({ error: "Invalid dismissal reason" }),
        { status: 400 },
      );
    }

    // Validate snoozeMinutes range (1 minute to 24 hours)
    if (
      snoozeMinutes !== undefined &&
      (snoozeMinutes < 1 || snoozeMinutes > 1440)
    ) {
      return new Response(
        JSON.stringify({ error: "Invalid snooze duration" }),
        { status: 400 },
      );
    }

    const { data: card, error: cardError } = await supabase
      .from("chat_action_cards")
      .select("id, session_id")
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

    const updates: Record<string, unknown> = {
      is_dismissed: true,
      dismissal_reason: reason,
      dismissed_at: new Date().toISOString(),
    };

    if (snoozeMinutes) {
      updates.expires_at = new Date(
        Date.now() + snoozeMinutes * 60000,
      ).toISOString();
      updates.is_dismissed = false;
    }

    const { error: updateError } = await supabase
      .from("chat_action_cards")
      .update(updates)
      .eq("id", cardId);

    if (updateError) {
      return new Response(JSON.stringify({ error: "Failed to dismiss card" }), {
        status: 500,
      });
    }

    // Log dismissal analytics
    await supabase.from("card_analytics").insert({
      card_id: cardId,
      event_type: "dismiss",
      event_data: {
        reason,
        snooze_minutes: snoozeMinutes,
        suppress_similar: suppressSimilar,
      },
      device_type: "iOS",
    });

    return new Response(
      JSON.stringify({
        success: true,
        cardId,
        dismissedAt: updates.dismissed_at,
        snoozeExpiresAt: updates.expires_at,
        suppressionActive: suppressSimilar,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error dismissing card:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
    });
  }
});
