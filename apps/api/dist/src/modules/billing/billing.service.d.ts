import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { AppleTransactionDto, EntitlementsDto, TransactionResponseDto } from './dto/billing.dto';
export declare class BillingService {
    private readonly prisma;
    private readonly configService;
    private readonly logger;
    private readonly isMockBilling;
    private readonly dailyFreeQuota;
    private readonly premiumQuota;
    constructor(prisma: PrismaService, configService: ConfigService);
    validateAppleTransaction(userId: string, dto: AppleTransactionDto): Promise<TransactionResponseDto>;
    getEntitlements(userId: string): Promise<EntitlementsDto>;
    private mockDecodeTransaction;
    private decodeAndValidateTransaction;
    private getLocalDate;
}
