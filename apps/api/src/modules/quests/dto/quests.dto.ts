import { IsString, IsOptional, IsInt, Min, Max } from 'class-validator';

export class CompleteQuestDto {
  @IsString()
  @IsOptional()
  reflectionNote?: string;

  @IsInt()
  @IsOptional()
  @Min(1)
  @Max(5)
  rating?: number;
}

export class QuestResponseDto {
  id: string;
  localDate: string;
  status: string;
  assignedAt: Date;
  completedAt: Date | null;
  template: {
    id: string;
    type: string;
    title: string;
    description: string;
    estimatedMinutes: number;
    difficulty: number;
    tags: string[];
    instructions: unknown;
  };
}

export class QuestCompletionResponseDto {
  questId: string;
  status: string;
  completedAt: Date;
  streakDays: number;
  badgesEarned: Array<{
    code: string;
    title: string;
  }>;
}
