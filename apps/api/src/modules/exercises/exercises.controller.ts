import { Controller, Get, Post, Body, Param, Query } from '@nestjs/common';
import { ExercisesService } from './exercises.service';
import {
  CompleteSessionDto,
  ExerciseResponseDto,
  StartSessionResponseDto,
  CompleteSessionResponseDto,
} from './dto/exercises.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1/exercises')
export class ExercisesController {
  constructor(private readonly exercisesService: ExercisesService) {}

  @Get()
  async getExercises(
    @Query('type') type?: string,
  ): Promise<ExerciseResponseDto[]> {
    return this.exercisesService.getExercises(type);
  }

  @Post(':id/start')
  async startSession(
    @CurrentUser('sub') userId: string,
    @Param('id') exerciseId: string,
  ): Promise<StartSessionResponseDto> {
    return this.exercisesService.startSession(userId, exerciseId);
  }

  @Post('sessions/:sessionId/complete')
  async completeSession(
    @CurrentUser('sub') userId: string,
    @Param('sessionId') sessionId: string,
    @Body() dto: CompleteSessionDto,
  ): Promise<CompleteSessionResponseDto> {
    return this.exercisesService.completeSession(userId, sessionId, dto);
  }
}
