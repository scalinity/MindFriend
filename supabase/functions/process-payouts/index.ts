import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface PayoutRequest {
  creatorId?: string; // If not provided, process all pending payouts
  periodId?: string;
}

interface CreatorData {
  id: string;
  user_id: string;
  display_name: string;
  stripe_account_id: string;
  payout_enabled: boolean;
  tax_info_complete: boolean;
}

interface EarningsData {
  id: string;
  creator_id: string;
  net_earnings: number;
  payout_status: string;
  period_id: string;
}

interface PeriodData {
  id: string;
  period_month: string;
  status: string;
  total_creator_pool: number;
  total_premium_minutes: number;
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Verify admin authentication
  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  // Check admin role
  const { data: adminCheck } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  if (adminCheck?.role !== "admin") {
    return new Response(JSON.stringify({ error: "Admin access required" }), {
      status: 403,
    });
  }

  const request: PayoutRequest = await req.json();

  try {
    // Get Stripe secret key
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeSecretKey) {
      throw new Error("Stripe is not configured");
    }

    // Get period to process
    let period: PeriodData | null;

    if (request.periodId) {
      const { data: periodData } = (await supabase
        .from("revenue_periods")
        .select("*")
        .eq("id", request.periodId)
        .single()) as unknown as { data: PeriodData | null };
      period = periodData;
    } else {
      // Get the latest finalized period with pending payouts
      const { data: periodData } = (await supabase
        .from("revenue_periods")
        .select("*")
        .eq("status", "finalized")
        .order("period_month", ascending: false)
        .limit(1)
        .single()) as unknown as { data: PeriodData | null };
      period = periodData;
    }

    if (!period) {
      return new Response(
        JSON.stringify({ error: "No finalized period found for payouts" }),
        { status: 400 },
      );
    }

    console.log(`Processing payouts for period: ${period.period_month}`);

    // Get earnings to process
    let earningsQuery = supabase
      .from("creator_earnings")
      .select(
        `
        id,
        creator_id,
        net_earnings,
        payout_status,
        period_id,
        creator:creators!inner(id, user_id, display_name, stripe_account_id, payout_enabled, tax_info_complete)
      `,
      )
      .eq("period_id", period.id)
      .in("payout_status", ["pending", "below_threshold"]);

    if (request.creatorId) {
      earningsQuery = earningsQuery.eq("creator_id", request.creatorId);
    }

    const { data: earnings, error: earningsError } = (await earningsQuery) as unknown as {
      data: (EarningsData & { creator: CreatorData })[];
      error: Error | null;
    };

    if (earningsError) throw earningsError;

    const results: Array<{
      creatorId: string;
      creatorName: string;
      amount: number;
      status: string;
      transferId?: string;
      error?: string;
    }> = [];

    for (const earning of earnings) {
      const creator = earning.creator;

      // Skip if payout not enabled or tax info incomplete
      if (!creator.payout_enabled || !creator.tax_info_complete) {
        results.push({
          creatorId: creator.id,
          creatorName: creator.display_name,
          amount: earning.net_earnings,
          status: "skipped",
          error: creator.payout_enabled
            ? "Tax information incomplete"
            : "Payout not enabled",
        });
        continue;
      }

      // Skip if amount is below minimum ($25)
      if (earning.net_earnings < 25) {
        await supabase
          .from("creator_earnings")
          .update({ payout_status: "below_threshold" })
          .eq("id", earning.id);

        results.push({
          creatorId: creator.id,
          creatorName: creator.display_name,
          amount: earning.net_earnings,
          status: "below_threshold",
        });
        continue;
      }

      // Skip if no Stripe account
      if (!creator.stripe_account_id) {
        results.push({
          creatorId: creator.id,
          creatorName: creator.display_name,
          amount: earning.net_earnings,
          status: "skipped",
          error: "No Stripe account connected",
        });
        continue;
      }

      try {
        // In production, this would make an actual Stripe API call
        // For now, we'll simulate the transfer
        const transferId = `tr_${Date.now()}_${creator.id.slice(0, 8)}`;

        // Simulate Stripe transfer
        // const transfer = await stripe.transfers.create({
        //   amount: Math.round(earning.net_earnings * 100), // Convert to cents
        //   currency: 'usd',
        //   destination: creator.stripe_account_id,
        //   metadata: {
        //     period_id: period.id,
        //     earnings_id: earning.id,
        //   },
        // });

        // Update earnings status
        await supabase
          .from("creator_earnings")
          .update({
            payout_status: "processing",
            payout_id: transferId,
          })
          .eq("id", earning.id);

        results.push({
          creatorId: creator.id,
          creatorName: creator.display_name,
          amount: earning.net_earnings,
          status: "processing",
          transferId,
        });

        console.log(
          `Payout initiated: $${earning.net_earnings} to ${creator.display_name} (${transferId})`,
        );
      } catch (stripeError) {
        // Mark as failed
        await supabase
          .from("creator_earnings")
          .update({ payout_status: "failed" })
          .eq("id", earning.id);

        results.push({
          creatorId: creator.id,
          creatorName: creator.display_name,
          amount: earning.net_earnings,
          status: "failed",
          error: stripeError instanceof Error ? stripeError.message : "Stripe error",
        });

        console.error(
          `Payout failed for ${creator.display_name}:`,
          stripeError,
        );
      }
    }

    // Create payout record
    const totalAmount = results
      .filter((r) => r.status === "processing")
      .reduce((sum, r) => sum + r.amount, 0);

    if (totalAmount > 0) {
      await supabase.from("creator_payouts").insert({
        creator_id: request.creatorId || "bulk",
        amount: totalAmount,
        period_ids: [period.id],
        status: "processing",
      });
    }

    // Update period status
    if (results.some((r) => r.status === "processing")) {
      await supabase
        .from("revenue_periods")
        .update({ status: "paid", paid_at: new Date().toISOString() })
        .eq("id", period.id);
    }

    return new Response(
      JSON.stringify({
        success: true,
        periodId: period.id,
        periodMonth: period.period_month,
        totalPayouts: results.filter((r) => r.status === "processing").length,
        skippedPayouts: results.filter((r) => r.status === "skipped" || r.status === "below_threshold").length,
        failedPayouts: results.filter((r) => r.status === "failed").length,
        totalAmount,
        results,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Payout processing error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
