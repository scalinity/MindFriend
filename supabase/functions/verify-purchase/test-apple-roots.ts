// Only deno.test.json maps production roots to this generated test root.
import { trustedChain } from "./test-fixtures.ts";
export const APPLE_ROOT_CERTIFICATES = [trustedChain.root.toString("base64")];
