// Shared input sanitization utilities for Edge Functions
// Prevents prompt injection attacks across all AI-calling functions
// Extracted from chat/index.ts for consistent application

/**
 * Sanitize user input to prevent prompt injection attacks.
 * Apply to ALL user-supplied text before interpolating into LLM prompts.
 *
 * @param input - Raw user input string
 * @param maxLength - Maximum allowed length (default 4000)
 * @returns Sanitized string safe for LLM prompt interpolation
 */
export function sanitizeForPrompt(
  input: string,
  maxLength: number = 4000,
): string {
  // Limit length to prevent token stuffing
  const truncated = input.slice(0, maxLength);
  // Escape characters that could be used for prompt manipulation
  return (
    truncated
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .replace(/\n/g, " ")
      .replace(/\r/g, "")
      .replace(/\t/g, " ")
      // Remove potential prompt injection patterns - role impersonation
      .replace(/^(system|assistant|user):/gim, "[redacted]:")
      .replace(/\b(system|assistant|user)\s*:\s*/gi, "[redacted]: ")
      // Common LLM-specific delimiters and tokens
      .replace(/\[INST\]/gi, "[redacted]")
      .replace(/\[\/INST\]/gi, "[redacted]")
      .replace(/<<SYS>>/gi, "[redacted]")
      .replace(/<\|.*?\|>/g, "[redacted]")
      .replace(/\[\[.*?\]\]/g, (match) =>
        match.toLowerCase().includes("system") ||
        match.toLowerCase().includes("instruction")
          ? "[redacted]"
          : match,
      )
      // Instruction override attempts
      .replace(
        /ignore\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?)/gi,
        "[redacted]",
      )
      .replace(
        /forget\s+(everything|all|your)\s+(you('ve)?\s+)?(learned|know|were told)/gi,
        "[redacted]",
      )
      .replace(/disregard\s+(all\s+)?(previous|above|system)/gi, "[redacted]")
      .replace(/new\s+instructions?:\s*/gi, "[redacted]: ")
      .replace(/override\s+(system|instructions?|prompt)/gi, "[redacted]")
      // Jailbreak/DAN pattern indicators
      .replace(/\b(do\s+anything\s+now|DAN|jailbreak)\b/gi, "[redacted]")
      .replace(
        /pretend\s+(to\s+be|you\s+are)\s+(a\s+)?(different|evil|unrestricted)/gi,
        "[redacted]",
      )
      .replace(
        /you\s+are\s+now\s+(a\s+)?(different|evil|unrestricted|free)/gi,
        "[redacted]",
      )
      // Roleplay escape attempts
      .replace(/stop\s+being\s+(a\s+)?helpful/gi, "[redacted]")
      .replace(/exit\s+(character|roleplay|persona)/gi, "[redacted]")
      // Markdown/formatting abuse
      .replace(/```(system|instruction|prompt)/gi, "```[redacted]")
  );
}
