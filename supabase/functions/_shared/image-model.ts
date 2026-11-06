// Image model for generate-art and generate-profile-picture (docs/decisions.md,
// "Image model replacement"). The previous model shut down on 2026-12-01.
// gpt-image-2.6-flare at quality "low", 1024x1024, measured 2026-11-06: 824 image
// output tokens at $30/M = $0.02472. Each streamed partial image adds 100 output
// tokens ($0.003); text input is $5/M. Quality is explicit so the price is fixed.
export const IMAGE_MODEL = "gpt-image-2.6-flare";
export const IMAGE_QUALITY = "low";

// UTF-8 prompt bytes bound text tokens; 1024 more tokens cover request framing.
export function imageReserveMicrodollars(
  prompt: string,
  streaming: boolean | undefined,
): number {
  return Math.ceil(
    (new TextEncoder().encode(JSON.stringify(prompt)).length + 1024) * 5 +
      24_720 + (streaming ? 2 * 3_000 : 0),
  );
}
