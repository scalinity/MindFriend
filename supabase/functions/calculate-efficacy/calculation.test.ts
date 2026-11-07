import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1.0.19";
import { calculateEfficacy } from "./calculation.ts";
import fixtures from "./fixtures.json" with { type: "json" };

for (const fixture of fixtures) {
  Deno.test(`Swift/server efficacy parity: ${fixture.name}`, () => {
    const result = calculateEfficacy(fixture.scores.map((compositeScore, i) => ({
      timestamp: new Date(i * 30_000).toISOString(), secondsFromStart: i * 30, compositeScore,
    })));
    assertAlmostEquals(result.efficacyScore, fixture.efficacyScore, 1e-10);
    assertAlmostEquals(result.netEmotionalChange, Math.max(-1, Math.min(1, fixture.scores.at(-1)! - fixture.scores[0])), 1e-10);
    assertEquals(Number.isFinite(result.efficacyScore), true);
  });
}
