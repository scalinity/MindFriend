// Only deno.test.json maps production roots to this generated test root.
import { trustedChain } from "./test-fixtures.ts";

// Production trusts RSA roots ahead of Apple Root CA - G3, and Apple's verifier tries
// every root in order, so the tests put Apple's real RSA root first as well.
const production = await Deno.readTextFile(new URL("./apple-roots.ts", import.meta.url));
const [appleRootCA] = [...production.matchAll(/"([A-Za-z0-9+/=]{200,})"/g)].map((match) => match[1]);

export const APPLE_ROOT_CERTIFICATES = [appleRootCA, trustedChain.root.toString("base64")];
