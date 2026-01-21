import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface GenerateActionCardsRequest {
  conversationId: string;
  messageId: string;
  messageContent: string;
  messageIntent?: string;
}

interface CardData {
  id: string;
  cardType: string;
  title: string;
  description: string;
  icon: string;
  estimatedMinutes: number;
  actionDestination: {
    type: string;
    id?: string;
    params?: Record<string, string>;
  };
  metadata: {
    isPremium: boolean;
    priority: number;
    conditions?: Record<string, string>;
  };
}

interface GenerateActionCardsResponse {
  cards: CardData[];
  generatedAt: string;
}

// Card templates
const TEMPLATES = [
  {
    trigger_type: "breathing",
    card_title: "Take a Breath",
    card_description: "A quick breathing exercise to help you relax",
    action_destination: "exercise",
    action_destination_id: "breathing-1",
    icon: "wind",
    estimated_minutes: 3,
    priority: 90,
    is_premium: false,
  },
  {
    trigger_type: "meditation",
    card_title: "Mindful Moment",
    card_description: "A short meditation to center yourself",
    action_destination: "exercise",
    action_destination_id: "meditation-1",
    icon: "leaf",
    estimated_minutes: 5,
    priority: 85,
    is_premium: false,
  },
  {
    trigger_type: "journaling",
    card_title: "Reflect & Write",
    card_description: "Journal about your thoughts and feelings",
    action_destination: "journal",
    action_destination_id: null,
    icon: "pencil.and.scribble",
    estimated_minutes: 10,
    priority: 80,
    is_premium: false,
  },
  {
    trigger_type: "mood_check",
    card_title: "How Are You Feeling?",
    card_description: "Take a moment to log your current mood",
    action_destination: "mood",
    action_destination_id: null,
    icon: "face.smiling",
    estimated_minutes: 1,
    priority: 95,
    is_premium: false,
  },
  {
    trigger_type: "quest_offer",
    card_title: "New Quest Available",
    card_description: "Complete this quest to earn rewards",
    action_destination: "quest",
    action_destination_id: null,
    icon: "star",
    estimated_minutes: 15,
    priority: 75,
    is_premium: false,
  },
  {
    trigger_type: "grounding",
    card_title: "Ground Yourself",
    card_description: "A 5-4-3-2-1 grounding exercise",
    action_destination: "exercise",
    action_destination_id: "grounding-1",
    icon: "tree",
    estimated_minutes: 5,
    priority: 88,
    is_premium: false,
  },
  {
    trigger_type: "resource",
    card_title: "Helpful Resource",
    card_description: "Learn more about this topic",
    action_destination: "resource",
    action_destination_id: null,
    icon: "book",
    estimated_minutes: 5,
    priority: 60,
    is_premium: false,
  },
  {
    trigger_type: "meditation_premium",
    card_title: "Premium Meditation",
    card_description: "Unlock this guided meditation",
    action_destination: "exercise",
    action_destination_id: "meditation-premium-1",
    icon: "crown",
    estimated_minutes: 10,
    priority: 70,
    is_premium: true,
  },
];

function isValidUUID(str: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

function getTemplatesForIntent(intent: string, isPremium: boolean) {
  const intentMap: Record<string, string[]> = {
    breathing_suggestion: ["breathing"],
    meditation_suggestion: ["meditation", "meditation_premium"],
    journaling_suggestion: ["journaling"],
    mood_check: ["mood_check"],
    quest_offer: ["quest_offer"],
    grounding_suggestion: ["grounding"],
    resource_share: ["resource"],
  };

  const validTriggers = intentMap[intent] || [];
  return TEMPLATES.filter((t) => {
    if (t.is_premium && !isPremium) return false;
    return validTriggers.includes(t.trigger_type) || t.trigger_type === intent;
  }).sort((a, b) => b.priority - a.priority);
}

function detectIntentFromContent(content: string): string {
  const lower = content.toLowerCase();
  if (lower.includes("breath") || lower.includes("breathe"))
    return "breathing_suggestion";
  if (lower.includes("meditat") || lower.includes("calm"))
    return "meditation_suggestion";
  if (
    lower.includes("journal") ||
    lower.includes("write") ||
    lower.includes("reflect")
  )
    return "journaling_suggestion";
  if (
    lower.includes("mood") ||
    lower.includes("feeling") ||
    lower.includes("how are")
  )
    return "mood_check";
  if (
    lower.includes("quest") ||
    lower.includes("challenge") ||
    lower.includes("goal")
  )
    return "quest_offer";
  if (
    lower.includes("ground") ||
    lower.includes("5-4-3-2-1") ||
    lower.includes("senses")
  )
    return "grounding_suggestion";
  if (
    lower.includes("resource") ||
    lower.includes("read more") ||
    lower.includes("learn")
  )
    return "resource_share";
  return "general";
}

function mapTriggerToCardType(trigger: string): string {
  const mapping: Record<string, string> = {
    breathing: "exercise",
    meditation: "exercise",
    meditation_premium: "exercise",
    grounding: "exercise",
    journaling: "journaling",
    mood_check: "mood",
    quest_offer: "quest",
    resource: "resource",
  };
  return mapping[trigger] || "resource";
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
    const { conversationId, messageId, messageContent, messageIntent } =
      (await req.json()) as GenerateActionCardsRequest;

    // Validate UUIDs
    if (!isValidUUID(conversationId) || !isValidUUID(messageId)) {
      return new Response(JSON.stringify({ error: "Invalid ID format" }), {
        status: 400,
      });
    }

    // Validate message content length
    if (messageContent.length > 2000) {
      return new Response(
        JSON.stringify({ error: "Message exceeds maximum length" }),
        { status: 400 },
      );
    }

    // Verify user owns the conversation
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", user.id)
      .single();

    if (convError || !conversation) {
      return new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
      });
    }

    // Server-side verify premium status
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .in("status", ["active", "trialing"])
      .single();

    const isPremium =
      subscription?.status === "active" || subscription?.status === "trialing";

    // Get user context for template scoring
    const { data: completedExercises } = await supabase
      .from("exercise_sessions")
      .select("exercise_id")
      .eq("user_id", user.id)
      .gte(
        "created_at",
        new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
      );

    const completedExerciseIds =
      completedExercises?.map((e) => e.exercise_id) || [];

    const intent = messageIntent || detectIntentFromContent(messageContent);
    let templates = getTemplatesForIntent(intent, isPremium);
    templates = templates
      .map((t) => ({
        template: t,
        score:
          t.priority -
          (t.action_destination_id &&
          completedExerciseIds.includes(t.action_destination_id)
            ? 50
            : 0),
      }))
      .filter((t) => t.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 3)
      .map((t) => t.template);

    const cards: CardData[] = [];
    for (const template of templates) {
      const cardId = crypto.randomUUID();
      const { error: insertError } = await supabase
        .from("chat_action_cards")
        .insert({
          id: cardId,
          session_id: conversationId,
          message_id: messageId,
          card_type: mapTriggerToCardType(template.trigger_type),
          card_data: {
            title: template.card_title,
            description: template.card_description,
            icon: template.icon,
            estimated_minutes: template.estimated_minutes,
            action_destination: {
              type: template.action_destination,
              id: template.action_destination_id,
            },
            is_premium: template.is_premium,
            priority: template.priority,
          },
          template_id: null,
          expires_at: new Date(Date.now() + 3600000).toISOString(),
        });

      if (insertError) {
        console.error("Failed to insert card:", insertError);
        continue;
      }

      cards.push({
        id: cardId,
        cardType: mapTriggerToCardType(template.trigger_type),
        title: template.card_title,
        description: template.card_description,
        icon: template.icon,
        estimatedMinutes: template.estimated_minutes,
        actionDestination: {
          type: template.action_destination,
          id: template.action_destination_id,
        },
        metadata: {
          isPremium: template.is_premium,
          priority: template.priority,
        },
      });

      // Get device type from User-Agent
      const userAgent = req.headers.get("User-Agent") ?? "unknown";
      const deviceType = userAgent.includes("iOS")
        ? "iOS"
        : userAgent.includes("Android")
          ? "Android"
          : "web";

      await supabase.from("card_analytics").insert({
        card_id: cardId,
        event_type: "impression",
        event_data: { message_id: messageId },
        device_type: deviceType,
      });
    }

    return new Response(
      JSON.stringify({
        cards,
        generatedAt: new Date().toISOString(),
      } as GenerateActionCardsResponse),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error generating action cards:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
    });
  }
});
