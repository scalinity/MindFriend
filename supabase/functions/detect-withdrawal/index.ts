/**
 * detect-withdrawal Edge Function
 *
 * Scheduled: Daily at 00:10 UTC (cron job, after score calculation)
 * Purpose: Detect social withdrawal patterns and trigger peer support alerts
 *
 * Algorithm:
 * 1. Fetch users with 14+ days of scores
 * 2. Calculate decline: older_avg (D-8 to D-14) vs recent_avg (D-1 to D-7)
 * 3. Check if consistently declining (monotonically non-increasing)
 * 4. Classify severity: moderate (15-25 point decline) or severe (25+ points)
 * 5. If severe + should_alert, call send-peer-alert function
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// Type definitions
interface WithdrawalStatus {
  severity: "moderate" | "severe";
  declinePercent: number;
  daysSincePeak: number;
  shouldAlert: boolean;
}

interface DetectionResult {
  userId: string;
  status: WithdrawalStatus | null;
  alertSent: boolean;
  error?: string;
}

serve(async (req) => {
  try {
    // Initialize Supabase client with service role key
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    console.log("[detect-withdrawal] Starting daily withdrawal detection...");

    // Fetch users with 14+ days of scores
    const { data: users, error: usersError } = await supabase.rpc(
      "get_users_with_scores",
      { p_min_days: 14 },
    );

    if (usersError) {
      console.error("[detect-withdrawal] Error fetching users:", usersError);
      return new Response(
        JSON.stringify({ success: false, error: usersError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(`[detect-withdrawal] Analyzing ${users?.length || 0} users...`);

    // OPTIMIZATION: Batch fetch all scores from past 14 days
    const fourteenDaysAgo = new Date();
    fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);
    
    const { data: allScores, error: scoresError } = await supabase
      .from("social_vitality_scores")
      .select("user_id, overall_score, date")
      .gte("date", fourteenDaysAgo.toISOString().split("T")[0])
      .order("user_id, date", { ascending: true });

    if (scoresError) {
      console.error("[detect-withdrawal] Error fetching scores:", scoresError);
      return new Response(
        JSON.stringify({ success: false, error: scoresError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // Group scores by user_id
    const scoresByUser = new Map<string, any[]>();
    for (const score of allScores || []) {
      if (!scoresByUser.has(score.user_id)) {
        scoresByUser.set(score.user_id, []);
      }
      scoresByUser.get(score.user_id)!.push(score);
    }

    // Process each user with pre-fetched data
    const results: DetectionResult[] = [];
    const detectionsToUpsert: any[] = [];

    for (const user of users || []) {
      const userScores = scoresByUser.get(user.user_id) || [];
      const result = await detectWithdrawalForUser(user.user_id, userScores);
      results.push(result);

      if (result.status) {
        detectionsToUpsert.push({
          user_id: user.user_id,
          date: new Date().toISOString().split("T")[0],
          severity: result.status.severity,
          decline_percent: result.status.declinePercent,
          days_since_peak: result.status.daysSincePeak,
          should_alert: result.status.shouldAlert,
          alert_sent: false,
        });
      }

      // If severe withdrawal detected and should alert, send peer alerts
      if (result.status?.shouldAlert && !result.error) {
        const alertSent = await sendPeerAlert(supabase, user.user_id, result.status);
        result.alertSent = alertSent;
      }
    }

    // OPTIMIZATION: Batch upsert all detections
    if (detectionsToUpsert.length > 0) {
      const { error: upsertError } = await supabase
        .from("withdrawal_detections")
        .upsert(detectionsToUpsert, {
          onConflict: "user_id,date",
        });

      if (upsertError) {
        console.error("[detect-withdrawal] Batch upsert error:", upsertError);
      }
    }

    const withdrawalsDetected = results.filter((r) => r.status !== null).length;
    const alertsSent = results.filter((r) => r.alertSent).length;

    console.log(
      `[detect-withdrawal] Completed: ${withdrawalsDetected} withdrawals detected, ${alertsSent} alerts sent`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        analyzed: results.length,
        withdrawalsDetected,
        alertsSent,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("[detect-withdrawal] Fatal error:", error);
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

/**
 * Detect withdrawal pattern for a single user (optimized with pre-fetched scores)
 */
async function detectWithdrawalForUser(
  userId: string,
  scores: any[],
): Promise<DetectionResult> {
  try {
    if (!scores || scores.length < 7) {
      return { userId, status: null, alertSent: false }; // Insufficient data
    }

    // Split into recent (last 7 days) and older (first 7 days)
    const recentScores = scores.slice(-7).map((s: any) => s.overall_score);
    const olderScores = scores.slice(0, 7).map((s: any) => s.overall_score);

    // Calculate averages
    const recentAvg =
      recentScores.reduce((sum: number, s: number) => sum + s, 0) /
      recentScores.length;
    const olderAvg =
      olderScores.reduce((sum: number, s: number) => sum + s, 0) /
      olderScores.length;
    const decline = olderAvg - recentAvg;

    // P2 FIX: Check if consistently declining (strict: each day < previous day, not <=)
    // This prevents flat scores from being flagged as "declining"
    const isConsistentlyDeclining = recentScores.every(
      (score: number, i: number) => i === 0 || score < recentScores[i - 1],
    );

    if (!isConsistentlyDeclining) {
      return { userId, status: null, alertSent: false }; // Not consistently declining
    }

    // Classify severity
    let severity: "moderate" | "severe" | null = null;
    let shouldAlert = false;

    if (decline > 25) {
      severity = "severe";
      shouldAlert = true;
    } else if (decline > 15) {
      severity = "moderate";
      shouldAlert = false;
    } else {
      return { userId, status: null, alertSent: false }; // Decline not significant enough
    }

    // Calculate days since peak
    const allScores = scores.map((s: any) => s.overall_score);
    const maxScore = Math.max(...allScores);
    const peakIndex = allScores.indexOf(maxScore);
    const daysSincePeak = allScores.length - peakIndex - 1;

    const status: WithdrawalStatus = {
      severity,
      declinePercent: Math.floor((decline / olderAvg) * 100),
      daysSincePeak,
      shouldAlert,
    };

    return { userId, status, alertSent: false };
  } catch (error) {
    return { userId, status: null, alertSent: false, error: String(error) };
  }
}

/**
 * Send peer support alerts for a user in withdrawal
 */
async function sendPeerAlert(
  supabase: any,
  userId: string,
  status: WithdrawalStatus,
): Promise<boolean> {
  try {
    // Check if user has opted in to peer alerts
    const { data: preferences, error: prefError } = await supabase
      .from("peer_alert_preferences")
      .select("*")
      .eq("user_id", userId)
      .single();

    if (prefError || !preferences || !preferences.enabled) {
      console.log(
        `[detect-withdrawal] User ${userId}: Peer alerts not enabled`,
      );
      return false;
    }

    // Check if severity meets threshold
    if (
      status.severity === "moderate" &&
      preferences.alert_threshold === "severe"
    ) {
      console.log(
        `[detect-withdrawal] User ${userId}: Severity below threshold`,
      );
      return false;
    }

    // Check rate limit (max 1 alert per 7 days)
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const { data: recentAlerts, error: alertsError } = await supabase
      .from("peer_alerts")
      .select("created_at")
      .eq("user_id", userId)
      .gte("created_at", sevenDaysAgo.toISOString())
      .limit(1);

    if (alertsError) {
      throw new Error(
        `Failed to check alert rate limit: ${alertsError.message}`,
      );
    }

    if (recentAlerts && recentAlerts.length > 0) {
      console.log(
        `[detect-withdrawal] User ${userId}: Rate limit exceeded (last alert within 7 days)`,
      );
      return false;
    }

    // SECURITY FIX: Generic message without PII
    const message = "A friend in your support circle might appreciate hearing from you today. A quick message could brighten their day. 💙";

    // Send alerts to each designated supporter (max 3)
    const supporters = preferences.designated_supporters || [];
    let alertsSent = 0;

    for (const supporterId of supporters) {
      // Check if supporter has consented
      const { data: consent, error: consentError } = await supabase
        .from("peer_support_consent")
        .select("accepted")
        .eq("supporter_id", supporterId)
        .eq("requesting_user_id", userId)
        .single();

      if (consentError || !consent || !consent.accepted) {
        console.log(
          `[detect-withdrawal] Supporter ${supporterId}: Consent not granted`,
        );
        continue;
      }

      // Call send-notification function with retry logic
      try {
        const notificationSent = await retryWithBackoff(async () => {
          const { data, error: notificationError } = await supabase.functions.invoke(
            "send-notification",
            {
              body: {
                user_id: supporterId,
                title: "A Friend Could Use Support",
                body: message,
                category: "peer_support",
                payload: { alert_type: "withdrawal_detected" }, // SECURITY: No user_id in payload
              },
            },
          );

          // P1 FIX: Check both error field AND HTTP response status
          if (notificationError) {
            throw new Error(`Notification failed: ${notificationError.message}`);
          }
          
          // Check if response indicates success (data should be truthy for successful notification)
          if (!data || (data as any).success === false) {
            throw new Error(`Notification delivery failed: ${JSON.stringify(data)}`);
          }
          
          return true;
        }, 3);

        if (notificationSent) {
          // Log alert in database
          await supabase.from("peer_alerts").insert({
            user_id: userId,
            supporter_id: supporterId,
            alert_type: "withdrawal_detected",
            message,
            acknowledged: false,
            delivery_failed: false,
          });

          alertsSent++;
          console.log(
            `[detect-withdrawal] Alert sent to supporter ${supporterId}`,
          );
        }
      } catch (error) {
        // Log delivery failure but continue to next supporter
        console.error(
          `[detect-withdrawal] Failed to send alert to ${supporterId}:`,
          error,
        );

        await supabase.from("peer_alerts").insert({
          user_id: userId,
          supporter_id: supporterId,
          alert_type: "withdrawal_detected",
          message,
          acknowledged: false,
          delivery_failed: true,
        });
      }
    }

    // Mark withdrawal detection as alert_sent
    if (alertsSent > 0) {
      await supabase
        .from("withdrawal_detections")
        .update({ alert_sent: true })
        .eq("user_id", userId)
        .eq("date", new Date().toISOString().split("T")[0]);
    }

    console.log(
      `[detect-withdrawal] User ${userId}: Sent ${alertsSent} alerts to supporters`,
    );

    return alertsSent > 0;
  } catch (error) {
    console.error(
      `[detect-withdrawal] Error sending peer alerts for ${userId}:`,
      error,
    );
    return false;
  }
}

/**
 * Retry function with exponential backoff
 */
async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxRetries: number,
  baseDelayMs: number = 1000,
): Promise<T> {
  let lastError: Error;
  
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;
      
      if (attempt < maxRetries - 1) {
        const delay = baseDelayMs * Math.pow(2, attempt);
        console.log(`Retry attempt ${attempt + 1}/${maxRetries} after ${delay}ms`);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  
  throw lastError!;
}
