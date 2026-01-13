import { Controller, Get, Post, Body, Param } from '@nestjs/common';
import { QuestsService } from './quests.service';
import {
  CompleteQuestDto,
  QuestResponseDto,
  QuestCompletionResponseDto,
} from './dto/quests.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1/quests')
export class QuestsController {
  constructor(private readonly questsService: QuestsService) {}

  @Get('today')
  async getTodayQuest(
    @CurrentUser('sub') userId: string,
  ): Promise<QuestResponseDto> {
    return this.questsService.getTodayQuest(userId);
  }

  @Post(':id/complete')
  async completeQuest(
    @CurrentUser('sub') userId: string,
    @Param('id') questId: string,
    @Body() dto: CompleteQuestDto,
  ): Promise<QuestCompletionResponseDto> {
    return this.questsService.completeQuest(userId, questId, dto);
  }

  @Post(':id/skip')
  async skipQuest(
    @CurrentUser('sub') userId: string,
    @Param('id') questId: string,
  ): Promise<{ status: string }> {
    return this.questsService.skipQuest(userId, questId);
  }
}
