# Intervention Efficacy Engine - Monitoring & Maintenance Guide

**Date:** 2026-01-24
**Status:** Production Ready
**Owner:** Engineering Team

---

## Table of Contents

1. [Overview](#overview)
2. [Monitoring Infrastructure](#monitoring-infrastructure)
3. [Key Metrics](#key-metrics)
4. [Alerting Rules](#alerting-rules)
5. [Dashboard Setup](#dashboard-setup)
6. [Maintenance Tasks](#maintenance-tasks)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Runbook: Common Issues](#runbook-common-issues)

---

## Overview

The Intervention Efficacy Engine consists of:

- **iOS Client**: EfficacyCalculator.swift (local calculations)
- **Edge Functions**: 4 Deno functions (calculate-efficacy, get-recommendations, get-efficacy-dashboard, aggregate-efficacy-profiles)
- **Database Tables**: intervention_efficacy, user_efficacy_profiles, emotional_trajectories
- **Supporting Infrastructure**: Logging, rate limiting, error monitoring

**Monitoring Goals:**

- Ensure < 100ms p95 response time for user-facing functions
- Maintain < 0.5% error rate across all functions
- Detect and alert on anomalies before users are affected
- Track efficacy engine business metrics (recommendations accuracy, breakthrough detection rate)

---

## Monitoring Infrastructure

### 1. Structured Logging

**Location:** `supabase/functions/_shared/logger.ts`

**Features:**

- JSON-formatted logs for easy parsing
- Request ID tracing across function calls
- Performance timing for all operations
- User context enrichment
- Error stack traces with context

**Log Levels:**

- `DEBUG`: Detailed execution flow
- `INFO`: Normal operations, request/response logging
- `WARN`: Recoverable errors, degraded performance
- `ERROR`: Unhandled errors, failures

**Viewing Logs:**

```bash
# View logs for a specific function
supabase functions logs calculate-efficacy --tail

# View logs with specific log level
supabase functions logs calculate-efficacy | grep '"level":"ERROR"'

# View logs for a specific request ID
supabase functions logs calculate-efficacy | grep 'req_1234567890'
```

**Supabase Dashboard:**

- Navigate to: **Project → Edge Functions → [Function Name] → Logs**
- Filter by: Time range, log level, search query
- Export: Download logs as JSON for analysis

### 2. Error Monitoring

**Location:** `supabase/functions/_shared/errorMonitor.ts`

**Features:**

- Automatic error recording to `error_events` table
- Error rate tracking with configurable thresholds
- Alert generation when thresholds exceeded
- 7-day data retention with automatic cleanup

**Database Tables:**

**error_events:**
| Column | Type | Description |
|--------|------|-------------|
| id | BIGSERIAL | Primary key |
| function_name | TEXT | Edge Function name |
| error_type | TEXT | Error class/type |
| error_message | TEXT | Error message |
| error_stack | TEXT | Stack trace |
| context | JSONB | Request context |
| timestamp | TIMESTAMPTZ | When error occurred |

**error_alerts:**
| Column | Type | Description |
|--------|------|-------------|
| id | BIGSERIAL | Primary key |
| function_name | TEXT | Edge Function name |
| error_rate | DECIMAL | Error rate (0.0-1.0) |
| threshold | DECIMAL | Threshold that was exceeded |
| window_minutes | INTEGER | Time window for calculation |
| message | TEXT | Alert message |
| acknowledged | BOOLEAN | Whether alert has been acknowledged |
| acknowledged_at | TIMESTAMPTZ | When alert was acknowledged |

**Querying Error Data:**

```sql
-- View error rate summary (past 24 hours)
SELECT * FROM error_rate_summary;

-- View active alerts
SELECT * FROM active_alerts;

-- Recent errors for a specific function
SELECT
  error_type,
  error_message,
  COUNT(*) as occurrence_count,
  MAX(timestamp) as last_seen
FROM error_events
WHERE function_name = 'calculate-efficacy'
  AND timestamp > NOW() - INTERVAL '1 hour'
GROUP BY error_type, error_message
ORDER BY occurrence_count DESC;

-- Acknowledge an alert
UPDATE error_alerts
SET acknowledged = TRUE,
    acknowledged_at = NOW(),
    acknowledged_by = auth.uid()
WHERE id = 123;
```

### 3. Rate Limiting

**Location:** `supabase/functions/_shared/rateLimiter.ts`

**Database Table:** `rate_limit_tracker`

**Rate Limits:**
| Function | Limit | Window | Purpose |
|----------|-------|--------|---------|
| calculate-efficacy | 20 req | 1 hour | Prevent abuse of costly calculation |
| get-recommendations | 100 req | 1 hour | High-traffic user-facing endpoint |
| get-efficacy-dashboard | 50 req | 1 hour | Dashboard data fetching |
| aggregate-efficacy-profiles | 5 req | 1 day | Nightly cron job (internal only) |

**Querying Rate Limit Data:**

```sql
-- Request volume by function (past hour)
SELECT
  SPLIT_PART(key, ':', 1) as function_name,
  COUNT(*) as request_count,
  COUNT(DISTINCT SPLIT_PART(key, ':', 2)) as unique_users
FROM rate_limit_tracker
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY function_name
ORDER BY request_count DESC;

-- Rate limit violations (requests that were blocked)
-- Note: Blocked requests are not recorded in rate_limit_tracker
-- Check error_events for "RATE_LIMIT_EXCEEDED" errors
SELECT
  function_name,
  COUNT(*) as violations,
  ARRAY_AGG(DISTINCT context->>'userId') as affected_users
FROM error_events
WHERE error_type = 'RATE_LIMIT_EXCEEDED'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY function_name;
```

---

## Key Metrics

### 1. Performance Metrics

**Response Time (95th Percentile):**
| Function | Target | Excellent | Good | Warning | Critical |
|----------|--------|-----------|------|---------|----------|
| calculate-efficacy | <50ms | <20ms | <50ms | <100ms | >100ms |
| get-recommendations | <100ms | <30ms | <80ms | <150ms | >150ms |
| get-efficacy-dashboard | <150ms | <40ms | <100ms | <200ms | >200ms |
| aggregate-efficacy-profiles | <2000ms | <500ms | <1500ms | <3000ms | >3000ms |

**Query from Supabase Dashboard:**

```sql
-- Edge Function performance (past 24 hours)
-- Note: Use Supabase Dashboard → Functions → Invocations tab for built-in metrics

-- Custom query: Calculate p95 response time from logs
-- (Requires parsing JSON logs, or use Supabase Analytics)
```

### 2. Error Metrics

**Error Rate Thresholds:**
| Function Type | Target | Warning | Critical |
|--------------|--------|---------|----------|
| Critical (user-facing) | <0.1% | 0.5% | 1% |
| Standard | <0.5% | 1% | 2% |
| Background (cron) | <1% | 5% | 10% |

**Query from error_rate_summary view:**

```sql
-- Error rate by function (past 24 hours)
SELECT
  function_name,
  SUM(error_count) as total_errors,
  COUNT(DISTINCT hour) as active_hours,
  ROUND(AVG(error_count), 2) as avg_errors_per_hour
FROM error_rate_summary
WHERE hour > NOW() - INTERVAL '24 hours'
GROUP BY function_name
ORDER BY total_errors DESC;
```

### 3. Business Metrics

**Efficacy Engine Usage:**

```sql
-- Calculations per day
SELECT
  DATE(completed_at) as date,
  COUNT(*) as efficacy_calculations,
  COUNT(DISTINCT user_id) as unique_users,
  ROUND(AVG(efficacy_score), 2) as avg_efficacy_score
FROM intervention_efficacy
WHERE completed_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(completed_at)
ORDER BY date DESC;

-- Breakthrough detection rate
SELECT
  DATE(completed_at) as date,
  COUNT(*) as total_sessions,
  SUM(CASE WHEN breakthrough_detected THEN 1 ELSE 0 END) as breakthrough_sessions,
  ROUND(100.0 * SUM(CASE WHEN breakthrough_detected THEN 1 ELSE 0 END) / COUNT(*), 2) as breakthrough_rate_pct
FROM intervention_efficacy
WHERE completed_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(completed_at)
ORDER BY date DESC;

-- Trajectory shape distribution
SELECT
  trajectory_shape,
  COUNT(*) as occurrence_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as percentage
FROM intervention_efficacy
WHERE completed_at > NOW() - INTERVAL '7 days'
GROUP BY trajectory_shape
ORDER BY occurrence_count DESC;

-- Top effective exercises
SELECT
  e.name,
  COUNT(*) as session_count,
  ROUND(AVG(ie.efficacy_score), 2) as avg_efficacy,
  SUM(CASE WHEN ie.breakthrough_detected THEN 1 ELSE 0 END) as breakthroughs
FROM intervention_efficacy ie
JOIN exercises e ON e.id = ie.exercise_id
WHERE ie.completed_at > NOW() - INTERVAL '7 days'
GROUP BY e.name
ORDER BY avg_efficacy DESC
LIMIT 10;
```

---

## Alerting Rules

### Critical Alerts (Immediate Response Required)

**1. High Error Rate (P0)**

```sql
-- Alert when error rate > 1% in 15-minute window
SELECT * FROM active_alerts
WHERE error_rate > 0.01
  AND window_minutes <= 15;
```

**Action:** Check error logs, identify root cause, hotfix if needed

**2. Edge Function Down (P0)**

```sql
-- Alert when no successful requests in 5 minutes
-- (Implement via external monitoring like UptimeRobot or Pingdom)
```

**Action:** Check Supabase status page, redeploy function if needed

**3. Database Connection Pool Exhausted (P0)**

```sql
-- Monitor via Supabase Dashboard → Database → Connection Pooler
-- Alert when connections > 80% of max
```

**Action:** Investigate slow queries, scale database if needed

### Warning Alerts (Monitor Closely)

**4. Elevated Error Rate (P1)**

```sql
-- Alert when error rate > 0.5% in 1-hour window
SELECT * FROM active_alerts
WHERE error_rate > 0.005
  AND window_minutes <= 60;
```

**Action:** Investigate error types, prepare hotfix

**5. Slow Response Time (P1)**

```sql
-- Alert when p95 response time > threshold
-- (Implement via Supabase Dashboard → Functions → Performance tab)
```

**Action:** Review database query performance, check index usage

**6. Rate Limit Violations (P2)**

```sql
-- Alert when users hit rate limits frequently
SELECT
  function_name,
  COUNT(*) as violation_count
FROM error_events
WHERE error_type = 'RATE_LIMIT_EXCEEDED'
  AND timestamp > NOW() - INTERVAL '1 hour'
GROUP BY function_name
HAVING COUNT(*) > 10;
```

**Action:** Review rate limit thresholds, investigate abuse

### Information Alerts (Track Trends)

**7. Low Efficacy Scores (P3)**

```sql
-- Alert when average efficacy score drops significantly
SELECT
  AVG(efficacy_score) as avg_efficacy
FROM intervention_efficacy
WHERE completed_at > NOW() - INTERVAL '24 hours'
HAVING AVG(efficacy_score) < 50;  -- Below neutral baseline
```

**Action:** Review exercise quality, investigate user feedback

**8. Aggregation Job Failure (P3)**

```sql
-- Alert when nightly aggregation job fails
SELECT * FROM error_events
WHERE function_name = 'aggregate-efficacy-profiles'
  AND error_type = 'AGGREGATION_FAILED'
  AND timestamp > NOW() - INTERVAL '25 hours';  -- Should run daily
```

**Action:** Re-run aggregation manually, investigate data quality

---

## Dashboard Setup

### Supabase Dashboard

**1. Edge Functions Overview**

- Navigate to: **Project → Edge Functions**
- Metrics: Invocations, Errors, Response time
- Timeframe: Last 24 hours (default)

**2. Function-Specific Metrics**

- Navigate to: **Project → Edge Functions → [Function Name]**
- Tabs: Invocations, Logs, Performance, Settings

**3. Database Performance**

- Navigate to: **Project → Database → Query Performance**
- View: Slowest queries, Most frequent queries
- Action: Add indexes for slow queries

### Custom Monitoring Dashboard

**Recommended Tools:**

- **Grafana** + **Prometheus**: For real-time metrics and alerting
- **Datadog** / **New Relic**: Full observability platform
- **Supabase Analytics**: Built-in analytics (Pro plan)

**Key Dashboard Panels:**

1. **Request Volume**
   - Line chart: Requests per minute by function
   - Alert: Sudden spikes or drops

2. **Error Rate**
   - Line chart: Error rate (%) over time
   - Alert: Error rate > threshold

3. **Response Time**
   - Line chart: p50, p95, p99 response time
   - Alert: p95 > threshold

4. **Business Metrics**
   - Gauge: Average efficacy score (7-day rolling)
   - Bar chart: Top exercises by efficacy
   - Pie chart: Trajectory shape distribution

5. **Database Health**
   - Line chart: Connection pool utilization
   - Line chart: Query duration (p95)
   - Alert: Slow queries > 500ms

---

## Maintenance Tasks

### Daily

**1. Review Error Alerts**

```sql
-- Check for unacknowledged alerts
SELECT * FROM active_alerts;
```

**Action:** Investigate and acknowledge alerts

**2. Monitor Request Volume**

- Check Supabase Dashboard → Functions → Invocations
- Look for unusual patterns (spikes, drops)

**3. Review Top Errors**

```sql
-- Top 5 errors in past 24 hours
SELECT
  error_type,
  error_message,
  COUNT(*) as count
FROM error_events
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY error_type, error_message
ORDER BY count DESC
LIMIT 5;
```

### Weekly

**1. Performance Review**

- Review p95 response times for all functions
- Identify slow queries via Database → Query Performance
- Review index hit rate (should be >95%)

**2. Error Trend Analysis**

```sql
-- Error count by day (past 7 days)
SELECT
  DATE(timestamp) as date,
  function_name,
  COUNT(*) as error_count
FROM error_events
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY DATE(timestamp), function_name
ORDER BY date DESC, error_count DESC;
```

**3. Business Metrics Review**

- Average efficacy score trend
- Breakthrough detection rate
- Top/bottom performing exercises
- User engagement (sessions per day)

**4. Data Cleanup**

```sql
-- Run cleanup functions (should be automatic, but verify)
SELECT cleanup_error_monitoring();
SELECT cleanup_rate_limit_tracker();
```

### Monthly

**1. Capacity Planning**

- Review database storage growth
- Evaluate connection pool capacity
- Assess Edge Function invocation limits
- Review rate limit thresholds

**2. Index Maintenance**

```sql
-- Check index sizes and usage
SELECT
  schemaname,
  tablename,
  indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
  idx_scan as index_scans
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename IN ('intervention_efficacy', 'user_efficacy_profiles')
ORDER BY pg_relation_size(indexrelid) DESC;
```

**3. Performance Benchmark**

- Run load tests with current data volume
- Compare against baseline performance targets
- Identify degradation and optimize

**4. Security Audit**

- Review RLS policies
- Check for exposed sensitive data in logs
- Verify rate limiting is effective
- Review error messages for information leakage

### Quarterly

**1. Code Review**

- Review efficacy calculation algorithm for improvements
- Check for deprecated dependencies
- Update Edge Function runtime if needed
- Review and update error handling patterns

**2. Data Retention Policy**

- Evaluate 7-day retention for error_events
- Consider archiving old intervention_efficacy records
- Plan for long-term data storage strategy

**3. Disaster Recovery Test**

- Test database backup restoration
- Verify Edge Function redeployment process
- Document recovery procedures

---

## Troubleshooting Guide

### High Error Rate

**Symptoms:**

- Error rate > 1% in active_alerts table
- Increased user complaints
- Elevated error logs

**Diagnosis:**

```sql
-- Identify error types
SELECT
  error_type,
  error_message,
  COUNT(*) as count,
  ARRAY_AGG(DISTINCT function_name) as affected_functions
FROM error_events
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY error_type, error_message
ORDER BY count DESC;
```

**Common Causes:**

1. **Database timeout** → Check query performance, add indexes
2. **External API failure** → Check AI provider status (X.AI)
3. **Invalid input data** → Add validation, improve error messages
4. **Rate limit exceeded** → Review thresholds, investigate abuse

**Resolution:**

- Hotfix if critical (redeploy function)
- Add error handling for recoverable errors
- Update validation rules
- Monitor for recurrence

### Slow Response Time

**Symptoms:**

- p95 response time > threshold
- User reports of slow dashboard/recommendations
- Database CPU spike

**Diagnosis:**

```sql
-- Identify slow queries
SELECT
  query,
  mean_exec_time,
  calls,
  total_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- Queries slower than 100ms
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**Common Causes:**

1. **Missing index** → Add recommended indexes from PERFORMANCE_REVIEW.md
2. **Large dataset** → Optimize query, add pagination
3. **Inefficient joins** → Rewrite query, denormalize data
4. **Lock contention** → Review concurrent writes

**Resolution:**

- Add missing indexes (apply via migration)
- Optimize slow queries (test with EXPLAIN ANALYZE)
- Consider caching for frequently accessed data
- Monitor index hit rate (should be >95%)

### Aggregation Job Failure

**Symptoms:**

- No updates to user_efficacy_profiles for >24 hours
- Recommendations become stale
- Error in aggregate-efficacy-profiles logs

**Diagnosis:**

```sql
-- Check last successful aggregation
SELECT
  user_id,
  exercise_id,
  updated_at,
  NOW() - updated_at as staleness
FROM user_efficacy_profiles
ORDER BY updated_at DESC
LIMIT 100;

-- Check for aggregation errors
SELECT * FROM error_events
WHERE function_name = 'aggregate-efficacy-profiles'
ORDER BY timestamp DESC
LIMIT 10;
```

**Common Causes:**

1. **Cron schedule failure** → Check Supabase cron logs
2. **Data validation error** → Check for corrupt data in intervention_efficacy
3. **Timeout** → Large dataset takes >10 minutes (Deno timeout)
4. **Database connection** → Connection pool exhausted

**Resolution:**

- Manually trigger aggregation via Function invoke
- Fix data quality issues
- Optimize aggregation query (use SQL GROUP BY instead of JS)
- Increase function timeout if needed

### Rate Limit False Positives

**Symptoms:**

- Legitimate users hitting rate limits
- Increased RATE_LIMIT_EXCEEDED errors
- User complaints about blocked requests

**Diagnosis:**

```sql
-- Analyze rate limit violations
SELECT
  context->>'userId' as user_id,
  function_name,
  COUNT(*) as violation_count,
  MAX(timestamp) as last_violation
FROM error_events
WHERE error_type = 'RATE_LIMIT_EXCEEDED'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY context->>'userId', function_name
ORDER BY violation_count DESC;
```

**Common Causes:**

1. **Threshold too low** → Power users exceed limits
2. **Client retry logic** → App retries too aggressively
3. **Shared IP address** → Multiple users from same network
4. **Test traffic** → Automated testing hitting production

**Resolution:**

- Increase rate limits for specific functions
- Implement user-based rate limiting (not IP-based)
- Add exponential backoff to client retry logic
- Whitelist test user accounts

---

## Runbook: Common Issues

### Issue: Efficacy scores suddenly drop

**Symptoms:**

- Average efficacy score < 50 (neutral baseline)
- User complaints about inaccurate recommendations
- Sudden change in trajectory shape distribution

**Diagnostic Steps:**

1. Check for data quality issues in intervention_efficacy table
2. Review recent code changes to EfficacyCalculator.swift or calculate-efficacy function
3. Analyze trajectory points for anomalies (missing data, extreme values)
4. Check if exercise library changed (deleted/modified exercises)

**Resolution:**

1. If data quality issue: Fix data validation in iOS app
2. If algorithm bug: Revert to previous version, fix and redeploy
3. If exercise change: Update exercise recommendations
4. Monitor efficacy scores for recovery

### Issue: Dashboard not loading

**Symptoms:**

- get-efficacy-dashboard returns 500 error
- Empty dashboard in iOS app
- High response time (>5 seconds)

**Diagnostic Steps:**

1. Check error logs for get-efficacy-dashboard function
2. Test dashboard query directly in Database → SQL Editor
3. Check database connection pool utilization
4. Review index usage for dashboard queries

**Resolution:**

1. If database issue: Optimize query, add indexes
2. If connection pool exhausted: Kill idle connections, scale database
3. If data corruption: Fix invalid records in intervention_efficacy
4. Fallback: Return cached data or default empty dashboard

### Issue: Recommendations not personalized

**Symptoms:**

- All users get same generic recommendations
- user_efficacy_profiles table is empty
- Aggregation job not running

**Diagnostic Steps:**

1. Check last run time of aggregate-efficacy-profiles cron job
2. Verify cron schedule in Supabase Dashboard
3. Check for errors in aggregation function logs
4. Query user_efficacy_profiles table for data freshness

**Resolution:**

1. If cron not scheduled: Set up cron schedule (see deployment docs)
2. If aggregation failing: Fix errors, manually trigger job
3. If insufficient data: Users need to complete more exercises (minimum 5 sessions)
4. Monitor aggregation job success rate

---

## Emergency Contacts

**On-Call Engineer:** [Engineering Team Slack Channel]
**Supabase Support:** support@supabase.com (Pro plan)
**Database Admin:** [DBA Email]
**Product Owner:** [PM Email/Slack]

---

## Appendix: SQL Queries Reference

### Quick Health Check

```sql
-- Overall system health (past 1 hour)
SELECT
  'Error Rate' as metric,
  ROUND(100.0 * COUNT(CASE WHEN e.timestamp IS NOT NULL THEN 1 END) / COUNT(r.timestamp), 2) as value,
  '%' as unit
FROM rate_limit_tracker r
LEFT JOIN error_events e ON e.timestamp = r.timestamp
WHERE r.timestamp > NOW() - INTERVAL '1 hour'

UNION ALL

SELECT
  'Active Alerts',
  COUNT(*)::text,
  'alerts'
FROM error_alerts
WHERE acknowledged = FALSE

UNION ALL

SELECT
  'Avg Efficacy Score (7d)',
  ROUND(AVG(efficacy_score), 2)::text,
  'pts'
FROM intervention_efficacy
WHERE completed_at > NOW() - INTERVAL '7 days';
```

### Export Error Data for Analysis

```sql
-- Export error events as CSV
COPY (
  SELECT
    to_char(timestamp, 'YYYY-MM-DD HH24:MI:SS') as timestamp,
    function_name,
    error_type,
    error_message,
    context->>'userId' as user_id,
    context->>'requestId' as request_id
  FROM error_events
  WHERE timestamp > NOW() - INTERVAL '24 hours'
  ORDER BY timestamp DESC
) TO '/tmp/error_events.csv' WITH CSV HEADER;
```

### Performance Baseline

```sql
-- Establish performance baseline for future comparison
CREATE TABLE performance_baseline AS
SELECT
  NOW() as baseline_date,
  function_name,
  COUNT(*) as request_count,
  AVG(duration) as avg_duration_ms,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration) as p95_duration_ms
FROM (
  -- Parse duration from log context (pseudocode - adapt to actual log structure)
  SELECT
    function_name,
    (context->>'duration')::numeric as duration
  FROM error_events
  WHERE timestamp > NOW() - INTERVAL '7 days'
) t
GROUP BY function_name;
```

---

**Document Version:** 1.0
**Last Updated:** 2026-01-24
**Next Review:** 2026-02-24
**Status:** ✅ Production Ready
