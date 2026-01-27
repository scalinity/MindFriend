import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  validateTimezone,
  calculateScheduledTime,
  getMonthYear,
  formatDate,
  shouldSendEmail,
  generateMessageId,
  calculateNextRetryTime,
  shouldRetryEmail,
  formatErrorMessage,
  checkCrisisSuppressionPeriod,
  insertEmailLogWithRateLimitCheck,
  timingSafeEqual,
} from "../_shared/email-utils.ts";
import {
  renderTemplate,
  validatePayload,
  EmailTemplate,
} from "../_shared/email-templates.ts";

interface EmailQueueItem {
  id: string;
  user_id: string;
  email_type: string;
  template_version: string;
  payload: Record<string, unknown>;
  status: string;
  scheduled_for: string;
  retry_count: number;
}

interface UserProfile {
  id: string;
  email: string;
  full_name?: string;
}

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const resendApiKey = Deno.env.get("RESEND_API_KEY")!;
const appUrl = Deno.env.get("APP_URL") || "https://getmindfriend.app";

// UUID validation regex
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

serve(async (req: Request) => {
  // Only accept POST requests
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Validate CRON_SECRET to prevent unauthorized access (timing-safe comparison)
  const cronSecret = Deno.env.get("CRON_SECRET");
  const authHeader = req.headers.get("X-Cron-Secret");
  
  if (!cronSecret || !timingSafeEqual(authHeader, cronSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const body = await req.json();

    const { queueItemId } = body;
    
    // Validate queueItemId format (must be valid UUID)
    if (!queueItemId || !UUID_REGEX.test(queueItemId)) {
      return new Response(
        JSON.stringify({ error: "Invalid or missing queueItemId (must be UUID format)" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Fetch queue item
    const { data: queueItem, error: fetchError } = await supabase
      .from("email_queue")
      .select("*")
      .eq("id", queueItemId)
      .single();

    if (fetchError || !queueItem) {
      return new Response(
        JSON.stringify({ error: "Queue item not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    const qi = queueItem as EmailQueueItem;

    // Fetch user profile
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("id, email, full_name")
      .eq("id", qi.user_id)
      .single();

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: "User profile not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    const userProfile = profile as UserProfile;

    // Check send conditions
    const { shouldSend, reason } = await shouldSendEmail(
      supabase,
      qi.user_id,
      qi.email_type,
    );

    if (!shouldSend) {
      // Log as skipped
      const messageId = generateMessageId();
      await supabase.from("email_logs").insert({
        user_id: qi.user_id,
        email_type: qi.email_type,
        template_version: qi.template_version,
        message_id: messageId,
        status: "skipped",
        skipped_reason: reason,
        created_at: new Date().toISOString(),
      });

      // Update queue item
      await supabase
        .from("email_queue")
        .update({
          status: "sent",
          updated_at: new Date().toISOString(),
        })
        .eq("id", queueItemId);

      return new Response(
        JSON.stringify({ skipped: true, reason }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Validate payload
    if (!validatePayload(qi.email_type, qi.payload)) {
      const failureReason = `Invalid payload for ${qi.email_type}`;

      // Log failure
      await supabase.from("email_logs").insert({
        user_id: qi.user_id,
        email_type: qi.email_type,
        template_version: qi.template_version,
        message_id: generateMessageId(),
        status: "failed",
        failure_reason: failureReason,
        created_at: new Date().toISOString(),
      });

      // Try retry or move to DLQ
      if (shouldRetryEmail(qi.retry_count)) {
        const nextRetry = calculateNextRetryTime(qi.retry_count);
        await supabase
          .from("email_queue")
          .update({
            status: "pending",
            retry_count: qi.retry_count + 1,
            scheduled_for: nextRetry.toISOString(),
            last_error: failureReason,
            updated_at: new Date().toISOString(),
          })
          .eq("id", queueItemId);
      } else {
        // Move to DLQ
        await supabase.from("email_dead_letter_queue").insert({
          user_id: qi.user_id,
          email_type: qi.email_type,
          template_version: qi.template_version,
          payload: qi.payload,
          failure_count: qi.retry_count + 1,
          last_error: failureReason,
          original_scheduled_for: qi.scheduled_for,
          moved_to_dlq_at: new Date().toISOString(),
        });

        await supabase
          .from("email_queue")
          .update({ status: "failed", updated_at: new Date().toISOString() })
          .eq("id", queueItemId);
      }

      return new Response(
        JSON.stringify({ error: failureReason }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Render template
    let template: EmailTemplate;
    try {
      // Add userName to payload if not present
      const enrichedPayload = {
        ...qi.payload,
        userName: userProfile.full_name || userProfile.email.split("@")[0],
      };
      template = renderTemplate(qi.email_type, enrichedPayload as any);
    } catch (error) {
      const failureReason = `Template rendering failed: ${formatErrorMessage(error)}`;

      await supabase.from("email_logs").insert({
        user_id: qi.user_id,
        email_type: qi.email_type,
        template_version: qi.template_version,
        message_id: generateMessageId(),
        status: "failed",
        failure_reason: failureReason,
        created_at: new Date().toISOString(),
      });

      if (shouldRetryEmail(qi.retry_count)) {
        const nextRetry = calculateNextRetryTime(qi.retry_count);
        await supabase
          .from("email_queue")
          .update({
            status: "pending",
            retry_count: qi.retry_count + 1,
            scheduled_for: nextRetry.toISOString(),
            last_error: failureReason,
            updated_at: new Date().toISOString(),
          })
          .eq("id", queueItemId);
      }

      return new Response(
        JSON.stringify({ error: failureReason }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Send via Resend
    const messageId = generateMessageId();
    let resendResponse: any;

    try {
      // Use AbortController for timeout (20 second limit)
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 20000);

      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${resendApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: "MindFriend <notifications@mindfriend.email>",
          to: userProfile.email,
          subject: template.subject,
          html: template.htmlBody,
          text: template.textBody,
          headers: {
            "X-Entity-Ref-ID": messageId,
            "List-Unsubscribe": `${appUrl}/email-preferences`,
          },
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);
      resendResponse = await response.json();

      if (!response.ok) {
        throw new Error(
          `Resend API error: ${resendResponse.message || response.statusText}`,
        );
      }
    } catch (error) {
      const failureReason = `Resend API call failed: ${formatErrorMessage(error)}`;

      // Log failure
      await supabase.from("email_logs").insert({
        user_id: qi.user_id,
        email_type: qi.email_type,
        template_version: qi.template_version,
        message_id: messageId,
        status: "failed",
        failure_reason: failureReason,
        created_at: new Date().toISOString(),
      });

      // Retry or DLQ
      if (shouldRetryEmail(qi.retry_count)) {
        const nextRetry = calculateNextRetryTime(qi.retry_count);
        await supabase
          .from("email_queue")
          .update({
            status: "pending",
            retry_count: qi.retry_count + 1,
            scheduled_for: nextRetry.toISOString(),
            last_error: failureReason,
            updated_at: new Date().toISOString(),
          })
          .eq("id", queueItemId);
      } else {
        await supabase.from("email_dead_letter_queue").insert({
          user_id: qi.user_id,
          email_type: qi.email_type,
          template_version: qi.template_version,
          payload: qi.payload,
          failure_count: qi.retry_count + 1,
          last_error: failureReason,
          original_scheduled_for: qi.scheduled_for,
          moved_to_dlq_at: new Date().toISOString(),
        });

        await supabase
          .from("email_queue")
          .update({ status: "failed", updated_at: new Date().toISOString() })
          .eq("id", queueItemId);
      }

      return new Response(
        JSON.stringify({ error: failureReason }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Log successful send
    const { success: logSuccess, withinLimit } = await insertEmailLogWithRateLimitCheck(
      supabase,
      qi.user_id,
      {
        user_id: qi.user_id,
        email_type: qi.email_type,
        template_version: qi.template_version,
        message_id: messageId,
        status: "sent",
        sent_at: new Date().toISOString(),
        created_at: new Date().toISOString(),
      }
    );

    if (!logSuccess) {
      console.error("Failed to log email send");
      return new Response(
        JSON.stringify({ error: "Failed to log email send" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // CRITICAL FIX: Check if rate limit was exceeded during atomic insert
    // If so, update the log to "skipped" instead of "sent" to accurately reflect that
    // the email was NOT sent due to rate limiting
    if (!withinLimit) {
      console.warn(`Rate limit exceeded for user ${qi.user_id} during email send. Log marked as skipped.`);
      
      // Update the email log we just inserted to mark as skipped
      await supabase
        .from("email_logs")
        .update({
          status: "skipped",
          skipped_reason: "rate limit exceeded (10 per 7 days)",
          updated_at: new Date().toISOString(),
        })
        .eq("message_id", messageId);
      
      // Mark queue item as sent (to avoid retry loops)
      await supabase
        .from("email_queue")
        .update({
          status: "sent",
          updated_at: new Date().toISOString(),
        })
        .eq("id", queueItemId);

      return new Response(
        JSON.stringify({
          skipped: true,
          reason: "rate limit exceeded (10 per 7 days)",
          queueItemId,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    // Update queue to sent
    await supabase
      .from("email_queue")
      .update({
        status: "sent",
        updated_at: new Date().toISOString(),
      })
      .eq("id", queueItemId);

    return new Response(
      JSON.stringify({
        success: true,
        messageId,
        queueItemId,
        emailType: qi.email_type,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Unexpected error in send-email:", error);
    return new Response(
      JSON.stringify({
        error: `Unexpected error: ${formatErrorMessage(error)}`,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
