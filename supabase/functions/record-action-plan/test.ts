import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { UUID_REGEX, VALID_ITEM_TYPES, VALID_STATUSES } from "./index.ts";

Deno.test("record-action-plan constants", () => {
  assert(UUID_REGEX.test("d2719d6b-7a3c-4c6a-9c2b-91a2c3a9d5d6"));
  assertEquals(VALID_STATUSES.includes("scheduled"), true);
  assertEquals(VALID_ITEM_TYPES.includes("exercise"), true);
});
