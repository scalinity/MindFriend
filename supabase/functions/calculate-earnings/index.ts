import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface CalculateRequest {
  periodMonth: string; // YYYY-MM
}

interface CreatorMinutesMap {
  [creatorId: string]: number;
}

interface EngagementRecord {
  content_id: string;
  duration_seconds: number | null;
  completion_percentage: number | null;
  creator_content: {
    creator_id: string;
  };
}

function getRevenueShareRate(verificationLevel: string): number {
  switch (verificationLevel) {
    case "partner":
      return 0.7;
    case "expert":
      return 0.65;
    case "verified":
      return 0.6;
    default:
      return 0.6;
  }
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Authenticate request - must be admin or authorized cron job
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization header" }),
      { status: 401 },
    );
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  // Verify user is admin (check admin flag in profiles table)
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("is_admin")
    .eq("id", user.id)
    .single();

  if (profileError || !profile?.is_admin) {
    return new Response(
      JSON.stringify({ error: "Only admins can calculate earnings" }),
      { status: 403 },
    );
  }

  const { periodMonth }: CalculateRequest = await req.json();

  try {
    // Validate period format
    if (!periodMonth.match(/^\d{4}-\d{2}$/)) {
      return new Response(
        JSON.stringify({ error: "Invalid period format. Use YYYY-MM" }),
        { status: 400 },
      );
    }

    // Get or create period
    let { data: period, error: periodFetchError } = await supabase
      .from("revenue_periods")
      .select("*")
      .eq("period_month", periodMonth)
      .single();

    if (periodFetchError && periodFetchError.code !== "PGRST116") {
      throw periodFetchError;
    }

    if (!period) {
      const [year, month] = periodMonth.split("-").map(Number);
      const periodStart = new Date(year, month - 1, 1);
      const periodEnd = new Date(year, month, 0);

      const { data: newPeriod, error: createError } = await supabase
        .from("revenue_periods")
        .insert({
          period_month: periodMonth,
          period_start: periodStart.toISOString().split("T")[0],
          period_end: periodEnd.toISOString().split("T")[0],
          status: "calculating",
        })
        .select()
        .single();

      if (createError) throw createError;
      period = newPeriod;
    }

    // Update status to calculating
    await supabase
      .from("revenue_periods")
      .update({ status: "calculating" })
      .eq("id", period.id);

    // Get engagement by creator
    const { data: engagementData, error: engagementError } = (await supabase
      .from("content_engagement")
      .select(
        `
        content_id,
        duration_seconds,
        completion_percentage,
        creator_content!inner(creator_id)
      `,
      )
      .eq("engagement_month", periodMonth)
      .eq("user_is_premium", true)) as unknown as {
      data: EngagementRecord[] | null;
      error: Error | null;
    };

    if (engagementError) throw engagementError;

    // Aggregate by creator with tiered completion weighting (per spec)
    // Tiers: 0-25%: 0.25x, 25-50%: 0.50x, 50-75%: 0.75x, 75-100%: 1.0x
    const creatorMinutes: CreatorMinutesMap = {};
    let totalMinutes = 0;

    for (const engagement of engagementData || []) {
      const creatorId = engagement.creator_content.creator_id;
      const completionPercent = engagement.completion_percentage || 0;

      // Apply tiered weighting based on completion percentage
      let weight: number;
      if (completionPercent < 25) {
        weight = 0.25;
      } else if (completionPercent < 50) {
        weight = 0.5;
      } else if (completionPercent < 75) {
        weight = 0.75;
      } else {
        weight = 1.0;
      }

      const minutes = ((engagement.duration_seconds || 0) / 60) * weight;

      creatorMinutes[creatorId] = (creatorMinutes[creatorId] || 0) + minutes;
      totalMinutes += minutes;
    }

    // Stub subscription revenue calculation
    // In production, this would sum actual subscription revenue for the period
    const totalSubscriptionRevenue = 50000; // Placeholder
    const creatorPool = totalSubscriptionRevenue * 0.3; // 30% to creators

    // Update period totals
    const { error: updatePeriodError } = await supabase
      .from("revenue_periods")
      .update({
        total_subscription_revenue: totalSubscriptionRevenue,
        total_creator_pool: creatorPool,
        total_premium_minutes: Math.round(totalMinutes),
        status: "calculating",
      })
      .eq("id", period.id);

    if (updatePeriodError) throw updatePeriodError;

    // Batch-fetch all creators' verification levels to avoid N+1 queries
    const creatorIds = Object.keys(creatorMinutes);
    const { data: creators, error: creatorsError } = await supabase
      .from("creators")
      .select("id, verification_level")
      .in("id", creatorIds);

    if (creatorsError) throw creatorsError;

    // Map creator data by ID for O(1) lookup
    const creatorMap = new Map((creators || []).map((c) => [c.id, c]));

    // Calculate each creator's earnings
    let earningsCount = 0;
    for (const [creatorId, minutes] of Object.entries(creatorMinutes)) {
      const sharePercentage = totalMinutes > 0 ? minutes / totalMinutes : 0;
      const grossEarnings = creatorPool * sharePercentage;

      // Get creator's revenue share rate from batch-fetched data
      const creator = creatorMap.get(creatorId);
      if (!creator) {
        console.error(`Creator ${creatorId} not found in batch fetch`);
        continue;
      }

      const revenueShareRate = getRevenueShareRate(creator?.verification_level);
      const platformFee = grossEarnings * (1 - revenueShareRate);
      const netEarnings = grossEarnings - platformFee;

      // Upsert creator earnings
      const { error: earningsError } = await supabase
        .from("creator_earnings")
        .upsert(
          {
            creator_id: creatorId,
            period_id: period.id,
            total_minutes: Math.round(minutes),
            premium_minutes: Math.round(minutes),
            share_percentage: sharePercentage,
            gross_earnings: grossEarnings,
            platform_fee: platformFee,
            net_earnings: netEarnings,
            payout_status: netEarnings >= 25 ? "pending" : "below_threshold",
          },
          {
            onConflict: "creator_id,period_id",
          },
        );

      if (earningsError) {
        console.error(
          `Error updating earnings for creator ${creatorId}:`,
          earningsError,
        );
        continue;
      }

      earningsCount++;
    }

    // Finalize period
    const { error: finalizeError } = await supabase
      .from("revenue_periods")
      .update({
        status: "finalized",
        finalized_at: new Date().toISOString(),
      })
      .eq("id", period.id);

    if (finalizeError) throw finalizeError;

    console.log(
      `Earnings calculated for period ${periodMonth}: ${earningsCount} creators`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        periodId: period.id,
        periodMonth: periodMonth,
        totalCreatorPool: creatorPool,
        creatorsCalculated: earningsCount,
        totalMinutes: Math.round(totalMinutes),
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Earnings calculation error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
