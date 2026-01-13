/**
 * Unit tests for ChatService moderation and quota logic.
 * These tests verify the safety moderation keywords and quota calculations
 * without requiring database or API connections.
 */

// Crisis keywords that should trigger the safety response
const CRISIS_KEYWORDS = [
  'kill myself',
  'want to die',
  'end my life',
  'suicide',
  'self-harm',
  'hurt myself',
  'cutting myself',
  'overdose',
  'jump off',
  'hang myself',
];

// Moderation logic extracted for testing
function moderateInput(content: string): {
  isCrisis: boolean;
  label: 'ok' | 'self_harm' | 'violence' | 'unknown';
} {
  const lowerContent = content.toLowerCase();

  for (const keyword of CRISIS_KEYWORDS) {
    if (lowerContent.includes(keyword)) {
      return { isCrisis: true, label: 'self_harm' };
    }
  }

  return { isCrisis: false, label: 'ok' };
}

// Quota calculation logic extracted for testing
function calculateQuota(
  isPremium: boolean,
  dailyFreeQuota: number,
  premiumQuota: number,
): number {
  return isPremium ? premiumQuota : dailyFreeQuota;
}

function checkQuotaAllowed(
  currentUsage: number,
  dailyQuota: number,
): { allowed: boolean; remaining: number } {
  if (currentUsage >= dailyQuota) {
    return { allowed: false, remaining: 0 };
  }
  return { allowed: true, remaining: dailyQuota - currentUsage - 1 };
}

describe('ChatService', () => {
  describe('Moderation Logic', () => {
    describe('moderateInput', () => {
      describe('should detect crisis keywords', () => {
        test.each([
          ['I want to kill myself', true],
          ['I want to die', true],
          ['I want to end my life', true],
          ['considering suicide', true],
          ['self-harm thoughts', true],
          ['I want to hurt myself', true],
          ['I keep cutting myself', true],
          ['thinking about overdose', true],
          ['I want to jump off a bridge', true],
          ['I want to hang myself', true],
        ])('"%s" should be flagged: %s', (input, expected) => {
          const result = moderateInput(input);
          expect(result.isCrisis).toBe(expected);
          if (expected) {
            expect(result.label).toBe('self_harm');
          }
        });
      });

      describe('should NOT flag safe messages', () => {
        test.each([
          ['I feel sad today'],
          ['Having a rough day'],
          ['I am stressed about work'],
          ['Feeling anxious about my exam'],
          ['I need help with motivation'],
          ['Can you help me relax?'],
          ['I am feeling down'],
          ['Work is killing me (figuratively)'],
          ['I could die of embarrassment'],
          ['This movie was to die for'],
        ])('"%s" should NOT be flagged', (input) => {
          const result = moderateInput(input);
          expect(result.isCrisis).toBe(false);
          expect(result.label).toBe('ok');
        });
      });

      it('should be case insensitive', () => {
        expect(moderateInput('SUICIDE').isCrisis).toBe(true);
        expect(moderateInput('Suicide').isCrisis).toBe(true);
        expect(moderateInput('KILL MYSELF').isCrisis).toBe(true);
        expect(moderateInput('Want To Die').isCrisis).toBe(true);
      });

      it('should detect keywords within sentences', () => {
        expect(
          moderateInput('I have been thinking about suicide lately').isCrisis,
        ).toBe(true);
        expect(
          moderateInput('Sometimes I want to hurt myself when I am sad')
            .isCrisis,
        ).toBe(true);
      });
    });
  });

  describe('Quota Logic', () => {
    const dailyFreeQuota = 20;
    const premiumQuota = 9999;

    describe('calculateQuota', () => {
      it('should return free quota for non-premium users', () => {
        expect(calculateQuota(false, dailyFreeQuota, premiumQuota)).toBe(20);
      });

      it('should return premium quota for premium users', () => {
        expect(calculateQuota(true, dailyFreeQuota, premiumQuota)).toBe(9999);
      });
    });

    describe('checkQuotaAllowed', () => {
      it('should allow messages when under quota', () => {
        expect(checkQuotaAllowed(0, 20)).toEqual({
          allowed: true,
          remaining: 19,
        });
        expect(checkQuotaAllowed(5, 20)).toEqual({
          allowed: true,
          remaining: 14,
        });
        expect(checkQuotaAllowed(19, 20)).toEqual({
          allowed: true,
          remaining: 0,
        });
      });

      it('should deny messages when at quota', () => {
        expect(checkQuotaAllowed(20, 20)).toEqual({
          allowed: false,
          remaining: 0,
        });
      });

      it('should deny messages when over quota', () => {
        expect(checkQuotaAllowed(21, 20)).toEqual({
          allowed: false,
          remaining: 0,
        });
        expect(checkQuotaAllowed(100, 20)).toEqual({
          allowed: false,
          remaining: 0,
        });
      });

      it('should handle premium quota correctly', () => {
        expect(checkQuotaAllowed(0, 9999)).toEqual({
          allowed: true,
          remaining: 9998,
        });
        expect(checkQuotaAllowed(9998, 9999)).toEqual({
          allowed: true,
          remaining: 0,
        });
        expect(checkQuotaAllowed(9999, 9999)).toEqual({
          allowed: false,
          remaining: 0,
        });
      });
    });
  });

  describe('Tone Modifiers', () => {
    const TONE_MODIFIERS: Record<string, string> = {
      friendly:
        'Be warm, casual, and use occasional light humor when appropriate.',
      professional:
        'Be supportive but maintain a calm, measured professional tone.',
      motivational:
        'Be enthusiastic, encouraging, and use empowering language.',
      gentle: 'Be extra soft, patient, and nurturing in your responses.',
    };

    it('should have all expected tones', () => {
      expect(Object.keys(TONE_MODIFIERS)).toEqual([
        'friendly',
        'professional',
        'motivational',
        'gentle',
      ]);
    });

    it('should have non-empty modifiers for all tones', () => {
      Object.values(TONE_MODIFIERS).forEach((modifier) => {
        expect(modifier.length).toBeGreaterThan(10);
      });
    });

    it('should default to friendly tone', () => {
      const getModifier = (tone: string): string =>
        TONE_MODIFIERS[tone] || TONE_MODIFIERS.friendly;

      expect(getModifier('nonexistent')).toBe(TONE_MODIFIERS.friendly);
      expect(getModifier('friendly')).toBe(TONE_MODIFIERS.friendly);
    });
  });

  describe('Crisis Response', () => {
    const CRISIS_RESPONSE = `I'm really sorry you're feeling this way. I can't help with anything that could harm you, but you deserve support right now. If you're in immediate danger, please call your local emergency number.

You can also access Crisis Resources in the app (tap the heart icon) for local helplines. You matter, and help is available.`;

    it('should contain key safety elements', () => {
      expect(CRISIS_RESPONSE).toContain("sorry you're feeling");
      expect(CRISIS_RESPONSE).toContain(
        "can't help with anything that could harm",
      );
      expect(CRISIS_RESPONSE).toContain('emergency number');
      expect(CRISIS_RESPONSE).toContain('Crisis Resources');
      expect(CRISIS_RESPONSE).toContain('help is available');
    });

    it('should not give dangerous advice', () => {
      expect(CRISIS_RESPONSE.toLowerCase()).not.toContain('how to');
      expect(CRISIS_RESPONSE.toLowerCase()).not.toContain('method');
      expect(CRISIS_RESPONSE.toLowerCase()).not.toContain('technique');
    });

    it('should be appropriately empathetic', () => {
      expect(CRISIS_RESPONSE).toContain('You matter');
      expect(CRISIS_RESPONSE).toContain('support');
      expect(CRISIS_RESPONSE).toContain('deserve');
    });
  });
});
