// MindFriend Streak Risk Check Cron
// Runs hourly via Supabase cron to identify users at streak risk
// Sends notifications at 6 PM (urgency=0) and 9 PM (urgency=1) local time
// See: specs/04-smart-notifications.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";

// Target hours for streak risk notifications (user's local time)
const FIRST_REMINDER_HOUR = 18; // 6 PM - encouraging
const SECOND_REMINDER_HOUR = 21; // 9 PM - warning

interface AtRiskUser {
  user_id: string;
  current_streak_days: number;
  timezone: string;
  push_token: string;
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
    !(await isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey))
  ) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    // Initialize Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const now = new Date();
    const results = {
      firstReminders: 0,
      secondReminders: 0,
      errors: 0,
    };

    // Process first reminder (6 PM local time, urgency=0)
    const { data: firstReminderUsers, error: error1 } = await supabaseAdmin.rpc(
      "get_streak_at_risk_users",
      { p_target_hour: FIRST_REMINDER_HOUR },
    );

    if (error1) {
      console.error("Error fetching 6 PM reminder users:", error1);
    } else if (firstReminderUsers && firstReminderUsers.length > 0) {
      console.log(`Found ${firstReminderUsers.length} users for 6 PM reminder`);

      for (const user of firstReminderUsers as AtRiskUser[]) {
        try {
          const response = await supabaseAdmin.functions.invoke(
            "send-notification",
            {
              body: {
                type: "streak_risk",
                recipientId: user.user_id,
                data: {
                  streak: user.current_streak_days,
                  urgency: 0, // Encouraging message
                  target_hour: FIRST_REMINDER_HOUR,
                },
              },
            },
          );

          if (response.error) {
            console.error(
              "Error sending 6 PM reminder to",
              user.user_id,
              response.error,
            );
            results.errors++;
          } else {
            results.firstReminders++;
          }
        } catch (err) {
          console.error("Exception sending 6 PM reminder:", err);
          results.errors++;
        }
      }
    }

    // Process second reminder (9 PM local time, urgency=1)
    const { data: secondReminderUsers, error: error2 } =
      await supabaseAdmin.rpc("get_streak_at_risk_users", {
        p_target_hour: SECOND_REMINDER_HOUR,
      });

    if (error2) {
      console.error("Error fetching 9 PM reminder users:", error2);
    } else if (secondReminderUsers && secondReminderUsers.length > 0) {
      console.log(
        `Found ${secondReminderUsers.length} users for 9 PM reminder`,
      );

      for (const user of secondReminderUsers as AtRiskUser[]) {
        try {
          const response = await supabaseAdmin.functions.invoke(
            "send-notification",
            {
              body: {
                type: "streak_risk",
                recipientId: user.user_id,
                data: {
                  streak: user.current_streak_days,
                  urgency: 1, // Warning message
                  target_hour: SECOND_REMINDER_HOUR,
                },
              },
            },
          );

          if (response.error) {
            console.error(
              "Error sending 9 PM reminder to",
              user.user_id,
              response.error,
            );
            results.errors++;
          } else {
            results.secondReminders++;
          }
        } catch (err) {
          console.error("Exception sending 9 PM reminder:", err);
          results.errors++;
        }
      }
    }

    console.log("Streak risk check complete:", results);

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: now.toISOString(),
        ...results,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Streak risk check error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
