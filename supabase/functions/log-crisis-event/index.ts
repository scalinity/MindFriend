import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

// SEC-CRIT-004: Zod schema for input validation
const CrisisEventSchema = z.object({
  assessmentTemplateId: z.string().uuid(),
  assessmentResponseId: z.string().uuid().optional(),
  eventType: z.string().min(1).max(50),
  severity: z.enum(["low", "medium", "high", "critical"]),
  context: z.record(z.unknown()).optional(),
  responseAction: z.string().max(100).optional(),
});

type CrisisEventRequest = z.infer<typeof CrisisEventSchema>;

serve(async (req) => {
  try {
    // Verify JWT and extract user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") || "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
    );

    // Get user from JWT
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Parse and validate request body with Zod schema
    let body: CrisisEventRequest;
    try {
      const rawBody = await req.json();
      body = CrisisEventSchema.parse(rawBody);
    } catch (validationError) {
      if (validationError instanceof z.ZodError) {
        return new Response(
          JSON.stringify({
            error: "Validation failed",
            details: validationError.errors.map((e) => ({
              field: e.path.join("."),
              message: e.message,
            })),
          }),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          },
        );
      }
      return new Response(JSON.stringify({ error: "Invalid request body" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Log crisis event to database
    const { data, error } = await supabase
      .from("assessment_crisis_events")
      .insert({
        user_id: user.id,
        assessment_template_id: body.assessmentTemplateId,
        assessment_response_id: body.assessmentResponseId,
        event_type: body.eventType,
        severity: body.severity,
        context: body.context || {},
        response_action: body.responseAction,
        created_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error) {
      console.error("Database error:", error);
      return new Response(
        JSON.stringify({ error: "Failed to log crisis event" }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // If critical severity, trigger additional notifications/escalations
    if (body.severity === "critical") {
      await escalateCrisisEvent(supabase, user.id, data);
    }

    // Send success response
    return new Response(JSON.stringify({ success: true, event: data }), {
      status: 201,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Function error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

/**
 * Handle critical crisis escalation
 * For MVP: Log for audit trail and alert via notifications
 * Future: Integration with crisis hotlines, emergency contacts
 */
async function escalateCrisisEvent(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  event: Record<string, unknown>,
): Promise<void> {
  try {
    // In MVP, critical events are logged for audit trail
    // and the client app displays crisis resources screen

    // Could implement:
    // 1. Send notification to emergency contact
    // 2. Alert crisis team via Slack/email
    // 3. Track high-risk users for follow-up

    console.info(
      `Crisis escalation: User ${userId} - Event: ${event.event_type}`,
    );

    // For now, just ensure event is properly recorded
    // Future: Add crisis team notification logic
  } catch (error) {
    console.error("Escalation error:", error);
    // Don't throw - event already logged
  }
}
