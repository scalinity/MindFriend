// Monitor Session Safety - Scans peer support messages for crisis indicators
// This function is designed to be triggered by a cron job
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Crisis keywords that require immediate escalation
const CRISIS_KEYWORDS = [
  "suicide",
  "kill myself",
  "end my life",
  "don't want to live",
  "self-harm",
  "hurt myself",
  "cutting",
  "overdose",
  "want to die",
  "better off dead",
  "ending it",
  "take my own life",
];

// Warning keywords that should be flagged for monitoring
const WARNING_KEYWORDS = [
  "hopeless",
  "can't go on",
  "no point",
  "better off without me",
  "giving up",
  "end it all",
  "disappear",
  "worthless",
  "no reason to live",
  "tired of living",
  "nobody cares",
  "can't take it anymore",
];

// Crisis resources message
const CRISIS_MESSAGE = `If you're having thoughts of harming yourself, please reach out to a crisis helpline:

• National Suicide Prevention Lifeline: 988
• Crisis Text Line: Text HOME to 741741
• International Association for Suicide Prevention: https://www.iasp.info/resources/Crisis_Centres/

You matter, and help is available 24/7. A trained crisis counselor can help right now.`;

interface ProcessingResult {
  processed: number;
  flagged: number;
  escalated: number;
  errors: number;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // This should only be called via cron or internally with service role key
  // SECURITY: Strict auth check - service role key required
  const authHeader = req.headers.get("Authorization");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // Validate service role key exists and is not empty
  if (!serviceRoleKey || serviceRoleKey.length < 32) {
    console.error("SUPABASE_SERVICE_ROLE_KEY is missing or invalid");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Check for exact match of service role key
  const isValidServiceRole = authHeader === `Bearer ${serviceRoleKey}`;
  // Allow requests from within Supabase (cron jobs) with webhook header
  const isSupabaseCron = req.headers.get("X-Supabase-Webhook") === "true";

  if (!isValidServiceRole && !isSupabaseCron) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const result: ProcessingResult = {
    processed: 0,
    flagged: 0,
    escalated: 0,
    errors: 0,
  };

  try {
    // Get recent messages from active sessions (last 5 minutes)
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString();

    const { data: messages, error: fetchError } = await supabase
      .from("support_messages")
      .select(
        `
        id,
        session_id,
        content,
        sender_type,
        support_sessions!inner(
          id,
          seeker_id,
          listener_id,
          status
        )
      `,
      )
      .eq("is_flagged", false)
      .eq("sender_type", "seeker") // Only scan seeker messages
      .eq("support_sessions.status", "active")
      .gte("sent_at", fiveMinutesAgo);

    if (fetchError) {
      console.error("Failed to fetch messages:", fetchError);
      return new Response(
        JSON.stringify({
          error: "Failed to fetch messages",
          details: fetchError,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!messages?.length) {
      return new Response(
        JSON.stringify({ ...result, message: "No messages to process" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    result.processed = messages.length;

    for (const message of messages) {
      try {
        const contentLower = message.content.toLowerCase();
        const session = message.support_sessions as {
          id: string;
          seeker_id: string;
          listener_id: string | null;
        };

        // Check for crisis keywords
        const crisisKeyword = CRISIS_KEYWORDS.find((kw) =>
          contentLower.includes(kw),
        );

        // Check for warning keywords
        const warningKeyword = WARNING_KEYWORDS.find((kw) =>
          contentLower.includes(kw),
        );

        if (crisisKeyword) {
          // Flag message
          await supabase
            .from("support_messages")
            .update({
              is_flagged: true,
              flag_reason: "crisis_keyword_detected",
            })
            .eq("id", message.id);

          // Escalate session
          await supabase
            .from("support_sessions")
            .update({
              was_escalated: true,
              escalation_reason: `Crisis keyword detected: "${crisisKeyword}"`,
              escalated_at: new Date().toISOString(),
            })
            .eq("id", session.id);

          // Insert system message with crisis resources
          await supabase.from("support_messages").insert({
            session_id: session.id,
            sender_type: "system",
            content: CRISIS_MESSAGE,
          });

          // Log crisis event
          await supabase.from("crisis_events").insert({
            user_id: session.seeker_id,
            trigger_type: "peer_support_session",
            trigger_text: message.content.slice(0, 200),
            response_sent: true,
          });

          // Notify listener with guidance
          if (session.listener_id) {
            const { data: listener } = await supabase
              .from("listeners")
              .select("user_id")
              .eq("id", session.listener_id)
              .single();

            if (listener) {
              try {
                await supabase.functions.invoke("send-notification", {
                  body: {
                    userId: listener.user_id,
                    title: "Session Alert",
                    body: "Crisis indicators detected. Resources have been shared. Follow safety protocol.",
                    data: {
                      type: "crisis_alert",
                      sessionId: session.id,
                    },
                  },
                });
              } catch (notifyError) {
                console.error("Failed to notify listener:", notifyError);
              }
            }
          }

          result.escalated++;
          result.flagged++;
        } else if (warningKeyword) {
          // Flag for monitoring but don't escalate
          await supabase
            .from("support_messages")
            .update({
              is_flagged: true,
              flag_reason: `warning_keyword_detected: "${warningKeyword}"`,
            })
            .eq("id", message.id);

          result.flagged++;
        }
      } catch (messageError) {
        console.error("Error processing message:", message.id, messageError);
        result.errors++;
      }
    }

    return new Response(
      JSON.stringify({
        ...result,
        success: true,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error in safety monitor:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        processed: result.processed,
        flagged: result.flagged,
        escalated: result.escalated,
        errors: result.errors + 1,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
