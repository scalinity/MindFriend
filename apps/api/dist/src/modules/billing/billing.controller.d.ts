import { BillingService } from './billing.service';
import { AppleTransactionDto, EntitlementsDto, TransactionResponseDto } from './dto/billing.dto';
export declare class BillingController {
    private readonly billingService;
    constructor(billingService: BillingService);
    validateAppleTransaction(userId: string, dto: AppleTransactionDto): Promise<TransactionResponseDto>;
    getEntitlements(userId: string): Promise<EntitlementsDto>;
}
