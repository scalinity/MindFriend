import { IsString, IsNotEmpty } from 'class-validator';

export class AppleTransactionDto {
  @IsString()
  @IsNotEmpty()
  signedTransactionJws: string;
}

export class EntitlementsDto {
  tier: 'free' | 'premium';
  aiMessagesPerDayLimit: number;
  aiMessagesUsedToday: number;
}

export class TransactionResponseDto {
  entitlements: EntitlementsDto;
  subscription: {
    status: string;
    currentPeriodEnd: Date | null;
  };
}
