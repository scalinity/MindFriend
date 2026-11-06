/**
 * xAI Grok API Client Utility
 * Shared utility for calling xAI Grok API with timeout and graceful fallback
 * Used by: analyze-decision, generate-weekly-insights Edge Functions
 */

import { budgetedXAIText, type XAITextBudgetContext } from "./budgeted-xai-text.ts";
const DEFAULT_TIMEOUT_MS = 10000; // 10 seconds as per decisions.md
const DEFAULT_MAX_TOKENS = 200;
const DEFAULT_TEMPERATURE = 0.7;

export interface XAIRequest {
  model: "grok-4.3";
  messages: Array<{
    role: "system" | "user" | "assistant";
    content: string;
  }>;
  max_tokens: number;
  temperature: number;
}

export interface XAIResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: Array<{
    index: number;
    message: {
      role: string;
      content: string;
    };
    finish_reason: string;
  }>;
  usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export interface GrokCallOptions {
  budget: XAITextBudgetContext;
  signal?: AbortSignal;
  maxTokens?: number;
  temperature?: number;
  timeout?: number;
}

/**
 * Call xAI Grok API with structured prompt and timeout
 * @param systemPrompt - System message defining AI behavior
 * @param userPrompt - User message with context/question
 * @param options - Optional configuration (tokens, temperature, timeout)
 * @returns AI response text or null on failure (timeout/error)
 */
export async function callGrokAPI(
  systemPrompt: string,
  userPrompt: string,
  options: GrokCallOptions,
): Promise<string | null> {
  const {
    maxTokens = DEFAULT_MAX_TOKENS,
    temperature = DEFAULT_TEMPERATURE,
    timeout = DEFAULT_TIMEOUT_MS,
  } = options;

  // Validate environment variable
  const apiKey = Deno.env.get("XAI_API_KEY");
  if (!apiKey) {
    console.error("[xai-client] XAI_API_KEY environment variable not set");
    return null;
  }

  // Create abort controller for timeout
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await budgetedXAIText({
      ...options.budget,
      apiKey,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      maxTokens,
      temperature,
      signal: options.signal ? AbortSignal.any([options.signal, controller.signal]) : controller.signal,
    });

    clearTimeout(timeoutId);

    // Handle HTTP errors
    if (!response.ok) {
      console.error(`[xai-client] API error (status ${response.status})`);
      return null;
    }

    // Parse response
    const data: XAIResponse = await response.json();

    if (!data.choices || data.choices.length === 0) {
      console.error("[xai-client] No choices in API response");
      return null;
    }

    const content = data.choices[0].message.content;

    console.log(
      `[xai-client] Success (tokens used: ${data.usage?.total_tokens || "unknown"})`,
    );

    return content;
  } catch (error) {
    clearTimeout(timeoutId);

    if (error instanceof Error && error.name === "AbortError") {
      console.error(`[xai-client] Request timeout after ${timeout}ms`);
    } else {
      console.error("[xai-client] Request failed");
    }

    return null;
  }
}

/**
 * Sanitize user input to prevent prompt injection attacks
 * Removes potential injection patterns while preserving meaning
 * @param input - Raw user input
 * @returns Sanitized text safe for AI prompts
 */
export function sanitizeForPrompt(input: string): string {
  return input
    .replace(/```/g, "") // Remove code blocks
    .replace(/system:/gi, "user says:") // Prevent role confusion
    .replace(/assistant:/gi, "user says:") // Prevent role confusion
    .replace(/<\/?[^>]+(>|$)/g, "") // Strip HTML tags
    .substring(0, 5000); // Limit length to prevent token overflow
}

/**
 * Parse JSON from AI response with fallback
 * Attempts to extract JSON even if surrounded by markdown or text
 * @param response - AI response text
 * @returns Parsed object or null if unparseable
 */
export function parseAIJSON<T>(response: string | null): T | null {
  if (!response) return null;

  try {
    // Try direct parse first
    return JSON.parse(response) as T;
  } catch {
    // Try extracting JSON from markdown code blocks
    const jsonMatch = response.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/);
    if (jsonMatch) {
      try {
        return JSON.parse(jsonMatch[1]) as T;
      } catch {
        // Fall through to next attempt
      }
    }

    // Try finding any JSON object in the response
    const objectMatch = response.match(/\{[\s\S]*\}/);
    if (objectMatch) {
      try {
        return JSON.parse(objectMatch[0]) as T;
      } catch {
        console.error("[xai-client] Failed to parse JSON from response");
      }
    }

    console.error("[xai-client] No valid JSON found in response");
    return null;
  }
}
