import {
  IsString,
  IsOptional,
  IsInt,
  Min,
  Max,
  MaxLength,
} from 'class-validator';

export class CompleteSessionDto {
  @IsInt()
  @Min(1)
  @Max(5)
  @IsOptional()
  rating?: number;

  @IsString()
  @MaxLength(500)
  @IsOptional()
  note?: string;
}

export class ExerciseResponseDto {
  id: string;
  type: string;
  title: string;
  description: string;
  durationSeconds: number;
  contentKind: string;
  contentText: string | null;
  audioUrl: string | null;
  tags: string[];
}

export class StartSessionResponseDto {
  sessionId: string;
  startedAt: Date;
}

export class CompleteSessionResponseDto {
  ok: boolean;
  stats: {
    totalExercisesCompleted: number;
  };
}
