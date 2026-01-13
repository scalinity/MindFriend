// Crisis detection keywords and response template
// IMPORTANT: This is a safety-critical module

export const CRISIS_KEYWORDS = [
  "kill myself",
  "want to die",
  "end my life",
  "suicide",
  "suicidal",
  "self-harm",
  "hurt myself",
  "cutting myself",
  "don't want to live",
  "no reason to live",
  "better off dead",
  "can't go on",
  "end it all",
  "take my life",
];

export function detectCrisis(content: string): boolean {
  const lowerContent = content.toLowerCase();
  return CRISIS_KEYWORDS.some((keyword) => lowerContent.includes(keyword));
}

export const CRISIS_RESPONSE = `I hear that you're going through something really difficult right now, and I'm genuinely concerned about your wellbeing.

What you're feeling matters, and you don't have to face this alone. Please reach out to someone who can help:

**988 Suicide & Crisis Lifeline**
- Call or text: **988** (US)
- Available 24/7

**Crisis Text Line**
- Text **HOME** to **741741** (US)
- Text **HELLO** to **686868** (Canada)

**International Association for Suicide Prevention**
- https://www.iasp.info/resources/Crisis_Centres/

These trained counselors are here to listen without judgment and can provide the support you need right now.

I care about you. Please reach out to one of these resources.`;
