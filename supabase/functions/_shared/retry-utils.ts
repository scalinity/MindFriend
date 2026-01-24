// Retry Utilities - Exponential Backoff for External API Calls
// Addresses reliability findings from code review

export interface RetryOptions {
  maxAttempts?: number;
  initialDelayMs?: number;
  maxDelayMs?: number;
  backoffMultiplier?: number;
  retryableErrors?: string[];
}

const DEFAULT_RETRY_OPTIONS: Required<RetryOptions> = {
  maxAttempts: 3,
  initialDelayMs: 100,
  maxDelayMs: 10000,
  backoffMultiplier: 2,
  retryableErrors: [
    'ECONNRESET',
    'ETIMEDOUT',
    'ECONNREFUSED',
    'ENETUNREACH',
    'EAI_AGAIN',
  ],
};

/**
 * Retry a function with exponential backoff
 * @param fn Function to retry
 * @param options Retry configuration
 * @returns Result of successful function call
 * @throws Error if all retry attempts fail
 */
export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {},
): Promise<T> {
  const opts = { ...DEFAULT_RETRY_OPTIONS, ...options };
  let lastError: Error | null = null;
  let delay = opts.initialDelayMs;

  for (let attempt = 1; attempt <= opts.maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error: any) {
      lastError = error;

      // Don't retry if this is the last attempt
      if (attempt === opts.maxAttempts) {
        break;
      }

      // Check if error is retryable
      const isRetryable = opts.retryableErrors.some(code =>
        error.code === code || error.message?.includes(code)
      );

      if (!isRetryable && !isNetworkError(error)) {
        // Non-retryable error, fail immediately
        throw error;
      }

      // Log retry attempt
      console.warn(
        `Retry attempt ${attempt}/${opts.maxAttempts} after error:`,
        error.message,
        `- waiting ${delay}ms`
      );

      // Wait before retrying
      await sleep(delay);

      // Calculate next delay with exponential backoff
      delay = Math.min(delay * opts.backoffMultiplier, opts.maxDelayMs);
    }
  }

  // All attempts failed
  throw new Error(
    `Failed after ${opts.maxAttempts} attempts: ${lastError?.message}`
  );
}

/**
 * Check if error is a network-related error
 */
function isNetworkError(error: any): boolean {
  const networkIndicators = [
    'network',
    'timeout',
    'ECONNRESET',
    'ETIMEDOUT',
    'fetch failed',
    'socket hang up',
  ];

  return networkIndicators.some(indicator =>
    error.message?.toLowerCase().includes(indicator.toLowerCase())
  );
}

/**
 * Sleep for specified milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Retry a Supabase database query with backoff
 * @param queryFn Supabase query function
 * @param options Retry configuration
 * @returns Query result
 */
export async function retrySupabaseQuery<T>(
  queryFn: () => Promise<{ data: T; error: any }>,
  options: RetryOptions = {},
): Promise<T> {
  return retryWithBackoff(async () => {
    const { data, error } = await queryFn();
    if (error) {
      throw error;
    }
    return data;
  }, options);
}
