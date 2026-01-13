import { Controller, Get, Post, Body, Param, Query } from '@nestjs/common';
import { CirclesService } from './circles.service';
import {
  CreateCircleDto,
  JoinCircleDto,
  CircleCheckInDto,
  CircleResponseDto,
  CircleListItemDto,
  CircleDetailDto,
  CirclePostDto,
  JoinCircleResponseDto,
} from './dto/circles.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1/circles')
export class CirclesController {
  constructor(private readonly circlesService: CirclesService) {}

  @Post()
  async createCircle(
    @CurrentUser('sub') userId: string,
    @Body() dto: CreateCircleDto,
  ): Promise<CircleResponseDto> {
    return this.circlesService.createCircle(userId, dto);
  }

  @Post('join')
  async joinCircle(
    @CurrentUser('sub') userId: string,
    @Body() dto: JoinCircleDto,
  ): Promise<JoinCircleResponseDto> {
    return this.circlesService.joinCircle(userId, dto);
  }

  @Get()
  async getCircles(
    @CurrentUser('sub') userId: string,
  ): Promise<CircleListItemDto[]> {
    return this.circlesService.getCircles(userId);
  }

  @Get(':id')
  async getCircleDetail(
    @CurrentUser('sub') userId: string,
    @Param('id') circleId: string,
  ): Promise<CircleDetailDto> {
    return this.circlesService.getCircleDetail(userId, circleId);
  }

  @Get(':id/feed')
  async getCircleFeed(
    @CurrentUser('sub') userId: string,
    @Param('id') circleId: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ): Promise<CirclePostDto[]> {
    return this.circlesService.getCircleFeed(userId, circleId, from, to);
  }

  @Post(':id/checkin')
  async postCheckIn(
    @CurrentUser('sub') userId: string,
    @Param('id') circleId: string,
    @Body() dto: CircleCheckInDto,
  ): Promise<CirclePostDto> {
    return this.circlesService.postCheckIn(userId, circleId, dto);
  }
}
