/**
 * Structured logging utility for Edge Functions
 * Provides consistent log formatting and levels
 */

export enum LogLevel {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

interface LogContext {
  userId?: string;
  requestId?: string;
  functionName?: string;
  [key: string]: unknown;
}

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  message: string;
  context?: LogContext;
  error?: {
    name: string;
    message: string;
    stack?: string;
  };
  duration?: number;
}

/**
 * Logger class for structured logging
 */
export class Logger {
  private functionName: string;
  private context: LogContext;

  constructor(functionName: string, baseContext: LogContext = {}) {
    this.functionName = functionName;
    this.context = { ...baseContext, functionName };
  }

  /**
   * Add additional context to all subsequent logs
   */
  addContext(context: LogContext): void {
    this.context = { ...this.context, ...context };
  }

  /**
   * Log a debug message
   */
  debug(message: string, context?: LogContext): void {
    this.log(LogLevel.DEBUG, message, context);
  }

  /**
   * Log an info message
   */
  info(message: string, context?: LogContext): void {
    this.log(LogLevel.INFO, message, context);
  }

  /**
   * Log a warning message
   */
  warn(message: string, context?: LogContext): void {
    this.log(LogLevel.WARN, message, context);
  }

  /**
   * Log an error message
   */
  error(message: string, error?: Error, context?: LogContext): void {
    const logEntry: LogEntry = {
      timestamp: new Date().toISOString(),
      level: LogLevel.ERROR,
      message,
      context: { ...this.context, ...context },
      error: error
        ? {
            name: error.name,
            message: error.message,
            stack: error.stack,
          }
        : undefined,
    };

    console.error(JSON.stringify(logEntry));
  }

  /**
   * Log request start
   */
  logRequest(method: string, path: string, context?: LogContext): void {
    this.info(`${method} ${path}`, { ...context, type: "request" });
  }

  /**
   * Log request completion with duration
   */
  logResponse(
    method: string,
    path: string,
    status: number,
    durationMs: number,
    context?: LogContext,
  ): void {
    this.info(`${method} ${path} ${status}`, {
      ...context,
      type: "response",
      status,
      duration: durationMs,
    });
  }

  /**
   * Measure execution time of an async function
   */
  async measure<T>(operationName: string, fn: () => Promise<T>): Promise<T> {
    const startTime = performance.now();
    this.debug(`Starting ${operationName}`);

    try {
      const result = await fn();
      const duration = performance.now() - startTime;
      this.debug(`Completed ${operationName}`, { duration });
      return result;
    } catch (error) {
      const duration = performance.now() - startTime;
      this.error(
        `Failed ${operationName}`,
        error instanceof Error ? error : new Error(String(error)),
        { duration },
      );
      throw error;
    }
  }

  /**
   * Base logging method
   */
  private log(level: LogLevel, message: string, context?: LogContext): void {
    const logEntry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      context: { ...this.context, ...context },
    };

    const logFn = level === LogLevel.ERROR ? console.error : console.log;
    logFn(JSON.stringify(logEntry));
  }
}

/**
 * Create a logger instance for a function
 */
export function createLogger(
  functionName: string,
  context?: LogContext,
): Logger {
  return new Logger(functionName, context);
}

/**
 * Extract user ID from request authorization header
 */
export function getUserIdFromRequest(req: Request): string | undefined {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return undefined;

  try {
    // Extract JWT payload (naive approach - in production use proper JWT library)
    const token = authHeader.replace("Bearer ", "");
    const payload = token.split(".")[1];
    const decoded = JSON.parse(atob(payload));
    return decoded.sub || decoded.user_id;
  } catch {
    return undefined;
  }
}

/**
 * Generate a unique request ID
 */
export function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}
