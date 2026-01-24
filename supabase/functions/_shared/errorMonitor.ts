/**
 * Error monitoring and metrics tracking for Edge Functions
 * Provides error rate tracking, metrics aggregation, and alerting
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Logger } from "./logger.ts";

export interface ErrorMetrics {
  functionName: string;
  errorCount: number;
  totalRequests: number;
  errorRate: number;
  lastError: Date;
  timeWindow: string;
}

export interface ErrorAlert {
  id?: number;
  functionName: string;
  errorRate: number;
  threshold: number;
  windowMinutes: number;
  message: string;
  createdAt: Date;
}

/**
 * Error monitor class for tracking and alerting on error rates
 */
export class ErrorMonitor {
  private logger: Logger;
  private supabase: SupabaseClient;
  private functionName: string;

  // Alert thresholds (can be configured per function)
  private static readonly DEFAULT_ERROR_RATE_THRESHOLD = 0.1; // 10% error rate
  private static readonly DEFAULT_WINDOW_MINUTES = 15; // 15-minute window

  constructor(functionName: string, supabase: SupabaseClient, logger: Logger) {
    this.functionName = functionName;
    this.supabase = supabase;
    this.logger = logger;
  }

  /**
   * Record an error occurrence
   */
  async recordError(
    error: Error,
    context: Record<string, unknown> = {},
  ): Promise<void> {
    try {
      await this.supabase.from("error_events").insert({
        function_name: this.functionName,
        error_type: error.name,
        error_message: error.message,
        error_stack: error.stack,
        context: context,
        timestamp: new Date().toISOString(),
      });
    } catch (err) {
      // Don't fail the request if error recording fails
      this.logger.warn("Failed to record error event", { error: err });
    }
  }

  /**
   * Check if error rate exceeds threshold and trigger alert if needed
   */
  async checkErrorRate(
    threshold: number = ErrorMonitor.DEFAULT_ERROR_RATE_THRESHOLD,
    windowMinutes: number = ErrorMonitor.DEFAULT_WINDOW_MINUTES,
  ): Promise<ErrorMetrics | null> {
    try {
      const windowStart = new Date(Date.now() - windowMinutes * 60 * 1000);

      // Count errors in window
      const { count: errorCount } = await this.supabase
        .from("error_events")
        .select("*", { count: "exact", head: true })
        .eq("function_name", this.functionName)
        .gte("timestamp", windowStart.toISOString());

      // Count total requests in window (from rate_limit_tracker)
      const { count: totalRequests } = await this.supabase
        .from("rate_limit_tracker")
        .select("*", { count: "exact", head: true })
        .like("key", `%:${this.functionName}:%`)
        .gte("timestamp", windowStart.toISOString());

      const errors = errorCount || 0;
      const requests = totalRequests || 0;

      if (requests === 0) {
        return null; // No data to analyze
      }

      const errorRate = errors / requests;

      const metrics: ErrorMetrics = {
        functionName: this.functionName,
        errorCount: errors,
        totalRequests: requests,
        errorRate,
        lastError: new Date(),
        timeWindow: `${windowMinutes}m`,
      };

      // Trigger alert if threshold exceeded
      if (errorRate > threshold) {
        await this.triggerAlert(errorRate, threshold, windowMinutes);
        this.logger.error(
          `Error rate threshold exceeded: ${(errorRate * 100).toFixed(2)}%`,
          undefined,
          {
            errorCount: errors,
            totalRequests: requests,
            threshold: threshold * 100,
            windowMinutes,
          },
        );
      }

      return metrics;
    } catch (err) {
      this.logger.warn("Failed to check error rate", { error: err });
      return null;
    }
  }

  /**
   * Trigger an alert when error rate exceeds threshold
   */
  private async triggerAlert(
    errorRate: number,
    threshold: number,
    windowMinutes: number,
  ): Promise<void> {
    try {
      const alert: ErrorAlert = {
        functionName: this.functionName,
        errorRate,
        threshold,
        windowMinutes,
        message: `Error rate ${(errorRate * 100).toFixed(2)}% exceeds threshold ${(threshold * 100).toFixed(2)}% in ${windowMinutes}m window`,
        createdAt: new Date(),
      };

      await this.supabase.from("error_alerts").insert({
        function_name: alert.functionName,
        error_rate: alert.errorRate,
        threshold: alert.threshold,
        window_minutes: alert.windowMinutes,
        message: alert.message,
        created_at: alert.createdAt.toISOString(),
      });

      // TODO: Send notification (email, Slack, PagerDuty, etc.)
      // This would integrate with your notification service
    } catch (err) {
      this.logger.warn("Failed to trigger alert", { error: err });
    }
  }

  /**
   * Get error metrics for the past N minutes
   */
  async getMetrics(windowMinutes: number = 60): Promise<ErrorMetrics | null> {
    return await this.checkErrorRate(1.0, windowMinutes); // Set threshold to 100% to get metrics without triggering alert
  }

  /**
   * Clean up old error events (older than 7 days)
   */
  async cleanup(): Promise<void> {
    try {
      const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

      await this.supabase
        .from("error_events")
        .delete()
        .lt("timestamp", cutoff.toISOString());

      await this.supabase
        .from("error_alerts")
        .delete()
        .lt("created_at", cutoff.toISOString());

      this.logger.debug("Cleaned up old error events and alerts");
    } catch (err) {
      this.logger.warn("Failed to cleanup error events", { error: err });
    }
  }
}

/**
 * Create an error monitor instance
 */
export function createErrorMonitor(
  functionName: string,
  supabase: SupabaseClient,
  logger: Logger,
): ErrorMonitor {
  return new ErrorMonitor(functionName, supabase, logger);
}

/**
 * Common error rate thresholds for different function types
 */
export const ERROR_RATE_THRESHOLDS = {
  // Critical functions (user-facing, high traffic)
  CRITICAL: 0.01, // 1% error rate

  // Standard functions (normal operations)
  STANDARD: 0.05, // 5% error rate

  // Background jobs (cron, batch processing)
  BACKGROUND: 0.1, // 10% error rate

  // Experimental features (alpha/beta)
  EXPERIMENTAL: 0.2, // 20% error rate
};
