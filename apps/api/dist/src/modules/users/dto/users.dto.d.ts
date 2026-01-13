export declare class UpdateProfileDto {
    displayName?: string;
    timezone?: string;
}
export declare class UpdateSettingsDto {
    dailyQuestTimeLocal?: string;
    quietHoursStartLocal?: string;
    quietHoursEndLocal?: string;
    remindersEnabled?: boolean;
    nudgeAfterDaysInactive?: number;
    shareMoodInCircles?: boolean;
    aiTone?: string;
    privacyMode?: string;
}
export declare class RegisterDeviceDto {
    apnsToken: string;
    deviceModel?: string;
    osVersion?: string;
    locale?: string;
    timezone?: string;
}
export declare class UserProfileResponseDto {
    id: string;
    handle: string;
    displayName: string;
    email: string | null;
    timezone: string;
    createdAt: Date;
    settings: {
        dailyQuestTimeLocal: string;
        quietHoursStartLocal: string | null;
        quietHoursEndLocal: string | null;
        remindersEnabled: boolean;
        nudgeAfterDaysInactive: number;
        shareMoodInCircles: boolean;
        aiTone: string;
        privacyMode: string;
    };
    stats: {
        currentStreakDays: number;
        longestStreakDays: number;
        totalQuestsCompleted: number;
        totalExercisesCompleted: number;
    };
    entitlements: {
        tier: 'free' | 'premium';
        dailyAiQuota: number;
        dailyAiUsed: number;
    };
    badges: Array<{
        code: string;
        title: string;
        earnedAt: Date;
    }>;
}
