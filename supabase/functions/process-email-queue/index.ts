import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { timingSafeEqual } from "https://esm.sh/@supabase/email-utils";

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

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sendEmailUrl = Deno.env.get("SEND_EMAIL_URL") ||
  `${supabaseUrl}/functions/v1/send-email`;

serve(async (req: Request) => {
  // Only accept POST requests
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Validate CRON_SECRET to prevent unauthorized access
  const cronSecret = Deno.env.get("CRON_SECRET");
  const authHeader = req.headers.get("X-Cron-Secret");
  
  if (!cronSecret || !timingSafeEqual(cronSecret, authHeader)) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const workerId = `worker-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;

    // Clean up stale locks before claiming new batch
    console.log("Cleaning up stale locks...");
    const { data: cleanupResult, error: cleanupError } = await supabase.rpc(
      "cleanup_stale_locks",
      { p_lock_timeout_minutes: 10 }
    );

    if (cleanupError) {
      console.error("Stale lock cleanup error:", cleanupError);
      // Don't fail processing on cleanup error, just log it
    } else {
      console.log(`Cleanup released ${cleanupResult} stale locks`);
    }

    // Claim batch of emails for processing
    // Claim batch of pending emails using RPC function with FOR UPDATE SKIP LOCKED
    // This ensures concurrent safety - each worker gets unique batch
    const { data: queueItems, error: claimError } = await supabase.rpc(
      "claim_emails_for_processing",
      {
        p_worker_id: workerId,
        p_batch_size: 50, // Process 50 emails per batch
      },
    );

    if (claimError) {
      console.error("Error claiming emails:", claimError);
      return new Response(
        JSON.stringify({
          error: `Failed to claim emails: ${claimError.message}`,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const batch = queueItems as EmailQueueItem[];

    if (!batch || batch.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No pending emails to process",
          processedCount: 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(
      `Worker ${workerId} claimed ${batch.length} emails for processing`,
    );

    // Process claimed batch in parallel instead of sequentially
    const sendPromises = batch.map((item: any) =>
      fetch(sendEmailUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Cron-Secret": cronSecret,
        },
        body: JSON.stringify({ queueItemId: item.id }),
      })
        .then((res) => res.json())
        .then((data) => ({
          queueItemId: item.id,
          success: true,
          data,
        }))
        .catch((error) => ({
          queueItemId: item.id,
          success: false,
          error: String(error),
        }))
    );

    const results = await Promise.allSettled(sendPromises);
    
    let successCount = 0;
    let failureCount = 0;
    
    for (const result of results) {
      if (result.status === "fulfilled") {
        if (result.value.success) {
          successCount++;
        } else {
          failureCount++;
          console.error(
            `Email send failed for queue item ${result.value.queueItemId}:`,
            result.value.error
          );
        }
      } else {
        failureCount++;
        console.error("Email send promise rejected:", result.reason);
      }
    }

    // Release lock by marking processing emails as sent (if successful) or pending (if failed)
    // This is done implicitly by send-email function
    console.log(
      `Worker ${workerId} completed: ${successCount} sent, ${failureCount} failed`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        workerId,
        claimedCount: batch.length,
        processedCount: successCount + failureCount,
        successCount,
        failureCount,
        results,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Unexpected error in process-email-queue:", error);
    return new Response(
      JSON.stringify({
        error: `Unexpected error: ${String(error)}`,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
