// Agent Act - Delivers scheduled actions via push notifications
// Triggered by cron (every 15 minutes) to check for due actions

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { isCurrentlyQuietHours } from "../_shared/timing-optimizer.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
    const cronSecret = Deno.env.get("CRON_SECRET");

    // Allow cron jobs with secret, or admin service calls
    const isCronRequest =
      cronSecret && req.headers.get("X-Cron-Secret") === cronSecret;
    const isServiceRequest = authHeader?.includes(
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    if (!isCronRequest && !isServiceRequest) {
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
          // Reschedule for after quiet hours
          const tomorrow9am = new Date();
          tomorrow9am.setDate(tomorrow9am.getDate() + 1);
          tomorrow9am.setHours(9, 0, 0, 0);

          await supabase
            .from("agent_actions")
            .update({ scheduled_for: tomorrow9am.toISOString() })
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
          user_id: userId,
          title: action.content.title,
          body: action.content.body,
          data: {
            action_id: action.id,
            action_type: action.action_type,
            deep_link: action.content.deepLink,
            category: "AGENT_ACTION",
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
