import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import {
  AppleTransactionDto,
  EntitlementsDto,
  TransactionResponseDto,
} from './dto/billing.dto';

// Mock transaction data structure for development
interface DecodedTransaction {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  purchaseDate: Date;
  expiresDate: Date | null;
  type: 'Auto-Renewable Subscription' | 'Non-Consumable' | 'Consumable';
}

@Injectable()
export class BillingService {
  private readonly logger = new Logger(BillingService.name);
  private readonly isMockBilling: boolean;
  private readonly dailyFreeQuota: number;
  private readonly premiumQuota: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {
    this.isMockBilling =
      this.configService.get('APPLE_BILLING_MOCK') === 'true';
    this.dailyFreeQuota = parseInt(
      this.configService.get('AI_DAILY_FREE_QUOTA', '20'),
      10,
    );
    this.premiumQuota = 9999;
  }

  async validateAppleTransaction(
    userId: string,
    dto: AppleTransactionDto,
  ): Promise<TransactionResponseDto> {
    let transaction: DecodedTransaction;

    if (this.isMockBilling) {
      // Mock validation for development
      transaction = this.mockDecodeTransaction(dto.signedTransactionJws);
    } else {
      // Real App Store Server API validation
      transaction = await this.decodeAndValidateTransaction(
        dto.signedTransactionJws,
      );
    }

    // Update subscription in database
    await this.prisma.subscription.upsert({
      where: {
        userId_productId: {
          userId,
          productId: transaction.productId,
        },
      },
      create: {
        userId,
        productId: transaction.productId,
        status: 'active',
        currentPeriodEnd: transaction.expiresDate,
        originalTransactionId: transaction.originalTransactionId,
        latestTransactionId: transaction.transactionId,
      },
      update: {
        status: 'active',
        currentPeriodEnd: transaction.expiresDate,
        latestTransactionId: transaction.transactionId,
        updatedAt: new Date(),
      },
    });

    // Get updated entitlements
    const entitlements = await this.getEntitlements(userId);

    return {
      entitlements,
      subscription: {
        status: 'active',
        currentPeriodEnd: transaction.expiresDate,
      },
    };
  }

  async getEntitlements(userId: string): Promise<EntitlementsDto> {
    // Check for active subscription
    const subscription = await this.prisma.subscription.findFirst({
      where: {
        userId,
        status: { in: ['active', 'grace'] },
      },
    });

    const isPremium = !!subscription;

    // Get today's AI usage
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });
    const timezone = user?.timezone || 'UTC';
    const localDate = this.getLocalDate(timezone);

    const usage = await this.prisma.dailyAiUsage.findUnique({
      where: {
        userId_localDate: { userId, localDate },
      },
    });

    const aiMessagesUsedToday = usage?.messageCount || 0;

    return {
      tier: isPremium ? 'premium' : 'free',
      aiMessagesPerDayLimit: isPremium
        ? this.premiumQuota
        : this.dailyFreeQuota,
      aiMessagesUsedToday,
    };
  }

  private mockDecodeTransaction(jws: string): DecodedTransaction {
    // Mock decoder for development
    // In production, use @apple/app-store-server-library
    this.logger.debug('Using mock transaction decoder');

    // Parse the mock JWS (in dev, we accept a simple JSON string)
    try {
      const mockData = JSON.parse(jws);
      return {
        originalTransactionId:
          mockData.originalTransactionId || `mock_${Date.now()}`,
        transactionId: mockData.transactionId || `mock_tx_${Date.now()}`,
        productId: mockData.productId || 'mindfriend_premium_monthly',
        purchaseDate: new Date(mockData.purchaseDate || Date.now()),
        expiresDate: mockData.expiresDate
          ? new Date(mockData.expiresDate)
          : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
        type: 'Auto-Renewable Subscription',
      };
    } catch {
      // If parsing fails, return a default mock transaction
      return {
        originalTransactionId: `mock_${Date.now()}`,
        transactionId: `mock_tx_${Date.now()}`,
        productId: 'mindfriend_premium_monthly',
        purchaseDate: new Date(),
        expiresDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        type: 'Auto-Renewable Subscription',
      };
    }
  }

  private async decodeAndValidateTransaction(
    jws: string,
  ): Promise<DecodedTransaction> {
    // TODO: Implement real App Store Server API validation
    // Using @apple/app-store-server-library
    // For now, throw an error in production mode without proper config
    throw new BadRequestException(
      'App Store Server API validation not yet implemented',
    );
  }

  private getLocalDate(timezone: string): string {
    const now = new Date();
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    return formatter.format(now);
  }
}
