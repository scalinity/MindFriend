"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var BillingService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.BillingService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const prisma_service_1 = require("../prisma/prisma.service");
let BillingService = BillingService_1 = class BillingService {
    prisma;
    configService;
    logger = new common_1.Logger(BillingService_1.name);
    isMockBilling;
    dailyFreeQuota;
    premiumQuota;
    constructor(prisma, configService) {
        this.prisma = prisma;
        this.configService = configService;
        this.isMockBilling =
            this.configService.get('APPLE_BILLING_MOCK') === 'true';
        this.dailyFreeQuota = parseInt(this.configService.get('AI_DAILY_FREE_QUOTA', '20'), 10);
        this.premiumQuota = 9999;
    }
    async validateAppleTransaction(userId, dto) {
        let transaction;
        if (this.isMockBilling) {
            transaction = this.mockDecodeTransaction(dto.signedTransactionJws);
        }
        else {
            transaction = await this.decodeAndValidateTransaction(dto.signedTransactionJws);
        }
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
        const entitlements = await this.getEntitlements(userId);
        return {
            entitlements,
            subscription: {
                status: 'active',
                currentPeriodEnd: transaction.expiresDate,
            },
        };
    }
    async getEntitlements(userId) {
        const subscription = await this.prisma.subscription.findFirst({
            where: {
                userId,
                status: { in: ['active', 'grace'] },
            },
        });
        const isPremium = !!subscription;
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
    mockDecodeTransaction(jws) {
        this.logger.debug('Using mock transaction decoder');
        try {
            const mockData = JSON.parse(jws);
            return {
                originalTransactionId: mockData.originalTransactionId || `mock_${Date.now()}`,
                transactionId: mockData.transactionId || `mock_tx_${Date.now()}`,
                productId: mockData.productId || 'mindfriend_premium_monthly',
                purchaseDate: new Date(mockData.purchaseDate || Date.now()),
                expiresDate: mockData.expiresDate
                    ? new Date(mockData.expiresDate)
                    : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
                type: 'Auto-Renewable Subscription',
            };
        }
        catch {
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
    async decodeAndValidateTransaction(jws) {
        throw new common_1.BadRequestException('App Store Server API validation not yet implemented');
    }
    getLocalDate(timezone) {
        const now = new Date();
        const formatter = new Intl.DateTimeFormat('en-CA', {
            timeZone: timezone,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        });
        return formatter.format(now);
    }
};
exports.BillingService = BillingService;
exports.BillingService = BillingService = BillingService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], BillingService);
//# sourceMappingURL=billing.service.js.map