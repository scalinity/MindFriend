/**
 * aggregate-interaction-metrics Edge Function
 *
 * Scheduled: Daily at 00:00 UTC (cron job, before score calculation)
 * Purpose: Aggregate circle interaction data into daily metrics
 *
 * Algorithm:
 * 1. Fetch all circle_posts from past 24 hours
 * 2. Group by (user_id, other_user_id, circle_id, date)
 * 3. Calculate metrics:
 *    - messages_sent/received count
 *    - avg_message_length (character count)
 *    - avg_response_time_minutes (time between consecutive messages)
 * 4. Upsert to interaction_metrics table
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// Type definitions
interface CirclePost {
  id: string;
  circle_id: string;
  user_id: string;
  body_text: string;
  created_at: string;
}

interface InteractionMetric {
  user_id: string;
  other_user_id: string;
  circle_id: string;
  date: string;
  messages_sent: number;
  messages_received: number;
  avg_message_length: number | null;
  avg_response_time_minutes: number | null;
}

interface AggregationResult {
  success: boolean;
  processed: number;
  metricsCreated: number;
  error?: string;
}

serve(async (req) => {
  try {
    // Initialize Supabase client with service role key
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    console.log(
      "[aggregate-interaction-metrics] Starting daily aggregation...",
    );

    // Calculate yesterday's date (process completed day)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split("T")[0];

    // Calculate today's date for exclusive upper bound
    const today = new Date();
    const todayStr = today.toISOString().split("T")[0];

    // Fetch all circle posts from yesterday
    const { data: posts, error: postsError } = await supabase
      .from("circle_posts")
      .select("id, circle_id, user_id, body_text, created_at")
      .gte("created_at", `${yesterdayStr}T00:00:00Z`)
      .lt("created_at", `${todayStr}T00:00:00Z`)  // Exclusive upper bound
      .order("created_at", { ascending: true });

    if (postsError) {
      console.error(
        "[aggregate-interaction-metrics] Error fetching posts:",
        postsError,
      );
      return new Response(
        JSON.stringify({ success: false, error: postsError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(
      `[aggregate-interaction-metrics] Processing ${posts?.length || 0} posts from ${yesterdayStr}`,
    );

    if (!posts || posts.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          processed: 0,
          metricsCreated: 0,
          message: "No posts to process",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    // Get all circle memberships to determine interactions
    const circleIds = [...new Set(posts.map((p) => p.circle_id))];
    const { data: memberships, error: membershipsError } = await supabase
      .from("circle_members")
      .select("circle_id, user_id")
      .in("circle_id", circleIds);

    if (membershipsError) {
      throw new Error(
        `Failed to fetch memberships: ${membershipsError.message}`,
      );
    }

    // Group memberships by circle for quick lookup
    const circleMembers = new Map<string, Set<string>>();
    for (const membership of memberships || []) {
      if (!circleMembers.has(membership.circle_id)) {
        circleMembers.set(membership.circle_id, new Set());
      }
      circleMembers.get(membership.circle_id)!.add(membership.user_id);
    }

    // Aggregate metrics
    const metrics = await aggregateMetrics(posts, circleMembers, yesterdayStr);

    // Batch upsert metrics
    let metricsCreated = 0;
    const batchSize = 100;
    for (let i = 0; i < metrics.length; i += batchSize) {
      const batch = metrics.slice(i, i + batchSize);
      const { error: upsertError } = await supabase
        .from("interaction_metrics")
        .upsert(batch, {
          onConflict: "user_id,other_user_id,circle_id,date",
        });

      if (upsertError) {
        console.error(
          `[aggregate-interaction-metrics] Batch upsert error:`,
          upsertError,
        );
        throw new Error(`Failed to upsert metrics: ${upsertError.message}`);
      }

      metricsCreated += batch.length;
    }

    console.log(
      `[aggregate-interaction-metrics] Completed: ${metricsCreated} metrics created`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        processed: posts.length,
        metricsCreated,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("[aggregate-interaction-metrics] Fatal error:", error);
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

/**
 * Aggregate circle posts into interaction metrics
 */
function aggregateMetrics(
  posts: CirclePost[],
  circleMembers: Map<string, Set<string>>,
  date: string,
): InteractionMetric[] {
  // Group posts by circle
  const postsByCircle = new Map<string, CirclePost[]>();
  for (const post of posts) {
    if (!postsByCircle.has(post.circle_id)) {
      postsByCircle.set(post.circle_id, []);
    }
    postsByCircle.get(post.circle_id)!.push(post);
  }

  const metrics: InteractionMetric[] = [];

  // Process each circle
  for (const [circleId, circlePosts] of postsByCircle.entries()) {
    const members = circleMembers.get(circleId);
    if (!members) continue;

    // For each member, calculate metrics with every other member
    for (const userId of members) {
      const userPosts = circlePosts.filter((p) => p.user_id === userId);

      for (const otherUserId of members) {
        if (userId === otherUserId) continue;

        const otherUserPosts = circlePosts.filter(
          (p) => p.user_id === otherUserId,
        );

        // Calculate metrics
        const messagesSent = userPosts.length;
        const messagesReceived = otherUserPosts.length;

        // Skip if no interaction
        if (messagesSent === 0 && messagesReceived === 0) continue;

        // Calculate average message length
        let avgMessageLength: number | null = null;
        if (messagesSent > 0) {
          const totalLength = userPosts.reduce(
            (sum, p) => sum + (p.body_text?.length || 0),
            0,
          );
          avgMessageLength = Math.round(totalLength / messagesSent);
        }

        // Calculate average response time
        let avgResponseTime: number | null = null;
        const responseTimes: number[] = [];

        // Sort all posts in circle by time
        const allPosts = [...circlePosts].sort(
          (a, b) =>
            new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
        );

        // For each post by userId, find the most recent post from otherUserId before it
        for (const userPost of allPosts.filter(p => p.user_id === userId)) {
          const userPostTime = new Date(userPost.created_at).getTime();
          
          // Find the most recent post from otherUserId before this userPost
          let mostRecentOtherPost = null;
          let mostRecentOtherTime = 0;
          
          for (const otherPost of allPosts) {
            if (otherPost.user_id !== otherUserId) continue;
            
            const otherPostTime = new Date(otherPost.created_at).getTime();
            if (otherPostTime < userPostTime && otherPostTime > mostRecentOtherTime) {
              mostRecentOtherPost = otherPost;
              mostRecentOtherTime = otherPostTime;
            }
          }
          
          // If found, calculate response time
          if (mostRecentOtherPost) {
            const responseTimeMs = userPostTime - mostRecentOtherTime;
            responseTimes.push(responseTimeMs / 1000 / 60); // Convert to minutes
          }
        }

        if (responseTimes.length > 0) {
          avgResponseTime = Math.round(
            responseTimes.reduce((sum, rt) => sum + rt, 0) /
              responseTimes.length,
          );
        }

        metrics.push({
          user_id: userId,
          other_user_id: otherUserId,
          circle_id: circleId,
          date,
          messages_sent: messagesSent,
          messages_received: messagesReceived,
          avg_message_length: avgMessageLength,
          avg_response_time_minutes: avgResponseTime,
        });
      }
    }
  }

  return metrics;
}
