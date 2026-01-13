import {
  getLocalDate,
  getYesterday,
  getTomorrow,
  daysBetween,
  isValidDateString,
  calculateQuietHoursSpan,
} from './date.utils';

describe('Date Utilities', () => {
  describe('getLocalDate', () => {
    it('should return date in YYYY-MM-DD format for UTC timezone', () => {
      const testDate = new Date('2024-06-15T12:00:00Z');
      const result = getLocalDate('UTC', testDate);
      expect(result).toBe('2024-06-15');
    });

    it('should handle timezone conversion correctly (US Eastern)', () => {
      // 2024-06-15 01:00 UTC = 2024-06-14 21:00 Eastern (still previous day)
      const testDate = new Date('2024-06-15T01:00:00Z');
      const result = getLocalDate('America/New_York', testDate);
      expect(result).toBe('2024-06-14');
    });

    it('should handle timezone conversion correctly (Japan)', () => {
      // 2024-06-15 20:00 UTC = 2024-06-16 05:00 Tokyo (next day)
      const testDate = new Date('2024-06-15T20:00:00Z');
      const result = getLocalDate('Asia/Tokyo', testDate);
      expect(result).toBe('2024-06-16');
    });

    it('should handle year boundary correctly', () => {
      const testDate = new Date('2024-01-01T01:00:00Z');
      const result = getLocalDate('America/Los_Angeles', testDate);
      // 2024-01-01 01:00 UTC = 2023-12-31 17:00 Pacific (previous year)
      expect(result).toBe('2023-12-31');
    });

    it('should handle month boundary correctly', () => {
      const testDate = new Date('2024-03-01T05:00:00Z');
      const result = getLocalDate('America/New_York', testDate);
      // 2024-03-01 05:00 UTC = 2024-03-01 00:00 Eastern (same day at midnight)
      expect(result).toBe('2024-03-01');
    });
  });

  describe('getYesterday', () => {
    it('should return the previous day', () => {
      expect(getYesterday('2024-06-15')).toBe('2024-06-14');
    });

    it('should handle month boundary (beginning of month)', () => {
      expect(getYesterday('2024-06-01')).toBe('2024-05-31');
    });

    it('should handle year boundary', () => {
      expect(getYesterday('2024-01-01')).toBe('2023-12-31');
    });

    it('should handle February in leap year', () => {
      expect(getYesterday('2024-03-01')).toBe('2024-02-29');
    });

    it('should handle February in non-leap year', () => {
      expect(getYesterday('2023-03-01')).toBe('2023-02-28');
    });
  });

  describe('getTomorrow', () => {
    it('should return the next day', () => {
      expect(getTomorrow('2024-06-15')).toBe('2024-06-16');
    });

    it('should handle month boundary (end of month)', () => {
      expect(getTomorrow('2024-06-30')).toBe('2024-07-01');
    });

    it('should handle year boundary', () => {
      expect(getTomorrow('2024-12-31')).toBe('2025-01-01');
    });

    it('should handle leap year February', () => {
      expect(getTomorrow('2024-02-28')).toBe('2024-02-29');
      expect(getTomorrow('2024-02-29')).toBe('2024-03-01');
    });
  });

  describe('daysBetween', () => {
    it('should return 0 for same date', () => {
      expect(daysBetween('2024-06-15', '2024-06-15')).toBe(0);
    });

    it('should return 1 for consecutive days', () => {
      expect(daysBetween('2024-06-15', '2024-06-16')).toBe(1);
    });

    it('should return correct number of days regardless of order', () => {
      expect(daysBetween('2024-06-15', '2024-06-20')).toBe(5);
      expect(daysBetween('2024-06-20', '2024-06-15')).toBe(5);
    });

    it('should handle month boundary', () => {
      expect(daysBetween('2024-05-30', '2024-06-02')).toBe(3);
    });

    it('should handle year boundary', () => {
      expect(daysBetween('2023-12-30', '2024-01-02')).toBe(3);
    });
  });

  describe('isValidDateString', () => {
    it('should return true for valid date strings', () => {
      expect(isValidDateString('2024-06-15')).toBe(true);
      expect(isValidDateString('2024-01-01')).toBe(true);
      expect(isValidDateString('2024-12-31')).toBe(true);
    });

    it('should return false for invalid format', () => {
      expect(isValidDateString('2024/06/15')).toBe(false);
      expect(isValidDateString('06-15-2024')).toBe(false);
      expect(isValidDateString('2024-6-15')).toBe(false);
      expect(isValidDateString('2024-06-5')).toBe(false);
    });

    it('should return false for invalid dates', () => {
      expect(isValidDateString('2024-13-01')).toBe(false); // Invalid month
      expect(isValidDateString('2024-06-32')).toBe(false); // Invalid day
      expect(isValidDateString('2023-02-29')).toBe(false); // Feb 29 in non-leap year
    });

    it('should return true for leap year Feb 29', () => {
      expect(isValidDateString('2024-02-29')).toBe(true);
    });
  });

  describe('calculateQuietHoursSpan', () => {
    it('should calculate daytime span correctly', () => {
      expect(calculateQuietHoursSpan('09:00', '17:00')).toBe(8);
    });

    it('should calculate span with minutes', () => {
      expect(calculateQuietHoursSpan('09:30', '17:45')).toBe(8.25);
    });

    it('should handle overnight span (22:00 to 07:00)', () => {
      expect(calculateQuietHoursSpan('22:00', '07:00')).toBe(9);
    });

    it('should handle overnight span crossing midnight', () => {
      expect(calculateQuietHoursSpan('23:00', '06:00')).toBe(7);
    });

    it('should handle same start and end (24h span treated as overnight)', () => {
      // When end <= start, we add 24 hours, so 09:00 to 09:00 = 24 hours
      expect(calculateQuietHoursSpan('09:00', '09:00')).toBe(24);
    });
  });
});

describe('Streak Calculation Logic', () => {
  /**
   * Test the streak calculation algorithm directly.
   * This mirrors the logic in QuestsService.updateStreak
   */
  function calculateNewStreak(
    currentStreak: number,
    lastDate: string | null,
    completedDate: string,
  ): number {
    if (!lastDate) {
      return 1; // First completion
    }

    const yesterday = getYesterday(completedDate);

    if (lastDate === yesterday) {
      // Consecutive day - extend streak
      return currentStreak + 1;
    } else if (lastDate === completedDate) {
      // Same day - keep streak
      return currentStreak;
    } else {
      // Streak broken - start fresh
      return 1;
    }
  }

  describe('calculateNewStreak', () => {
    it('should start streak at 1 for first completion', () => {
      expect(calculateNewStreak(0, null, '2024-06-15')).toBe(1);
    });

    it('should extend streak for consecutive days', () => {
      expect(calculateNewStreak(1, '2024-06-14', '2024-06-15')).toBe(2);
      expect(calculateNewStreak(5, '2024-06-14', '2024-06-15')).toBe(6);
      expect(calculateNewStreak(29, '2024-06-14', '2024-06-15')).toBe(30);
    });

    it('should keep streak for same day completion', () => {
      expect(calculateNewStreak(3, '2024-06-15', '2024-06-15')).toBe(3);
    });

    it('should reset streak after missing a day', () => {
      expect(calculateNewStreak(5, '2024-06-13', '2024-06-15')).toBe(1);
    });

    it('should reset streak after missing multiple days', () => {
      expect(calculateNewStreak(10, '2024-06-01', '2024-06-15')).toBe(1);
    });

    it('should handle month boundary correctly', () => {
      // June 1 follows May 31
      expect(calculateNewStreak(5, '2024-05-31', '2024-06-01')).toBe(6);
    });

    it('should handle year boundary correctly', () => {
      // Jan 1, 2025 follows Dec 31, 2024
      expect(calculateNewStreak(10, '2024-12-31', '2025-01-01')).toBe(11);
    });

    it('should handle leap year correctly', () => {
      // March 1, 2024 follows Feb 29, 2024
      expect(calculateNewStreak(28, '2024-02-29', '2024-03-01')).toBe(29);
    });
  });
});

describe('Badge Evaluation Logic', () => {
  /**
   * Test the badge threshold evaluation logic.
   * This mirrors the logic in QuestsService.evaluateBadges
   */
  const streakBadges = [
    { threshold: 3, code: 'streak_3' },
    { threshold: 7, code: 'streak_7' },
    { threshold: 14, code: 'streak_14' },
    { threshold: 30, code: 'streak_30' },
  ];

  function getEarnedBadgeCodes(
    currentStreak: number,
    existingBadgeCodes: string[],
  ): string[] {
    const existingSet = new Set(existingBadgeCodes);
    const earned: string[] = [];

    for (const { threshold, code } of streakBadges) {
      if (currentStreak >= threshold && !existingSet.has(code)) {
        earned.push(code);
      }
    }

    return earned;
  }

  it('should not earn any badges with streak < 3', () => {
    expect(getEarnedBadgeCodes(1, [])).toEqual([]);
    expect(getEarnedBadgeCodes(2, [])).toEqual([]);
  });

  it('should earn streak_3 badge at exactly 3 days', () => {
    expect(getEarnedBadgeCodes(3, [])).toEqual(['streak_3']);
  });

  it('should earn streak_7 badge at exactly 7 days', () => {
    expect(getEarnedBadgeCodes(7, ['streak_3'])).toEqual(['streak_7']);
  });

  it('should earn multiple badges if streak jumps', () => {
    // If streak jumps from 2 to 8, should earn both streak_3 and streak_7
    expect(getEarnedBadgeCodes(8, [])).toEqual(['streak_3', 'streak_7']);
  });

  it('should not award already earned badges', () => {
    expect(getEarnedBadgeCodes(10, ['streak_3', 'streak_7'])).toEqual([]);
  });

  it('should handle all badges at 30+ days', () => {
    expect(getEarnedBadgeCodes(30, [])).toEqual([
      'streak_3',
      'streak_7',
      'streak_14',
      'streak_30',
    ]);
  });

  it('should only award missing badges', () => {
    expect(getEarnedBadgeCodes(30, ['streak_3', 'streak_14'])).toEqual([
      'streak_7',
      'streak_30',
    ]);
  });
});
