import { Controller, Get, Post, Body } from '@nestjs/common';
import { BillingService } from './billing.service';
import {
  AppleTransactionDto,
  EntitlementsDto,
  TransactionResponseDto,
} from './dto/billing.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1/billing')
export class BillingController {
  constructor(private readonly billingService: BillingService) {}

  @Post('apple/transaction')
  async validateAppleTransaction(
    @CurrentUser('sub') userId: string,
    @Body() dto: AppleTransactionDto,
  ): Promise<TransactionResponseDto> {
    return this.billingService.validateAppleTransaction(userId, dto);
  }

  @Get('entitlements')
  async getEntitlements(
    @CurrentUser('sub') userId: string,
  ): Promise<EntitlementsDto> {
    return this.billingService.getEntitlements(userId);
  }
}
