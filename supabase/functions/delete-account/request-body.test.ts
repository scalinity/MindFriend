import { assertEquals } from "jsr:@std/assert@1";
import { parseDeletionRequest } from "./request-body.ts";

Deno.test("an empty body from released clients is accepted", () => {
  assertEquals(parseDeletionRequest(""), {});
  assertEquals(parseDeletionRequest("  \n"), {});
});

Deno.test("a bound request keeps its expected owner", () => {
  assertEquals(parseDeletionRequest('{"expected_owner":"abc"}'), { expected_owner: "abc" });
  assertEquals(parseDeletionRequest("{}"), {});
});

Deno.test("malformed or non-object bodies are rejected", () => {
  assertEquals(parseDeletionRequest("{"), null);
  assertEquals(parseDeletionRequest("[]"), null);
  assertEquals(parseDeletionRequest("null"), null);
  assertEquals(parseDeletionRequest('"text"'), null);
});
