import { Controller, Get, Post, Body, Query } from '@nestjs/common';
import { MoodsService } from './moods.service';
import {
  CreateMoodDto,
  MoodEntryResponseDto,
  MoodHistoryResponseDto,
} from './dto/moods.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1/moods')
export class MoodsController {
  constructor(private readonly moodsService: MoodsService) {}

  @Post()
  async createMood(
    @CurrentUser('sub') userId: string,
    @Body() dto: CreateMoodDto,
  ): Promise<MoodEntryResponseDto> {
    return this.moodsService.createOrUpdateMood(userId, dto);
  }

  @Get()
  async getMoodHistory(
    @CurrentUser('sub') userId: string,
    @Query('from') from: string,
    @Query('to') to: string,
  ): Promise<MoodHistoryResponseDto> {
    return this.moodsService.getMoodHistory(userId, from, to);
  }
}
