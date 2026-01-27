/**
 * Audio Utilities for Sleep Story Synthesis
 * Handles text chunking for ElevenLabs API limits and MP3 concatenation
 */

// ElevenLabs has a 5000 character limit per request
const MAX_CHARS_PER_CHUNK = 4500; // Leave buffer for safety

/**
 * Split text into chunks at sentence boundaries
 * Ensures no chunk exceeds the ElevenLabs character limit
 * @param text Full text to chunk
 * @param maxChars Maximum characters per chunk (default 4500)
 * @returns Array of text chunks
 */
export function chunkTextBySentence(
  text: string,
  maxChars: number = MAX_CHARS_PER_CHUNK,
): string[] {
  // If text is short enough, return as single chunk
  if (text.length <= maxChars) {
    return [text];
  }

  const chunks: string[] = [];
  let currentChunk = "";

  // Split into sentences (handles ., !, ?, and ellipsis)
  const sentences = text.match(/[^.!?]+[.!?]+(?:\s|$)|[^.!?]+$/g) || [text];

  for (const sentence of sentences) {
    const trimmedSentence = sentence.trim();

    // If single sentence is too long, split at commas or force split
    if (trimmedSentence.length > maxChars) {
      // First save current chunk if exists
      if (currentChunk.trim()) {
        chunks.push(currentChunk.trim());
        currentChunk = "";
      }

      // Split long sentence at clause boundaries (commas, semicolons)
      const clauseChunks = splitLongSentence(trimmedSentence, maxChars);
      chunks.push(...clauseChunks.slice(0, -1));
      currentChunk = clauseChunks[clauseChunks.length - 1];
      continue;
    }

    // Check if adding this sentence would exceed limit
    if ((currentChunk + " " + trimmedSentence).trim().length > maxChars) {
      // Save current chunk and start new one
      if (currentChunk.trim()) {
        chunks.push(currentChunk.trim());
      }
      currentChunk = trimmedSentence;
    } else {
      // Add sentence to current chunk
      currentChunk = (currentChunk + " " + trimmedSentence).trim();
    }
  }

  // Don't forget the last chunk
  if (currentChunk.trim()) {
    chunks.push(currentChunk.trim());
  }

  console.log(
    `[audio-utils] Split ${text.length} chars into ${chunks.length} chunks`,
  );

  return chunks;
}

/**
 * Split a long sentence at clause boundaries
 */
function splitLongSentence(sentence: string, maxChars: number): string[] {
  const chunks: string[] = [];
  let current = "";

  // Try to split at commas and semicolons first
  const clauses = sentence.split(/([,;])/);

  for (let i = 0; i < clauses.length; i++) {
    const clause = clauses[i];

    if ((current + clause).length > maxChars) {
      if (current.trim()) {
        chunks.push(current.trim());
      }

      // If single clause is still too long, force split at word boundary
      if (clause.length > maxChars) {
        const wordChunks = splitAtWordBoundary(clause, maxChars);
        chunks.push(...wordChunks.slice(0, -1));
        current = wordChunks[wordChunks.length - 1];
      } else {
        current = clause;
      }
    } else {
      current += clause;
    }
  }

  if (current.trim()) {
    chunks.push(current.trim());
  }

  return chunks;
}

/**
 * Force split at word boundary when no better option
 */
function splitAtWordBoundary(text: string, maxChars: number): string[] {
  const words = text.split(/\s+/);
  const chunks: string[] = [];
  let current = "";

  for (const word of words) {
    if ((current + " " + word).trim().length > maxChars) {
      if (current.trim()) {
        chunks.push(current.trim());
      }
      current = word;
    } else {
      current = (current + " " + word).trim();
    }
  }

  if (current.trim()) {
    chunks.push(current.trim());
  }

  return chunks;
}

/**
 * Concatenate MP3 audio buffers
 * Note: This works for MP3s with the same encoding (bit rate, sample rate)
 * ElevenLabs outputs consistent MP3 format so simple concatenation works
 * @param buffers Array of audio data buffers
 * @returns Combined audio buffer
 */
export function concatenateAudioBuffers(buffers: Uint8Array[]): Uint8Array {
  if (buffers.length === 0) {
    return new Uint8Array(0);
  }

  if (buffers.length === 1) {
    return buffers[0];
  }

  // Calculate total length
  const totalLength = buffers.reduce((sum, buf) => sum + buf.length, 0);

  // Allocate combined buffer
  const combined = new Uint8Array(totalLength);

  // Copy each buffer
  let offset = 0;
  for (const buffer of buffers) {
    combined.set(buffer, offset);
    offset += buffer.length;
  }

  console.log(
    `[audio-utils] Concatenated ${buffers.length} buffers (${totalLength} bytes)`,
  );

  return combined;
}

/**
 * Estimate audio file size from character count
 * Based on ElevenLabs typical output (~1.5 KB per 100 characters at 128kbps)
 */
export function estimateAudioSize(characterCount: number): number {
  const bytesPerChar = 15; // Approximate for speech at 128kbps
  return characterCount * bytesPerChar;
}

/**
 * Format duration in seconds to MM:SS string
 */
export function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

/**
 * Validate that audio buffer appears to be valid MP3
 * Checks for MP3 sync word (0xFF 0xFB or 0xFF 0xFA or 0xFF 0xF3)
 */
export function isValidMP3(buffer: Uint8Array): boolean {
  if (buffer.length < 4) {
    return false;
  }

  // Check for ID3 tag (ID3v2 header)
  if (buffer[0] === 0x49 && buffer[1] === 0x44 && buffer[2] === 0x33) {
    return true; // Has ID3 tag, likely valid
  }

  // Check for MP3 sync word (frame header starts with 0xFF 0xF*)
  if (buffer[0] === 0xff && (buffer[1] & 0xe0) === 0xe0) {
    return true;
  }

  return false;
}

/**
 * Add a small silence gap between audio chunks to prevent jarring transitions
 * This creates a ~200ms silence in MP3 format (simplified approach)
 * For production, consider using proper audio processing
 */
export function createSilenceGap(durationMs: number = 200): Uint8Array {
  // For now, return empty array - ElevenLabs handles pauses naturally
  // A proper implementation would generate actual silence frames
  // but the natural pause from sentence-end punctuation usually suffices
  return new Uint8Array(0);
}
