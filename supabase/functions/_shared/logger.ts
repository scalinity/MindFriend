// Structured logging utility for Edge Functions
// Provides consistent JSON log format for Supabase logging

type LogLevel = "debug" | "info" | "warn" | "error";

interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: string;
  function?: string;
  userId?: string;
  [key: string]: unknown;
}

const LOG_LEVEL = Deno.env.get("LOG_LEVEL") || "info";

const LOG_LEVEL_PRIORITY: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

function shouldLog(level: LogLevel): boolean {
  const currentPriority = LOG_LEVEL_PRIORITY[LOG_LEVEL as LogLevel] ?? 1;
  const messagePriority = LOG_LEVEL_PRIORITY[level];
  return messagePriority >= currentPriority;
}

function formatLog(entry: LogEntry): string {
  return JSON.stringify(entry);
}

/**
 * Structured logger for Edge Functions
 * Outputs JSON-formatted logs that are easily searchable in Supabase
 *
 * Usage:
 *   const log = createLogger("chat");
 *   log.info("Processing message", { conversationId: "..." });
 *   log.error("Failed to send", { error: err.message });
 */
export function createLogger(functionName: string) {
  const log = (
    level: LogLevel,
    message: string,
    data?: Record<string, unknown>
  ) => {
    if (!shouldLog(level)) return;

    const entry: LogEntry = {
      level,
      message,
      timestamp: new Date().toISOString(),
      function: functionName,
      ...data,
    };

    // Redact sensitive fields
    if (entry.token) entry.token = "[REDACTED]";
    if (entry.password) entry.password = "[REDACTED]";
    if (entry.secret) entry.secret = "[REDACTED]";
    if (entry.apiKey) entry.apiKey = "[REDACTED]";

    const formatted = formatLog(entry);

    switch (level) {
      case "debug":
      case "info":
        console.log(formatted);
        break;
      case "warn":
        console.warn(formatted);
        break;
      case "error":
        console.error(formatted);
        break;
    }
  };

  return {
    debug: (message: string, data?: Record<string, unknown>) =>
      log("debug", message, data),
    info: (message: string, data?: Record<string, unknown>) =>
      log("info", message, data),
    warn: (message: string, data?: Record<string, unknown>) =>
      log("warn", message, data),
    error: (message: string, data?: Record<string, unknown>) =>
      log("error", message, data),

    // Log with user context (userId is hashed for privacy in non-debug mode)
    userAction: (
      message: string,
      userId: string,
      data?: Record<string, unknown>
    ) => {
      const userIdDisplay =
        LOG_LEVEL === "debug" ? userId : `${userId.slice(0, 8)}...`;
      log("info", message, { userId: userIdDisplay, ...data });
    },
  };
}

// Default logger for quick use
export const logger = createLogger("edge-function");
