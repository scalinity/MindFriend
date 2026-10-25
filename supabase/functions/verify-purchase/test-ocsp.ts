// Test-only transport: all OCSP responses are generated locally and signatures
// are checked by the unchanged Apple verifier. No socket or provider is used.
import { getOCSPResponse } from "./test-fixtures.ts";
export const Headers = globalThis.Headers;
export default function fetch(url: string) {
  const data = getOCSPResponse(url);
  return Promise.resolve({ ok: !!data, buffer: () => Promise.resolve(data) });
}
