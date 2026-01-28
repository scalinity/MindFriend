// MindFriend Assessment Reminder Scheduler
// Runs daily via Supabase cron to send reminders for due assessments
// Deep links to: mindfriend://assessment/{code}

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import { isInQuietHours } from "../_shared/notification-utils.ts";

interface DueAssessment {
  schedule_id: string;
  user_id: string;
  assessment_template_id: string;
  assessment_code: string;
  assessment_name: string;
  next_due_at: string;
  last_completed_at: string | null;
  timezone: string | null;
  quiet_hours_start_local: string | null;
  quiet_hours_end_local: string | null;
  reminders_enabled: boolean;
  display_name: string | null;
  device_token: string | null;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  // Require cron secret or service role key
  const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

  if (
    !isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey)
  ) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const now = new Date();
    let remindersSent = 0;
    let remindersSkipped = 0;

    // Find all assessment schedules that are due and haven't had a reminder sent
    // Join with assessment_templates to get the code and name
    // Join with user_settings for notification preferences
    // Join with profiles for display name
    // Join with device_tokens for push capability
    const { data: dueAssessments, error: fetchError } = await supabaseAdmin
      .from("assessment_schedule")
      .select(
        `
        id,
        user_id,
        assessment_template_id,
        next_due_at,
        last_completed_at,
        reminder_sent,
        assessment_templates!inner(code, name),
        profiles!inner(display_name),
        user_settings!inner(
          timezone,
          quiet_hours_start_local,
          quiet_hours_end_local,
          reminders_enabled
        )
      `,
      )
      .eq("enabled", true)
      .eq("reminder_sent", false)
      .lte("next_due_at", now.toISOString());

    if (fetchError) {
      console.error("Error fetching due assessments:", fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch due assessments" }),
        { status: 500, headers },
      );
    }

    if (!dueAssessments || dueAssessments.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          timestamp: now.toISOString(),
          reminders_sent: 0,
          reminders_skipped: 0,
          message: "No assessments due",
        }),
        { status: 200, headers },
      );
    }

    console.log(`Found ${dueAssessments.length} due assessments`);

    // Process each due assessment
    for (const schedule of dueAssessments) {
      const userId = schedule.user_id;
      const assessmentCode = (schedule.assessment_templates as any)?.code || "";
      const assessmentName =
        (schedule.assessment_templates as any)?.name || "wellness check-in";
      const displayName =
        (schedule.profiles as any)?.display_name?.split(" ")[0] || "there";
      const settings = schedule.user_settings as any;

      // Check if reminders are enabled
      if (!settings?.reminders_enabled) {
        console.log(`User ${userId.substring(0, 8)}...: reminders disabled`);
        remindersSkipped++;
        continue;
      }

      // Check quiet hours
      const timezone = settings?.timezone || "UTC";
      const currentHour = parseInt(
        new Date().toLocaleString("en-US", {
          timeZone: timezone,
          hour: "numeric",
          hour12: false,
        }),
        10,
      );

      if (
        isInQuietHours(
          currentHour,
          settings?.quiet_hours_start_local,
          settings?.quiet_hours_end_local,
        )
      ) {
        console.log(`User ${userId.substring(0, 8)}...: in quiet hours`);
        remindersSkipped++;
        continue;
      }

      // Calculate days since last assessment
      let daysSinceLastAssessment: number | undefined;
      if (schedule.last_completed_at) {
        const lastCompleted = new Date(schedule.last_completed_at);
        daysSinceLastAssessment = Math.floor(
          (now.getTime() - lastCompleted.getTime()) / (1000 * 60 * 60 * 24),
        );
      }

      // Send the notification
      try {
        const { error: notifyError } = await supabaseAdmin.functions.invoke(
          "send-notification",
          {
            body: {
              type: "assessment_reminder",
              recipientId: userId,
              data: {
                assessmentCode,
                assessmentName,
                displayName,
                daysSinceLastAssessment,
              },
            },
          },
        );

        if (notifyError) {
          console.error(
            `Failed to send notification to ${userId.substring(0, 8)}...:`,
            notifyError,
          );
          remindersSkipped++;
          continue;
        }

        // Mark reminder as sent
        const { error: updateError } = await supabaseAdmin
          .from("assessment_schedule")
          .update({ reminder_sent: true })
          .eq("id", schedule.id);

        if (updateError) {
          console.error(
            `Failed to update reminder_sent for schedule ${schedule.id}:`,
            updateError,
          );
        }

        remindersSent++;
        console.log(
          `Sent ${assessmentCode} reminder to ${userId.substring(0, 8)}...`,
        );
      } catch (err) {
        console.error(
          `Error sending notification to ${userId.substring(0, 8)}...:`,
          err,
        );
        remindersSkipped++;
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: now.toISOString(),
        assessments_due: dueAssessments.length,
        reminders_sent: remindersSent,
        reminders_skipped: remindersSkipped,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Assessment reminder scheduler error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
