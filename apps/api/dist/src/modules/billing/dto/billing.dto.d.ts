export declare class AppleTransactionDto {
    signedTransactionJws: string;
}
export declare class EntitlementsDto {
    tier: 'free' | 'premium';
    aiMessagesPerDayLimit: number;
    aiMessagesUsedToday: number;
}
export declare class TransactionResponseDto {
    entitlements: EntitlementsDto;
    subscription: {
        status: string;
        currentPeriodEnd: Date | null;
    };
}
