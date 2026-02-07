// ============================================================================
// B2B Stripe Webhook Handler
// Processes Stripe webhook events for organization billing
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import Stripe from "https://esm.sh/stripe@14.14.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
// Removed TEST_WEBHOOK_BYPASS_AUTH - signature verification must never be bypassed

serve(async (req) => {
  try {
    // Verify webhook signature
    const signature = req.headers.get("stripe-signature");
    if (!signature) {
      return new Response(
        JSON.stringify({ error: "Missing stripe-signature header" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const body = await req.text();
    let event: Stripe.Event;

    // Always verify webhook signature - never bypass in production
    try {
      event = stripe.webhooks.constructEvent(body, signature, webhookSecret);
    } catch (err) {
      console.error("Webhook signature verification failed:", err);
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Route to appropriate handler
    switch (event.type) {
      case "customer.subscription.updated":
        await handleSubscriptionUpdated(event, supabase);
        break;

      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(event, supabase);
        break;

      case "invoice.payment_failed":
        await handlePaymentFailed(event, supabase);
        break;

      case "invoice.paid":
        await handleInvoicePaid(event, supabase);
        break;

      case "invoice.payment_succeeded":
        await handlePaymentSucceeded(event, supabase);
        break;

      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Webhook processing error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

// ============================================================================
// EVENT HANDLERS
// ============================================================================

async function handleSubscriptionUpdated(
  event: Stripe.Event,
  supabase: ReturnType<typeof createClient>,
) {
  const subscription = event.data.object as Stripe.Subscription;
  const organizationId = subscription.metadata?.organization_id;

  if (!organizationId) {
    console.warn("Subscription update missing organization_id in metadata");
    return;
  }

  const newQuantity = subscription.items.data[0]?.quantity || 0;

  // Get current organization data
  const { data: currentOrg } = await supabase
    .from("organizations")
    .select("seat_count")
    .eq("id", organizationId)
    .single();

  const previousQuantity = currentOrg?.seat_count || 0;
  const seatDelta = newQuantity - previousQuantity;

  // Update organization
  const { error: updateError } = await supabase
    .from("organizations")
    .update({
      subscription_status: subscription.status,
      seat_count: newQuantity,
      updated_at: new Date().toISOString(),
    })
    .eq("id", organizationId);

  if (updateError) {
    console.error("Failed to update organization:", updateError);
    throw updateError;
  }

  // Log to billing audit
  await supabase.from("billing_audit_log").insert({
    organization_id: organizationId,
    event_type: "seat_change",
    seat_delta: seatDelta,
    metadata: {
      subscription_id: subscription.id,
      new_quantity: newQuantity,
      previous_quantity: previousQuantity,
      status: subscription.status,
    },
  });

  console.log(
    `Updated organization ${organizationId}: ${previousQuantity} -> ${newQuantity} seats`,
  );
}

async function handleSubscriptionDeleted(
  event: Stripe.Event,
  supabase: ReturnType<typeof createClient>,
) {
  const subscription = event.data.object as Stripe.Subscription;
  const organizationId = subscription.metadata?.organization_id;

  if (!organizationId) {
    console.warn("Subscription deletion missing organization_id in metadata");
    return;
  }

  // Update organization status to churned
  const { error: updateError } = await supabase
    .from("organizations")
    .update({
      status: "churned",
      subscription_status: "canceled",
      updated_at: new Date().toISOString(),
    })
    .eq("id", organizationId);

  if (updateError) {
    console.error("Failed to update organization status:", updateError);
    throw updateError;
  }

  // Revoke premium access for all members
  const { error: subscriptionError } = await supabase
    .from("subscriptions")
    .update({
      tier: "free",
      organization_id: null,
      access_source: null,
      ended_at: new Date().toISOString(),
    })
    .eq("organization_id", organizationId)
    .eq("access_source", "organization_sponsored");

  if (subscriptionError) {
    console.error("Failed to revoke member subscriptions:", subscriptionError);
  }

  // Log to billing audit
  await supabase.from("billing_audit_log").insert({
    organization_id: organizationId,
    event_type: "subscription_canceled",
    message: "Subscription canceled by Stripe",
    metadata: {
      subscription_id: subscription.id,
      canceled_at: subscription.canceled_at
        ? new Date(subscription.canceled_at * 1000).toISOString()
        : null,
    },
  });

  console.log(`Organization ${organizationId} subscription canceled`);
}

async function handlePaymentFailed(
  event: Stripe.Event,
  supabase: ReturnType<typeof createClient>,
) {
  const invoice = event.data.object as Stripe.Invoice;
  const organizationId = invoice.metadata?.organization_id;

  if (!organizationId) {
    console.warn("Payment failure missing organization_id in metadata");
    return;
  }

  // Set 7-day grace period
  const gracePeriodEnd = new Date();
  gracePeriodEnd.setDate(gracePeriodEnd.getDate() + 7);

  // Update organization to past_due status
  const { error: updateError } = await supabase
    .from("organizations")
    .update({
      status: "past_due",
      subscription_status: "past_due",
      grace_period_ends_at: gracePeriodEnd.toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", organizationId);

  if (updateError) {
    console.error("Failed to update organization to past_due:", updateError);
    throw updateError;
  }

  // Log to billing audit
  await supabase.from("billing_audit_log").insert({
    organization_id: organizationId,
    event_type: "payment_failed",
    message: `Payment failed for invoice ${invoice.id}`,
    metadata: {
      invoice_id: invoice.id,
      amount_due: invoice.amount_due,
      attempt_count: invoice.attempt_count,
      grace_period_ends_at: gracePeriodEnd.toISOString(),
    },
  });

  // TODO: Send email notification to billing_email
  console.log(
    `Organization ${organizationId} payment failed, grace period until ${gracePeriodEnd}`,
  );
}

async function handleInvoicePaid(
  event: Stripe.Event,
  supabase: ReturnType<typeof createClient>,
) {
  const invoice = event.data.object as Stripe.Invoice;
  const organizationId = invoice.metadata?.organization_id;

  if (!organizationId) {
    console.warn("Invoice paid missing organization_id in metadata");
    return;
  }

  // Determine if this is a renewal
  const isRenewal = invoice.billing_reason === "subscription_cycle";
  const eventType = isRenewal ? "renewal" : "payment_received";

  // Log to billing audit
  await supabase.from("billing_audit_log").insert({
    organization_id: organizationId,
    event_type: eventType,
    message: `Invoice ${invoice.id} paid: $${(invoice.amount_paid / 100).toFixed(2)}`,
    metadata: {
      invoice_id: invoice.id,
      amount_paid: invoice.amount_paid,
      billing_reason: invoice.billing_reason,
      subscription_id: invoice.subscription,
    },
  });

  console.log(
    `Organization ${organizationId} invoice ${invoice.id} paid: $${(invoice.amount_paid / 100).toFixed(2)}`,
  );
}

async function handlePaymentSucceeded(
  event: Stripe.Event,
  supabase: ReturnType<typeof createClient>,
) {
  const invoice = event.data.object as Stripe.Invoice;
  const organizationId = invoice.metadata?.organization_id;

  if (!organizationId) {
    console.warn("Payment success missing organization_id in metadata");
    return;
  }

  // Clear past_due status if it exists
  const { error: updateError } = await supabase
    .from("organizations")
    .update({
      status: "active",
      subscription_status: "active",
      grace_period_ends_at: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", organizationId)
    .in("status", ["past_due", "inactive"]);

  if (updateError) {
    console.error("Failed to update organization status:", updateError);
  }

  // Log to billing audit
  await supabase.from("billing_audit_log").insert({
    organization_id: organizationId,
    event_type: "payment_succeeded",
    message: `Payment succeeded for invoice ${invoice.id}`,
    metadata: {
      invoice_id: invoice.id,
      amount_paid: invoice.amount_paid,
    },
  });

  console.log(`Organization ${organizationId} payment succeeded`);
}
