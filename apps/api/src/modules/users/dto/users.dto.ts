import {
  IsString,
  IsOptional,
  IsBoolean,
  IsInt,
  Min,
  Max,
  Matches,
  MaxLength,
  IsIn,
} from 'class-validator';

export class UpdateProfileDto {
  @IsString()
  @IsOptional()
  @MaxLength(40)
  displayName?: string;

  @IsString()
  @IsOptional()
  @MaxLength(64)
  timezone?: string;
}

export class UpdateSettingsDto {
  @IsString()
  @IsOptional()
  @Matches(/^\d{2}:\d{2}:\d{2}$/, {
    message: 'dailyQuestTimeLocal must be in HH:mm:ss format',
  })
  dailyQuestTimeLocal?: string;

  @IsString()
  @IsOptional()
  @Matches(/^\d{2}:\d{2}:\d{2}$/, {
    message: 'quietHoursStartLocal must be in HH:mm:ss format',
  })
  quietHoursStartLocal?: string;

  @IsString()
  @IsOptional()
  @Matches(/^\d{2}:\d{2}:\d{2}$/, {
    message: 'quietHoursEndLocal must be in HH:mm:ss format',
  })
  quietHoursEndLocal?: string;

  @IsBoolean()
  @IsOptional()
  remindersEnabled?: boolean;

  @IsInt()
  @IsOptional()
  @Min(1)
  @Max(7)
  nudgeAfterDaysInactive?: number;

  @IsBoolean()
  @IsOptional()
  shareMoodInCircles?: boolean;

  @IsString()
  @IsOptional()
  @IsIn(['friendly', 'professional', 'motivational', 'gentle'])
  aiTone?: string;

  @IsString()
  @IsOptional()
  @IsIn(['standard', 'enhanced'])
  privacyMode?: string;
}

export class RegisterDeviceDto {
  @IsString()
  apnsToken: string;

  @IsString()
  @IsOptional()
  deviceModel?: string;

  @IsString()
  @IsOptional()
  osVersion?: string;

  @IsString()
  @IsOptional()
  locale?: string;

  @IsString()
  @IsOptional()
  timezone?: string;
}

export class UserProfileResponseDto {
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
