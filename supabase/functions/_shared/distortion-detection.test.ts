/**
 * Unit tests for multilingual cognitive distortion detection
 * Tests EN, ES, and PT-BR pattern matching
 */

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { detectDistortion } from "./distortion-detection.ts";

// English Tests
Deno.test("EN: All-or-Nothing - 'always' keyword", () => {
  const result = detectDistortion("I always mess everything up and never do anything right", "en", 0.7);
  assertEquals(result?.distortionCode, "AON");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("EN: Catastrophizing - 'worst case' phrase", () => {
  const result = detectDistortion("This is the worst case scenario everything is going to be ruined", "en", 0.7);
  assertEquals(result?.distortionCode, "CAT");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("EN: Mind Reading - 'they must think'", () => {
  const result = detectDistortion("They must think I'm so stupid and judging me constantly", "en", 0.7);
  assertEquals(result?.distortionCode, "MIND");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("EN: What-If Thinking - 'what if' phrase", () => {
  const result = detectDistortion(
    "What if everything goes wrong tomorrow and I fail completely",
    "en",
    0.7,
  );
  assertEquals(result?.distortionCode, "WHAT");
  assertEquals(result && result.confidence >= 0.7, true);
});

// Spanish Tests
Deno.test("ES: All-or-Nothing - 'siempre' keyword", () => {
  const result = detectDistortion("Siempre me sale todo mal y nunca hago nada bien", "es", 0.7);
  assertEquals(result?.distortionCode, "AON");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("ES: All-or-Nothing - 'nunca' keyword", () => {
  const result = detectDistortion("Nunca hago nada bien en mi vida siempre fracaso", "es", 0.7);
  assertEquals(result?.distortionCode, "AON");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("ES: Catastrophizing - 'peor caso'", () => {
  const result = detectDistortion("Este es el peor caso posible todo va a salir mal", "es", 0.7);
  assertEquals(result?.distortionCode, "CAT");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("ES: Labeling - 'soy un fracaso'", () => {
  const result = detectDistortion("Soy un fracaso total en todo lo que hago soy un idiota", "es", 0.7);
  assertEquals(result?.distortionCode, "LAB");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("ES: Should Statements - 'debería' keyword", () => {
  const result = detectDistortion("Debería ser mejor en esto debo mejorar tengo que hacerlo", "es", 0.7);
  assertEquals(result?.distortionCode, "SHO");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("ES: What-If Thinking - 'qué pasa si'", () => {
  const result = detectDistortion(
    "Qué pasa si todo sale mal mañana y pierdo todo",
    "es",
    0.7,
  );
  assertEquals(result?.distortionCode, "WHAT");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("ES: Regret Orientation - 'si solo'", () => {
  const result = detectDistortion(
    "Si solo hubiera estudiado más tiempo no debería haber salido",
    "es",
    0.7,
  );
  assertEquals(result?.distortionCode, "RG");
  assertEquals(result && result.confidence >= 0.7, true);
});

// Portuguese Tests
Deno.test("PT-BR: All-or-Nothing - 'sempre' keyword", () => {
  const result = detectDistortion("Sempre dá errado para mim nunca faço nada direito", "pt-BR", 0.7);
  assertEquals(result?.distortionCode, "AON");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: All-or-Nothing - 'nunca' keyword", () => {
  const result = detectDistortion(
    "Nunca consigo fazer nada direito sempre falho em tudo",
    "pt-BR",
    0.7,
  );
  assertEquals(result?.distortionCode, "AON");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: Catastrophizing - 'pior caso'", () => {
  const result = detectDistortion("Este é o pior caso possível tudo vai dar errado", "pt-BR", 0.7);
  assertEquals(result?.distortionCode, "CAT");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: Labeling - 'sou um fracasso'", () => {
  const result = detectDistortion(
    "Sou um fracasso completo em tudo sou um idiota",
    "pt-BR",
    0.7,
  );
  assertEquals(result?.distortionCode, "LAB");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: Should Statements - 'deveria' keyword", () => {
  const result = detectDistortion(
    "Deveria ser melhor nisso agora devo melhorar tenho que fazer",
    "pt-BR",
    0.7,
  );
  assertEquals(result?.distortionCode, "SHO");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: What-If Thinking - 'e se'", () => {
  const result = detectDistortion("E se tudo der errado amanhã e perder tudo", "pt-BR", 0.7);
  assertEquals(result?.distortionCode, "WHAT");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: Regret Orientation - 'se apenas'", () => {
  const result = detectDistortion(
    "Se apenas tivesse estudado mais tempo não deveria ter saído",
    "pt-BR",
    0.7,
  );
  assertEquals(result?.distortionCode, "RG");
  assertEquals(result && result.confidence >= 0.7, true);
});

Deno.test("PT-BR: Mind Reading - 'devem pensar'", () => {
  const result = detectDistortion(
    "Eles devem pensar que sou idiota estão me julgando agora",
    "pt-BR",
    0.7,
  );
  assertEquals(result?.distortionCode, "MIND");
  assertEquals(result && result.confidence >= 0.7, true);
});

// Edge Cases
Deno.test("Short messages are ignored (< 5 words)", () => {
  const result = detectDistortion("Always fails", "en", 0.7);
  assertEquals(result, null);
});

Deno.test("No detection below threshold", () => {
  const result = detectDistortion(
    "I might try something new tomorrow",
    "en",
    0.85,
  );
  assertEquals(result, null); // Low confidence, filtered out
});

Deno.test("Fallback to English for unknown language", () => {
  const result = detectDistortion("I always fail at everything I do nothing works for me", "fr", 0.7);
  assertEquals(result?.distortionCode, "AON"); // Uses EN patterns as fallback
});

Deno.test("Case insensitive matching", () => {
  const result = detectDistortion("SIEMPRE ME SALE MAL TODO Y NUNCA FUNCIONA NADA", "es", 0.7);
  assertEquals(result?.distortionCode, "AON");
});
