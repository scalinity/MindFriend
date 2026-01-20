# Stripe B2B Configuration Guide

This document describes the Stripe product and pricing configuration required for the MindFriend Workplace Wellness (B2B) module.

## Product Setup

### 1. MindFriend Business

**Product Configuration:**

- **Product Name:** MindFriend Business
- **Description:** Mental wellness platform for organizations (10-100 employees)
- **Statement Descriptor:** MINDFRIEND BUSINESS

**Pricing:**

| SKU                      | Type      | Price       | Billing Cycle | Seats  |
| ------------------------ | --------- | ----------- | ------------- | ------ |
| `price_business_monthly` | Recurring | $8/seat/mo  | Monthly       | 10-100 |
| `price_business_annual`  | Recurring | $80/seat/yr | Annual        | 10-100 |

**Pricing Configuration Details:**

```javascript
// Monthly Plan
{
  unit_amount: 800, // $8.00 in cents
  currency: "usd",
  recurring: {
    interval: "month",
    usage_type: "licensed"
  },
  billing_scheme: "per_unit",
  tiers_mode: null,
  metadata: {
    plan: "business",
    min_seats: "10",
    max_seats: "100"
  }
}

// Annual Plan
{
  unit_amount: 8000, // $80.00 in cents
  currency: "usd",
  recurring: {
    interval: "year",
    usage_type: "licensed"
  },
  billing_scheme: "per_unit",
  metadata: {
    plan: "business",
    min_seats: "10",
    max_seats: "100",
    discount_vs_monthly: "16.7%" // $96/yr vs $80/yr
  }
}
```

### 2. MindFriend Enterprise

**Product Configuration:**

- **Product Name:** MindFriend Enterprise
- **Description:** Mental wellness platform for large organizations (100+ employees)
- **Statement Descriptor:** MINDFRIEND ENTERPRISE

**Pricing:**

| SKU                       | Type      | Price  | Billing Cycle | Seats |
| ------------------------- | --------- | ------ | ------------- | ----- |
| `price_enterprise_custom` | Recurring | Custom | Annual        | 100+  |

**Pricing Configuration Details:**

```javascript
{
  unit_amount: null, // Custom pricing per contract
  currency: "usd",
  recurring: {
    interval: "year",
    usage_type: "licensed"
  },
  billing_scheme: "per_unit",
  metadata: {
    plan: "enterprise",
    min_seats: "100",
    requires_sales: "true"
  }
}
```

## Subscription Metadata

Every subscription must include `organization_id` in metadata for webhook processing:

```javascript
stripe.subscriptions.create({
  customer: customerId,
  items: [
    {
      price: "price_business_monthly",
      quantity: seatCount,
    },
  ],
  metadata: {
    organization_id: "uuid-from-supabase", // REQUIRED
    organization_name: "Acme Corp",
    plan_type: "business",
  },
});
```

## Metered Billing Configuration

Subscriptions use **quantity-based metered billing** to track seat usage:

```javascript
stripe.subscriptions.update(subscriptionId, {
  items: [
    {
      id: subscriptionItemId,
      quantity: newSeatCount, // Updated seat count
      billing_thresholds: {
        usage_gte: newSeatCount + 5, // Alert if usage exceeds by 5
      },
    },
  ],
  proration_behavior: "create_prorations", // Prorate mid-cycle changes
});
```

## Webhook Configuration

### Required Webhook Events

Configure webhook endpoint: `https://www.mindfriend.app/webhooks/stripe`

**Events to enable:**

- `customer.subscription.updated` - Seat count changes, status updates
- `customer.subscription.deleted` - Subscription cancellation
- `invoice.payment_failed` - Payment failures (triggers grace period)
- `invoice.payment_succeeded` - Payment success (clears grace period)
- `invoice.paid` - Renewal tracking

### Webhook Secret

Store webhook signing secret in environment variables:

```bash
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxx
```

## Customer Creation

When creating an organization, create a Stripe customer with metadata:

```javascript
const customer = await stripe.customers.create({
  email: billingEmail,
  name: organizationName,
  metadata: {
    organization_id: organizationId,
    plan: "business",
    created_via: "mindfriend_admin_portal",
  },
  invoice_settings: {
    default_payment_method: paymentMethodId,
  },
});
```

## Proration Behavior

**Mid-Cycle Seat Additions:**

When adding seats mid-cycle, Stripe automatically:

1. Calculates prorated charge for remaining billing period
2. Creates an invoice item for the proration
3. Charges immediately (if `proration_behavior: "create_prorations"`)

**Example:**

- Current: 50 seats @ $8/mo = $400/mo
- Add: 10 seats on day 15 of 30-day month
- Proration: 10 seats × $8 × (15/30 days) = $40
- New monthly charge: 60 seats × $8 = $480/mo

## Nightly Reconciliation

A nightly cron job (4:00 AM UTC) reconciles Stripe seat count with actual organization members:

```sql
-- SQL migration: supabase/migrations/20260119100200_stripe_reconciliation_cron.sql
SELECT cron.schedule(
  'reconcile_stripe_seats_nightly',
  '0 4 * * *',
  $$
    -- Update Stripe subscriptions to match actual member counts
    -- See spec section 5.2.3 for full implementation
  $$
);
```

## Payment Failure Flow

**Grace Period:** 7 days

**Timeline:**

1. **Day 0:** Payment fails → `invoice.payment_failed` webhook
2. **System action:** Update `organizations.status` to `past_due`, set `grace_period_ends_at`
3. **Day 1-7:** Email reminders sent to `billing_email`
4. **Day 7:** Cron job checks `grace_period_ends_at`, disables access if unpaid

**Status transitions:**

```
active → payment fails → past_due → grace period expires → inactive
active → payment succeeds (within grace) → active (restored)
```

## Subscription Status Mapping

| Stripe Status | Organization Status | Member Access | Action                           |
| ------------- | ------------------- | ------------- | -------------------------------- |
| `active`      | `active`            | Full          | None                             |
| `past_due`    | `past_due`          | Full (grace)  | Email alerts, 7-day grace period |
| `canceled`    | `churned`           | None          | Revoke all member premium access |
| `incomplete`  | `inactive`          | None          | Block access until payment       |
| `trialing`    | `active`            | Full          | None (not used for B2B)          |

## Testing Webhooks Locally

Use Stripe CLI to forward webhooks to local Edge Function:

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks to local Supabase
stripe listen --forward-to http://localhost:54321/functions/v1/b2b-stripe-webhook

# Trigger test events
stripe trigger customer.subscription.updated
stripe trigger invoice.payment_failed
stripe trigger customer.subscription.deleted
```

## Environment Variables

Required environment variables for Edge Function:

```bash
STRIPE_SECRET_KEY=sk_test_xxxxxxxxxxxxxxxxxxxxx  # Or sk_live_ for production
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxx
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Stripe Dashboard Configuration

### Products

1. Navigate to **Products** → **Add product**
2. Create "MindFriend Business" product
3. Add two prices: `price_business_monthly` and `price_business_annual`
4. Repeat for "MindFriend Enterprise" product

### Webhooks

1. Navigate to **Developers** → **Webhooks** → **Add endpoint**
2. Endpoint URL: `https://www.mindfriend.app/webhooks/stripe`
3. Description: "MindFriend B2B Organization Billing"
4. Events to send:
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_failed`
   - `invoice.payment_succeeded`
   - `invoice.paid`
5. Save webhook secret to environment variables

### Customer Portal

Enable Stripe Customer Portal for billing management:

1. Navigate to **Settings** → **Customer portal**
2. Enable portal
3. Configure:
   - **Subscriptions:** Allow customers to update quantity
   - **Payment methods:** Allow updating
   - **Invoices:** Allow viewing and downloading
   - **Cancellation:** Require reason, offer discount

Portal URL: `https://billing.stripe.com/p/login/xxxxx`

## Billing Audit Log

All Stripe webhook events are logged to `billing_audit_log` table:

```sql
SELECT * FROM billing_audit_log
WHERE organization_id = 'uuid-acme-corp'
ORDER BY created_at DESC
LIMIT 10;
```

**Event Types:**

- `seat_change` - Subscription quantity updated
- `subscription_canceled` - Subscription deleted
- `payment_failed` - Invoice payment failed
- `payment_succeeded` - Invoice payment succeeded
- `renewal` - Subscription renewed

## FAQ

**Q: What happens if a member joins when organization is at seat limit?**

A: The `join-organization` Edge Function checks `seat_count >= max_seats` and returns `SEAT_LIMIT_REACHED` error. Organization admin must purchase additional seats before new members can join.

**Q: How are seat overages handled?**

A: Stripe `billing_thresholds` triggers an alert when `seats_used >= seat_count + 5`. Admins receive email notification to purchase additional seats. Members can still join (up to soft limit), triggering immediate seat purchase.

**Q: Can organizations downgrade mid-cycle?**

A: Yes. Downgrading reduces `seat_count` immediately and creates a credit for remaining billing period, applied to next invoice.

**Q: What if payment fails after grace period?**

A: Organization status → `inactive`, all member `subscriptions` updated to `tier: free`, premium features blocked. Organization can reactivate by updating payment method and paying outstanding invoices.

---

**Last Updated:** 2026-01-19
**Owner:** MindFriend DevOps Team
**Status:** Phase 1 Implementation
