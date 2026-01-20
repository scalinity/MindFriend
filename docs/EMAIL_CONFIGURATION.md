# Email Configuration Guide

**Spec:** 15 - Daily/Weekly Summary Emails
**Last Updated:** 2026-01-19
**Owner:** Backend Team

This document provides setup instructions for Resend email delivery integration.

---

## Overview

MindFriend uses [Resend](https://resend.com) for transactional and marketing emails including weekly summaries, streak celebrations, lapsed user nudges, monthly reports, and achievement notifications.

---

## 1. Resend Account Setup

### 1.1 Create Resend Account

1. Go to resend.com
2. Sign up with work email
3. Verify email address

### 1.2 Add Sending Domain

1. Navigate to Domains in Resend dashboard
2. Click Add Domain
3. Enter: getmindfriend.app
4. Copy the DNS records shown (SPF, DKIM, DMARC)

### 1.3 Configure DNS Records

DNS Provider: Squarespace

1. Log in to Squarespace domain management
2. Navigate to DNS settings
3. Add the SPF, DKIM, and DMARC records
4. Wait 24-48 hours for DNS propagation
5. Return to Resend dashboard and click Verify Domain

---

## 2. API Key Generation

### 2.1 Create API Key

1. In Resend dashboard, go to API Keys
2. Click Create API Key
3. Name: mindfriend-production or mindfriend-staging
4. Permissions: Full Access
5. Copy the API key immediately (shown only once)

### 2.2 Store API Key in Supabase

Production:

```bash
# Set via Supabase Dashboard: Project Settings → Edge Functions → Secrets
# Add: RESEND_API_KEY = <your-api-key>

# Or via CLI:
supabase secrets set RESEND_API_KEY=<your-key-here>
```

Local Development:

```bash
# Create .env file in project root (DO NOT commit)
echo "RESEND_API_KEY=<your-key>" >> .env
```

---

## 3. Webhook Configuration

Webhooks notify MindFriend of email delivery events (bounces, complaints, opens, clicks).

### 3.1 Generate Webhook Secret

1. In Resend dashboard, go to Webhooks
2. Click Add Webhook
3. Endpoint URL: `https://<supabase-project-id>.supabase.co/functions/v1/email-webhook`
4. Subscribe to events: email.sent, email.delivered, email.opened, email.clicked, email.bounced, email.complained
5. Copy the Signing Secret

### 3.2 Store Webhook Secret in Supabase

```bash
supabase secrets set RESEND_WEBHOOK_SECRET=<your-webhook-secret>
```

### 3.3 Test Webhook

```bash
# View Edge Function logs to verify webhook events
supabase functions logs email-webhook --tail
```

---

## 4. Email Templates & Sender Identity

### 4.1 Sender Information

All emails sent from:

- From Name: MindFriend
- From Email: hello@getmindfriend.app
- Reply-To: support@getmindfriend.app

### 4.2 Email Headers (RFC 8058 Compliance)

All emails include one-click unsubscribe headers per RFC 8058.

---

## 5. Rate Limits & Quotas

### Resend Plan Limits

| Plan     | Monthly Emails | Rate Limit | Cost       |
| -------- | -------------- | ---------- | ---------- |
| Free     | 3,000          | 2/second   | $0         |
| Pro      | 50,000         | 10/second  | $20/month  |
| Business | 500,000        | 50/second  | $100/month |

Recommended: Start with Pro plan for MVP launch.

### Application-Level Rate Limits

- 10 emails per user per day (enforced by checkRateLimit())
- Queue-based sending (via email_queue table)

---

## 6. Monitoring & Troubleshooting

### 6.1 Check Email Logs

```sql
-- View recent email sends
SELECT * FROM email_logs ORDER BY sent_at DESC LIMIT 50;

-- Check bounce rate
SELECT status, COUNT(*) as count
FROM email_logs
WHERE sent_at > NOW() - INTERVAL '7 days'
GROUP BY status;
```

### 6.2 Dead Letter Queue

```sql
-- View failed emails requiring manual review
SELECT * FROM email_dead_letter_queue
WHERE requires_manual_review = true
ORDER BY created_at DESC;
```

### 6.3 Resend Dashboard Analytics

Monitor delivery rate (should be >98%), bounce rate (should be <2%), and complaint rate (should be <0.1%).

---

## 7. Security Best Practices

1. Never commit API keys to git
2. Rotate API keys quarterly
3. Verify webhook signatures (handled by verifyWebhookSignature())
4. Escape user input in templates (handled by escapeHtml())
5. Rate limit email sends (10/day per user)

---

## 8. Environment Variables Summary

| Variable              | Purpose                   |
| --------------------- | ------------------------- |
| RESEND_API_KEY        | Send emails via Resend    |
| RESEND_WEBHOOK_SECRET | Verify webhook signatures |

---

## 9. Testing Checklist

Before production deployment:

- [ ] Resend domain verified (getmindfriend.app)
- [ ] DNS records configured and verified
- [ ] API key stored in Supabase secrets
- [ ] Webhook endpoint deployed
- [ ] Webhook secret stored
- [ ] Send test email from Edge Function
- [ ] Verify email received (not spam)
- [ ] Test unsubscribe link
- [ ] Test bounce webhook
- [ ] Verify bounced user disabled

---

## 10. Support & Resources

- Resend Documentation: https://resend.com/docs
- Resend Status: https://status.resend.com
- Internal Spec: opus-specs/15-summary-emails.md
- Migration: supabase/migrations/20260420000000_email_summary_schema.sql
- Utilities: supabase/functions/\_shared/email-utils.ts
