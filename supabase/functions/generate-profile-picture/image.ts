export const MAX_IMAGE_BYTES = 524_288;
export const MAX_PROVIDER_BYTES = 8 * 1024 * 1024;

export class AvatarError extends Error {
  constructor(readonly code: string, message: string, readonly status = 502) {
    super(message);
  }
}

export function failure(error: unknown, signal: AbortSignal): AvatarError {
  if (signal.aborted) {
    return signal.reason instanceof AvatarError
      ? signal.reason
      : new AvatarError(
        "generation_cancelled",
        "Avatar generation was cancelled.",
        499,
      );
  }
  return error instanceof AvatarError ? error : new AvatarError(
    "generation_failed",
    "Unable to generate the avatar. Please try again later.",
    503,
  );
}

export function decodeBase64(
  value: unknown,
  maxBytes = MAX_IMAGE_BYTES,
): Uint8Array {
  if (typeof value !== "string" || !value.length) {
    throw new AvatarError(
      "invalid_image_encoding",
      "The image provider returned an invalid image encoding.",
    );
  }
  if (value.length > Math.ceil(maxBytes / 3) * 4) {
    throw imageTooLarge();
  }
  if (value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new AvatarError(
      "invalid_image_encoding",
      "The image provider returned an invalid image encoding.",
    );
  }
  let binary: string;
  try {
    binary = atob(value);
    if (btoa(binary) !== value) throw new Error();
  } catch {
    throw new AvatarError(
      "invalid_image_encoding",
      "The image provider returned an invalid image encoding.",
    );
  }
  if (binary.length > maxBytes) throw imageTooLarge();
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function imageTooLarge(): AvatarError {
  return new AvatarError(
    "image_too_large",
    "Generated avatar exceeds 512 KiB. Try a simpler image or upload a smaller JPEG photo.",
    422,
  );
}

/** Validate the JPEG container, frame, scans and end marker without native codecs. */
export function decodeJPEG(value: unknown): Uint8Array {
  const bytes = decodeBase64(value);
  const invalid = (): never => {
    throw new AvatarError(
      "invalid_image_format",
      "The image provider returned an invalid or incomplete JPEG. Please try again later.",
    );
  };
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) invalid();
  const word = (offset: number) => (bytes[offset] << 8) | bytes[offset + 1];
  let offset = 2;
  let frame = false;
  let progressive = false;
  let scan = false;
  const quantization = new Set<number>();
  const huffman = new Set<number>();
  const components = new Set<number>();
  const componentTables = new Map<number, number>();
  const scanned = new Set<number>();
  while (offset < bytes.length) {
    if (bytes[offset++] !== 0xff) invalid();
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9) {
      if (
        !frame || !scan || scanned.size !== components.size ||
        offset !== bytes.length
      ) invalid();
      return bytes;
    }
    // SOI, stuffed bytes and restart markers are only valid in their own contexts.
    if (
      marker === undefined || marker === 0 || marker === 0xd8 ||
      (marker >= 0xd0 && marker <= 0xd7) || marker === 1
    ) invalid();
    if (offset + 2 > bytes.length) invalid();
    const length = word(offset);
    const end = offset + length;
    if (length < 2 || end > bytes.length) invalid();
    if (marker === 0xc0 || marker === 0xc1 || marker === 0xc2) {
      const count = bytes[offset + 7];
      if (
        frame || length < 11 || count < 1 || count > 4 ||
        length !== 8 + count * 3 || bytes[offset + 2] !== 8 ||
        word(offset + 3) === 0 || word(offset + 5) === 0
      ) invalid();
      for (let i = offset + 8; i < end; i += 3) {
        const sampling = bytes[i + 1];
        if (
          components.has(bytes[i]) || !(sampling >> 4) ||
          (sampling >> 4) > 4 || !(sampling & 15) ||
          (sampling & 15) > 4 || bytes[i + 2] > 3
        ) invalid();
        components.add(bytes[i]);
        componentTables.set(bytes[i], bytes[i + 2]);
      }
      frame = true;
      progressive = marker === 0xc2;
    } else if (marker === 0xdb) {
      let table = offset + 2;
      while (table < end) {
        const spec = bytes[table++];
        if ((spec >> 4) > 1 || (spec & 15) > 3) invalid();
        const width = (spec >> 4) === 1 ? 2 : 1;
        if (table + 64 * width > end) invalid();
        for (let i = 0; i < 64; i++, table += width) {
          if ((width === 1 ? bytes[table] : word(table)) === 0) invalid();
        }
        quantization.add(spec & 15);
      }
      if (table !== end || length === 2) invalid();
    } else if (marker === 0xc4) {
      let table = offset + 2;
      while (table < end) {
        const spec = bytes[table++];
        if ((spec >> 4) > 1 || (spec & 15) > 3 || table + 16 > end) invalid();
        let symbols = 0;
        let codes = 1;
        for (let i = 0; i < 16; i++) {
          const count = bytes[table++];
          symbols += count;
          codes = codes * 2 - count;
          if (codes < 0) invalid();
        }
        if (!symbols || symbols > 256) invalid();
        table += symbols;
        huffman.add(spec);
      }
      if (table !== end || length === 2) invalid();
    } else if (marker === 0xda) {
      const count = bytes[offset + 2];
      if (
        !frame || !count ||
        count > components.size || length !== 6 + count * 2
      ) invalid();
      const start = bytes[end - 3];
      const finish = bytes[end - 2];
      const approximation = bytes[end - 1];
      const selected = new Set<number>();
      for (let i = offset + 3; i < end - 3; i += 2) {
        if (
          !components.has(bytes[i]) || selected.has(bytes[i]) ||
          (bytes[i + 1] >> 4) > 3 || (bytes[i + 1] & 15) > 3
        ) invalid();
        if (
          !quantization.has(componentTables.get(bytes[i])!) ||
          (start === 0 && !huffman.has(bytes[i + 1] >> 4)) ||
          (finish > 0 && !huffman.has(0x10 | (bytes[i + 1] & 15)))
        ) invalid();
        selected.add(bytes[i]);
        if (start === 0) scanned.add(bytes[i]);
      }
      if (
        start > finish || finish > 63 || (approximation >> 4) > 13 ||
        (approximation & 15) > 13 ||
        (!progressive && (start !== 0 || finish !== 63 || approximation !== 0))
      ) invalid();
      offset = end;
      const scanStart = offset;
      while (offset < bytes.length) {
        if (bytes[offset] !== 0xff) {
          offset++;
          continue;
        }
        const next = bytes[offset + 1];
        if (next === 0 || (next >= 0xd0 && next <= 0xd7)) {
          offset += 2;
          continue;
        }
        break;
      }
      if (offset === scanStart) invalid();
      scan = true;
      continue;
    } else if (marker === 0xdd) {
      if (length !== 4) invalid();
    } else if (
      !((marker >= 0xe0 && marker <= 0xef) || marker === 0xfe)
    ) {
      invalid();
    }
    offset = end;
  }
  return invalid();
}

async function* providerChunks(response: Response, signal: AbortSignal) {
  if (!response.body) {
    throw new AvatarError(
      "provider_response_invalid",
      "The image provider returned no response body.",
    );
  }
  const reader = response.body.getReader();
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  signal.addEventListener("abort", cancel, { once: true });
  let received = 0;
  try {
    signal.throwIfAborted();
    while (true) {
      const { done, value } = await reader.read();
      signal.throwIfAborted();
      if (done) break;
      received += value.byteLength;
      if (received > MAX_PROVIDER_BYTES) {
        throw new AvatarError(
          "provider_response_too_large",
          "The image provider response exceeded the size limit.",
        );
      }
      yield value;
    }
  } finally {
    signal.removeEventListener("abort", cancel);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function readProviderJSON(
  response: Response,
  signal: AbortSignal,
) {
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let text = "";
  try {
    for await (const chunk of providerChunks(response, signal)) {
      text += decoder.decode(chunk, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } catch (error) {
    if (error instanceof AvatarError || signal.aborted) throw error;
    throw new AvatarError(
      "provider_response_invalid",
      "The image provider returned an incomplete or invalid response.",
    );
  }
}

/** SSE data fields may span lines, UTF-8 chunks, CRLF pairs, or end at EOF. */
export async function* readProviderEvents(
  response: Response,
  signal: AbortSignal,
) {
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let buffer = "";
  let data: string[] = [];
  let eventName = "";
  function event() {
    const text = data.join("\n");
    data = [];
    const name = eventName;
    eventName = "";
    if (!text) return null;
    if (text === "[DONE]") return { type: "done" };
    try {
      const parsed = JSON.parse(text);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error();
      }
      return { ...parsed, type: parsed.type ?? name };
    } catch {
      throw new AvatarError(
        "provider_response_invalid",
        "The image provider returned an incomplete or invalid event.",
      );
    }
  }
  function line(value: string) {
    if (value.endsWith("\r")) value = value.slice(0, -1);
    if (!value) return event();
    const colon = value.indexOf(":");
    const field = colon < 0 ? value : value.slice(0, colon);
    let content = colon < 0 ? "" : value.slice(colon + 1);
    if (content.startsWith(" ")) content = content.slice(1);
    if (field === "data") data.push(content);
    if (field === "event") eventName = content;
    return null;
  }
  try {
    for await (const chunk of providerChunks(response, signal)) {
      buffer += decoder.decode(chunk, { stream: true });
      let newline: number;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const parsed = line(buffer.slice(0, newline));
        buffer = buffer.slice(newline + 1);
        if (parsed) yield parsed;
      }
    }
    buffer += decoder.decode();
    if (buffer) {
      const parsed = line(buffer);
      if (parsed) yield parsed;
    }
    const pending = event();
    if (pending) yield pending;
  } catch (error) {
    if (error instanceof AvatarError || signal.aborted) throw error;
    throw new AvatarError(
      "provider_response_invalid",
      "The image provider stream was interrupted or invalid.",
    );
  }
}
