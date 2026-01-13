import {
  IsString,
  IsNotEmpty,
  MaxLength,
  IsInt,
  Min,
  Max,
  IsOptional,
  Matches,
} from 'class-validator';

export class CreateCircleDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(40)
  name: string;

  @IsString()
  @IsOptional()
  @MaxLength(160)
  description?: string;

  @IsInt()
  @Min(2)
  @Max(8)
  @IsOptional()
  maxMembers?: number;
}

export class JoinCircleDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(12)
  @Matches(/^[A-Z0-9]{12}$/, {
    message: 'Invite code must be 12 uppercase alphanumeric characters',
  })
  inviteCode: string;
}

export class CircleCheckInDto {
  @IsString()
  @IsNotEmpty()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, {
    message: 'localDate must be in YYYY-MM-DD format',
  })
  localDate: string;

  @IsString()
  @IsOptional()
  @MaxLength(8)
  moodEmoji?: string;

  @IsString()
  @IsOptional()
  @MaxLength(280)
  bodyText?: string;
}

export class CircleResponseDto {
  id: string;
  name: string;
  description: string | null;
  isPrivate: boolean;
  inviteCode: string;
  maxMembers: number;
  memberCount: number;
  role: string;
  createdAt: Date;
}

export class CircleListItemDto {
  id: string;
  name: string;
  memberCount: number;
  role: string;
}

export class CircleMemberDto {
  userId: string;
  handle: string;
  displayName: string;
  role: string;
  joinedAt: Date;
}

export class CircleDetailDto {
  id: string;
  name: string;
  description: string | null;
  isPrivate: boolean;
  inviteCode: string;
  maxMembers: number;
  members: CircleMemberDto[];
  createdAt: Date;
}

export class CirclePostDto {
  id: string;
  kind: string;
  user: {
    handle: string;
    displayName: string;
  };
  moodEmoji: string | null;
  bodyText: string | null;
  localDate: string;
  createdAt: Date;
}

export class JoinCircleResponseDto {
  circleId: string;
  role: string;
}
