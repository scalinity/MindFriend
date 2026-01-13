import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateMoodDto,
  MoodEntryResponseDto,
  MoodHistoryResponseDto,
} from './dto/moods.dto';

@Injectable()
export class MoodsService {
  constructor(private readonly prisma: PrismaService) {}

  async createOrUpdateMood(
    userId: string,
    dto: CreateMoodDto,
  ): Promise<MoodEntryResponseDto> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { timezone: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const localDate = this.getLocalDate(user.timezone);
    const source =
      (dto.source as 'manual' | 'quest' | 'circle_checkin') || 'manual';

    // Upsert mood entry for today
    const mood = await this.prisma.moodEntry.upsert({
      where: {
        userId_localDate_source: {
          userId,
          localDate,
          source,
        },
      },
      create: {
        userId,
        localDate,
        moodScore: dto.moodScore,
        anxietyScore: dto.anxietyScore,
        energyScore: dto.energyScore,
        note: dto.note,
        source,
      },
      update: {
        moodScore: dto.moodScore,
        anxietyScore: dto.anxietyScore,
        energyScore: dto.energyScore,
        note: dto.note,
      },
    });

    // Check for mood tracker badge
    await this.checkMoodBadge(userId);

    return this.formatMoodResponse(mood);
  }

  async getMoodHistory(
    userId: string,
    from: string,
    to: string,
  ): Promise<MoodHistoryResponseDto> {
    const entries = await this.prisma.moodEntry.findMany({
      where: {
        userId,
        localDate: {
          gte: from,
          lte: to,
        },
      },
      orderBy: { localDate: 'desc' },
    });

    // Calculate summary statistics
    const moodScores = entries.map((e) => e.moodScore);
    const anxietyScores = entries
      .filter((e) => e.anxietyScore !== null)
      .map((e) => e.anxietyScore as number);
    const energyScores = entries
      .filter((e) => e.energyScore !== null)
      .map((e) => e.energyScore as number);

    const avgMoodScore =
      moodScores.length > 0
        ? moodScores.reduce((a, b) => a + b, 0) / moodScores.length
        : 0;
    const avgAnxietyScore =
      anxietyScores.length > 0
        ? anxietyScores.reduce((a, b) => a + b, 0) / anxietyScores.length
        : null;
    const avgEnergyScore =
      energyScores.length > 0
        ? energyScores.reduce((a, b) => a + b, 0) / energyScores.length
        : null;

    return {
      entries: entries.map((e) => this.formatMoodResponse(e)),
      summary: {
        avgMoodScore: Math.round(avgMoodScore * 10) / 10,
        avgAnxietyScore: avgAnxietyScore
          ? Math.round(avgAnxietyScore * 10) / 10
          : null,
        avgEnergyScore: avgEnergyScore
          ? Math.round(avgEnergyScore * 10) / 10
          : null,
        totalEntries: entries.length,
      },
    };
  }

  private async checkMoodBadge(userId: string): Promise<void> {
    // Count total mood entries
    const count = await this.prisma.moodEntry.count({
      where: { userId },
    });

    if (count >= 7) {
      const badge = await this.prisma.badge.findUnique({
        where: { code: 'mood_tracker' },
      });

      if (badge) {
        // Try to create badge (will fail silently if already exists due to PK constraint)
        await this.prisma.userBadge
          .create({
            data: { userId, badgeId: badge.id },
          })
          .catch(() => {
            // Badge already exists, ignore
          });
      }
    }
  }

  private formatMoodResponse(mood: any): MoodEntryResponseDto {
    return {
      id: mood.id,
      localDate: mood.localDate,
      moodScore: mood.moodScore,
      anxietyScore: mood.anxietyScore,
      energyScore: mood.energyScore,
      note: mood.note,
      source: mood.source,
      createdAt: mood.createdAt,
    };
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
