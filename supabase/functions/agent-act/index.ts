// Agent Act - Delivers scheduled actions via push notifications
// Triggered by cron (every 15 minutes) to check for due actions

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { isCurrentlyQuietHours } from "../_shared/timing-optimizer.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";


interface AgentAction {
  id: string;
  user_id: string;
  action_type: string;
  content: {
    title: string;
    body: string;
    quickActions?: Array<{ label: string; action: string; value?: string }>;
    deepLink?: string;
  };
  channel: string;
  reasoning: string;
}

interface DeviceToken {
  device_token: string;
  platform: string;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate request - require service role or valid cron token
    const authHeader = req.headers.get("Authorization");
    const cronSecret = Deno.env.get("CRON_SECRET") || "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    // Allow cron jobs with secret, or admin service calls (timing-safe comparison)
    const isAuthorized = await isAuthorizedCronRequest(req.headers, cronSecret, serviceRoleKey);

    if (!isAuthorized) {
      // Validate user token for manual triggers
      if (!authHeader) {
        return new Response(
          JSON.stringify({ error: "Missing authorization" }),
          {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Check if user has admin role for manual triggering
      const { data: profile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", user.id)
        .single();

      if (profile?.role !== "admin") {
        return new Response(
          JSON.stringify({ error: "Admin access required" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    const now = new Date();

    // Get scheduled actions that are due
    const { data: actions, error: actionsError } = await supabase
      .from("agent_actions")
      .select("id, user_id, action_type, content, channel, reasoning")
      .eq("status", "scheduled")
      .lte("scheduled_for", now.toISOString())
      .limit(100);

    if (actionsError) {
      throw new Error(`Failed to fetch actions: ${actionsError.message}`);
    }

    if (!actions || actions.length === 0) {
      return new Response(
        JSON.stringify({ delivered: 0, failed: 0, skipped: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let delivered = 0;
    let failed = 0;
    let skipped = 0;

    for (const action of actions as AgentAction[]) {
      try {
        // Check if user is in quiet hours
        const inQuietHours = await isCurrentlyQuietHours(
          supabase,
          action.user_id,
        );

        if (inQuietHours) {
          // Reschedule for after quiet hours using user's timezone
          // Fetch user timezone for proper scheduling
          const { data: userSettings } = await supabase
            .from("user_settings")
            .select("timezone")
            .eq("user_id", action.user_id)
            .maybeSingle();
          const userTz = userSettings?.timezone || "UTC";

          // Calculate tomorrow 9am in the user's timezone
          const userFormatter = new Intl.DateTimeFormat("en-US", {
            timeZone: userTz,
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
          });
          const userParts = userFormatter.formatToParts(new Date());
          const uYear = userParts.find(p => p.type === "year")?.value || "2026";
          const uMonth = userParts.find(p => p.type === "month")?.value || "01";
          const uDay = userParts.find(p => p.type === "day")?.value || "01";
          // Tomorrow 9am in user's local time, interpreted in their timezone
          const tomorrowDate = new Date(`${uYear}-${uMonth}-${uDay}T09:00:00`);
          tomorrowDate.setDate(tomorrowDate.getDate() + 1);
          // Convert to UTC by creating a date string in the user's timezone
          const tomorrow9amLocal = new Date(
            tomorrowDate.toLocaleString("en-US", { timeZone: userTz })
          );
          // Use the offset to get correct UTC time
          const tomorrow9amUtc = new Date(
            tomorrowDate.getTime() + (tomorrowDate.getTime() - tomorrow9amLocal.getTime())
          );

          await supabase
            .from("agent_actions")
            .update({ scheduled_for: tomorrow9amUtc.toISOString() })
            .eq("id", action.id);

          skipped++;
          continue;
        }

        // Get user's device token
        const { data: deviceData } = await supabase
          .from("device_tokens")
          .select("device_token, platform")
          .eq("user_id", action.user_id)
          .eq("is_active", true)
          .order("updated_at", { ascending: false })
          .limit(1)
          .single();

        if (!deviceData) {
          // No device token, mark as delivered but to in_app only
          await supabase
            .from("agent_actions")
            .update({
              status: "delivered",
              delivered_at: now.toISOString(),
              channel: "in_app",
            })
            .eq("id", action.id);

          delivered++;
          continue;
        }

        // Send push notification using existing send-notification function
        const notificationSent = await sendNotificationViaFunction(
          supabase,
          action.user_id,
          action,
        );

        if (notificationSent) {
          await supabase
            .from("agent_actions")
            .update({
              status: "delivered",
              delivered_at: now.toISOString(),
            })
            .eq("id", action.id);

          delivered++;
        } else {
          // Check if we should mark as failed
          const { data: actionData } = await supabase
            .from("agent_actions")
            .select("created_at")
            .eq("id", action.id)
            .single();

          // Guard against null actionData - mark as cancelled if no data found
          if (!actionData?.created_at) {
            await supabase
              .from("agent_actions")
              .update({ status: "cancelled" })
              .eq("id", action.id);
            failed++;
            continue;
          }

          const createdAt = new Date(actionData.created_at);
          const hoursSinceCreated =
            (now.getTime() - createdAt.getTime()) / (1000 * 60 * 60);

          if (hoursSinceCreated > 6) {
            // Failed after 6 hours of retries
            await supabase
              .from("agent_actions")
              .update({ status: "cancelled" })
              .eq("id", action.id);
          }

          failed++;
        }
      } catch (error) {
        console.error(`Failed to deliver action ${action.id}:`, error);
        failed++;
      }
    }

    return new Response(JSON.stringify({ delivered, failed, skipped }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Agent act error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function sendNotificationViaFunction(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: AgentAction,
): Promise<boolean> {
  try {
    // Use the existing send-notification Edge Function
    const { data, error } = await supabase.functions.invoke(
      "send-notification",
      {
        body: {
          type: "agent_action",
          recipientId: userId,
          data: {
            title: action.content.title,
            body: action.content.body,
            deepLink: action.content.deepLink,
            actionId: action.id,
            actionType: action.action_type,
          },
        },
      },
    );

    if (error) {
      console.error("send-notification error:", error);
      return false;
    }

    return data?.success === true;
  } catch (error) {
    console.error("Failed to invoke send-notification:", error);
    return false;
  }
}
