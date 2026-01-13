import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

export class CreateConversationDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  title?: string;
}

export class SendMessageDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(2000)
  content: string;
}

export class ConversationResponseDto {
  id: string;
  title: string | null;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  lastMessage?: {
    role: string;
    content: string;
    createdAt: Date;
  };
}

export class MessageResponseDto {
  id: string;
  role: string;
  content: string;
  createdAt: Date;
  blocked: boolean;
}

export class SendMessageResponseDto {
  userMessage: MessageResponseDto;
  assistantMessage: MessageResponseDto;
  quotaRemaining: number;
  crisisDetected?: boolean;
}
