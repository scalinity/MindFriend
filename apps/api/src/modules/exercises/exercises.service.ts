import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  CompleteSessionDto,
  ExerciseResponseDto,
  StartSessionResponseDto,
  CompleteSessionResponseDto,
} from './dto/exercises.dto';

@Injectable()
export class ExercisesService {
  constructor(private readonly prisma: PrismaService) {}

  async getExercises(type?: string): Promise<ExerciseResponseDto[]> {
    const exercises = await this.prisma.exercise.findMany({
      where: {
        active: true,
        ...(type ? { type } : {}),
      },
      orderBy: { title: 'asc' },
    });

    return exercises.map((e) => ({
      id: e.id,
      type: e.type,
      title: e.title,
      description: e.description,
      durationSeconds: e.durationSeconds,
      contentKind: e.contentKind,
      contentText: e.contentText,
      audioUrl: e.audioUrl,
      tags: e.tags,
    }));
  }

  async startSession(
    userId: string,
    exerciseId: string,
  ): Promise<StartSessionResponseDto> {
    // Verify exercise exists
    const exercise = await this.prisma.exercise.findUnique({
      where: { id: exerciseId },
    });

    if (!exercise || !exercise.active) {
      throw new NotFoundException('Exercise not found');
    }

    const session = await this.prisma.exerciseSession.create({
      data: {
        userId,
        exerciseId,
        startedAt: new Date(),
        completed: false,
      },
    });

    return {
      sessionId: session.id,
      startedAt: session.startedAt,
    };
  }

  async completeSession(
    userId: string,
    sessionId: string,
    dto: CompleteSessionDto,
  ): Promise<CompleteSessionResponseDto> {
    // Find session and verify ownership
    const session = await this.prisma.exerciseSession.findFirst({
      where: { id: sessionId, userId },
    });

    if (!session) {
      throw new NotFoundException('Session not found');
    }

    if (session.completed) {
      throw new BadRequestException('Session already completed');
    }

    // Update session
    await this.prisma.exerciseSession.update({
      where: { id: sessionId },
      data: {
        completed: true,
        endedAt: new Date(),
        rating: dto.rating || null,
        note: dto.note || null,
      },
    });

    // Update user stats
    const stats = await this.prisma.userStats.upsert({
      where: { userId },
      create: {
        userId,
        totalExercisesCompleted: 1,
      },
      update: {
        totalExercisesCompleted: { increment: 1 },
        updatedAt: new Date(),
      },
    });

    return {
      ok: true,
      stats: {
        totalExercisesCompleted: stats.totalExercisesCompleted,
      },
    };
  }
}
