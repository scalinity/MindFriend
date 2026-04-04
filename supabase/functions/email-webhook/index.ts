import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { Webhook } from "https://esm.sh/svix@1.15.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET")!;

if (!webhookSecret) {
  throw new Error("RESEND_WEBHOOK_SECRET environment variable is not set");
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Verify webhook signature using Svix
    const svixHeaders = {
      "svix-id": req.headers.get("svix-id") || "",
      "svix-timestamp": req.headers.get("svix-timestamp") || "",
      "svix-signature": req.headers.get("svix-signature") || "",
    };

    const payload = await req.text();
    const wh = new Webhook(webhookSecret);

    let body;
    try {
      body = wh.verify(payload, svixHeaders) as Record<string, unknown>;
    } catch (error) {
      console.error("Webhook signature verification failed:", error);
      return new Response(
        JSON.stringify({ error: "Unauthorized - invalid signature" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Webhook payload structure:
    // {
    //   "type": "email.sent" | "email.opened" | "email.clicked" | "email.bounced" | "email.complained",
    //   "created_at": "2024-01-19T12:00:00.000Z",
    //   "data": {
    //     "email_id": "...",
    //     "from": "from@example.com",
    //     "to": "to@example.com",
    //     "created_at": "...",
    //     "bounce": { "type": "permanent" | "temporary", "message": "..." }
    //   }
    // }

    const { type, data } = body;

    if (!type || !data) {
      return new Response(JSON.stringify({ error: "Missing type or data" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`Processing webhook: ${type}`);

    // Extract message ID from email_id (our custom header X-Entity-Ref-ID)
    const messageId = data.email_id;

    // Find email log by message ID
    const { data: emailLog, error: fetchError } = await supabase
      .from("email_logs")
      .select("id, user_id, email_type")
      .eq("message_id", messageId)
      .single();

    if (fetchError || !emailLog) {
      console.warn(`Email log not found for message ID: ${messageId}`);
      return new Response(
        JSON.stringify({ success: true, message: "Email log not found" }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    // Update email_logs based on event type
    switch (type) {
      case "email.opened":
        await supabase
          .from("email_logs")
          .update({
            opened_at: new Date().toISOString(),
          })
          .eq("id", emailLog.id);
        break;

      case "email.clicked":
        await supabase
          .from("email_logs")
          .update({
            clicked_at: new Date().toISOString(),
          })
          .eq("id", emailLog.id);
        break;

      case "email.bounced":
        const bounceType = data.bounce?.type || "unknown";
        const bounceReason = data.bounce?.message || "Unknown bounce reason";

        await supabase
          .from("email_logs")
          .update({
            bounce_type: bounceType,
            bounce_reason: bounceReason,
          })
          .eq("id", emailLog.id);

        // If permanent bounce, add to suppression list
        if (bounceType === "permanent") {
          const { data: profile } = await supabase
            .from("profiles")
            .select("email")
            .eq("id", emailLog.user_id)
            .single();

          if (profile) {
            await supabase.from("email_suppression_list").upsert({
              user_id: emailLog.user_id,
              email: profile.email,
              reason: `Permanent bounce: ${bounceReason}`,
              bounce_type: bounceType,
              suppressed_at: new Date().toISOString(),
            }, {
              onConflict: "user_id,email"
            });
          }
        }
        break;

      case "email.complained":
        // Mark as complaint for compliance
        await supabase
          .from("email_logs")
          .update({
            bounce_type: "complaint",
            bounce_reason: "User marked as spam",
          })
          .eq("id", emailLog.id);

        // Unsubscribe user from all emails
        await supabase
          .from("email_preferences")
          .update({
            unsubscribed_at: new Date().toISOString(),
            unsubscribe_reason: "Spam complaint",
          })
          .eq("user_id", emailLog.user_id);
        break;

      case "email.sent":
        // Resend sends this webhook when email is successfully sent
        // We already update on send in send-email function, so just log
        console.log(`Email ${messageId} confirmed sent by Resend`);
        break;

      default:
        console.warn(`Unknown webhook type: ${type}`);
    }

    return new Response(JSON.stringify({ success: true, type, messageId }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Webhook processing error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
