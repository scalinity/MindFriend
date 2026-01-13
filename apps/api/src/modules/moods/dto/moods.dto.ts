import { IsInt, IsOptional, IsString, Min, Max, IsIn } from 'class-validator';

export class CreateMoodDto {
  @IsInt()
  @Min(1)
  @Max(5)
  moodScore: number;

  @IsInt()
  @IsOptional()
  @Min(1)
  @Max(5)
  anxietyScore?: number;

  @IsInt()
  @IsOptional()
  @Min(1)
  @Max(5)
  energyScore?: number;

  @IsString()
  @IsOptional()
  note?: string;

  @IsString()
  @IsOptional()
  @IsIn(['manual', 'quest', 'circle_checkin'])
  source?: string;
}

export class MoodEntryResponseDto {
  id: string;
  localDate: string;
  moodScore: number;
  anxietyScore: number | null;
  energyScore: number | null;
  note: string | null;
  source: string;
  createdAt: Date;
}

export class MoodHistoryResponseDto {
  entries: MoodEntryResponseDto[];
  summary: {
    avgMoodScore: number;
    avgAnxietyScore: number | null;
    avgEnergyScore: number | null;
    totalEntries: number;
  };
}
