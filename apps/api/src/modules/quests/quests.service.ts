import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  CompleteQuestDto,
  QuestResponseDto,
  QuestCompletionResponseDto,
} from './dto/quests.dto';

@Injectable()
export class QuestsService {
  constructor(private readonly prisma: PrismaService) {}

  async getTodayQuest(userId: string): Promise<QuestResponseDto> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { timezone: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const localDate = this.getLocalDate(user.timezone);

    // Check if quest already exists for today
    let quest = await this.prisma.questInstance.findUnique({
      where: {
        userId_localDate: { userId, localDate },
      },
      include: { template: true },
    });

    if (!quest) {
      // Assign a new quest
      quest = await this.assignQuest(userId, localDate);
    }

    return this.formatQuestResponse(quest);
  }

  async completeQuest(
    userId: string,
    questId: string,
    dto: CompleteQuestDto,
  ): Promise<QuestCompletionResponseDto> {
    const quest = await this.prisma.questInstance.findFirst({
      where: { id: questId, userId },
      include: { template: true },
    });

    if (!quest) {
      throw new NotFoundException('Quest not found');
    }

    if (quest.status !== 'assigned') {
      throw new BadRequestException('Quest already completed or skipped');
    }

    // Complete the quest
    const completedAt = new Date();
    await this.prisma.$transaction(async (tx) => {
      // Update quest status
      await tx.questInstance.update({
        where: { id: questId },
        data: {
          status: 'completed',
          completedAt,
        },
      });

      // Create completion record
      await tx.questCompletion.create({
        data: {
          questInstanceId: questId,
          userId,
          reflectionNote: dto.reflectionNote,
          rating: dto.rating,
        },
      });
    });

    // Update streak
    const streakInfo = await this.updateStreak(userId, quest.localDate);

    // Check for earned badges
    const badgesEarned = await this.evaluateBadges(userId, streakInfo);

    return {
      questId,
      status: 'completed',
      completedAt,
      streakDays: streakInfo.currentStreakDays,
      badgesEarned,
    };
  }

  async skipQuest(
    userId: string,
    questId: string,
  ): Promise<{ status: string }> {
    const quest = await this.prisma.questInstance.findFirst({
      where: { id: questId, userId },
    });

    if (!quest) {
      throw new NotFoundException('Quest not found');
    }

    if (quest.status !== 'assigned') {
      throw new BadRequestException('Quest already completed or skipped');
    }

    // Skip breaks streak in MVP
    await this.prisma.$transaction(async (tx) => {
      await tx.questInstance.update({
        where: { id: questId },
        data: { status: 'skipped' },
      });

      // Reset streak
      await tx.userStats.update({
        where: { userId },
        data: {
          currentStreakDays: 0,
          lastStreakLocalDate: quest.localDate,
        },
      });
    });

    return { status: 'skipped' };
  }

  private async assignQuest(userId: string, localDate: string) {
    // Get user's recent quests to avoid repeats
    const recentQuests = await this.prisma.questInstance.findMany({
      where: { userId },
      orderBy: { assignedAt: 'desc' },
      take: 2,
      select: { templateId: true },
    });

    const recentTemplateIds = recentQuests.map((q) => q.templateId);

    // Get user's mood to personalize quest selection
    const recentMood = await this.prisma.moodEntry.findFirst({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });

    // Get available quest templates
    let templates = await this.prisma.questTemplate.findMany({
      where: {
        active: true,
        id: { notIn: recentTemplateIds },
      },
    });

    // If all templates were used recently, get any active template
    if (templates.length === 0) {
      templates = await this.prisma.questTemplate.findMany({
        where: { active: true },
      });
    }

    // Prefer calming quests if mood is low
    if (recentMood && recentMood.moodScore <= 2) {
      const calmingTemplates = templates.filter(
        (t) => t.tags.includes('calming') || t.tags.includes('stress-relief'),
      );
      if (calmingTemplates.length > 0) {
        templates = calmingTemplates;
      }
    }

    // Random selection
    const selectedTemplate =
      templates[Math.floor(Math.random() * templates.length)];

    const quest = await this.prisma.questInstance.create({
      data: {
        userId,
        templateId: selectedTemplate.id,
        localDate,
      },
      include: { template: true },
    });

    return quest;
  }

  private async updateStreak(
    userId: string,
    completedLocalDate: string,
  ): Promise<{ currentStreakDays: number; longestStreakDays: number }> {
    const stats = await this.prisma.userStats.findUnique({
      where: { userId },
    });

    if (!stats) {
      // Create stats if not exists
      const newStats = await this.prisma.userStats.create({
        data: {
          userId,
          currentStreakDays: 1,
          longestStreakDays: 1,
          lastStreakLocalDate: completedLocalDate,
          totalQuestsCompleted: 1,
        },
      });
      return {
        currentStreakDays: newStats.currentStreakDays,
        longestStreakDays: newStats.longestStreakDays,
      };
    }

    // Calculate if this extends the streak
    const lastDate = stats.lastStreakLocalDate;
    const yesterday = this.getYesterday(completedLocalDate);

    let newStreak = stats.currentStreakDays;
    if (lastDate === yesterday) {
      // Consecutive day - extend streak
      newStreak = stats.currentStreakDays + 1;
    } else if (lastDate === completedLocalDate) {
      // Same day - keep streak
      newStreak = stats.currentStreakDays;
    } else {
      // Streak broken - start fresh
      newStreak = 1;
    }

    const newLongest = Math.max(newStreak, stats.longestStreakDays);

    await this.prisma.userStats.update({
      where: { userId },
      data: {
        currentStreakDays: newStreak,
        longestStreakDays: newLongest,
        lastStreakLocalDate: completedLocalDate,
        totalQuestsCompleted: { increment: 1 },
      },
    });

    return { currentStreakDays: newStreak, longestStreakDays: newLongest };
  }

  private async evaluateBadges(
    userId: string,
    streakInfo: { currentStreakDays: number },
  ): Promise<Array<{ code: string; title: string }>> {
    const earnedBadges: Array<{ code: string; title: string }> = [];

    // Get user's existing badges
    const existingBadges = await this.prisma.userBadge.findMany({
      where: { userId },
      select: { badgeId: true },
    });
    const existingBadgeIds = new Set(existingBadges.map((b) => b.badgeId));

    // Check streak badges
    const streakBadges = [
      { threshold: 3, code: 'streak_3' },
      { threshold: 7, code: 'streak_7' },
      { threshold: 14, code: 'streak_14' },
      { threshold: 30, code: 'streak_30' },
    ];

    for (const { threshold, code } of streakBadges) {
      if (streakInfo.currentStreakDays >= threshold) {
        const badge = await this.prisma.badge.findUnique({
          where: { code },
        });
        if (badge && !existingBadgeIds.has(badge.id)) {
          await this.prisma.userBadge.create({
            data: { userId, badgeId: badge.id },
          });
          earnedBadges.push({ code: badge.code, title: badge.title });
        }
      }
    }

    // Check first quest badge
    const stats = await this.prisma.userStats.findUnique({
      where: { userId },
    });
    if (stats?.totalQuestsCompleted === 1) {
      const firstQuestBadge = await this.prisma.badge.findUnique({
        where: { code: 'first_quest' },
      });
      if (firstQuestBadge && !existingBadgeIds.has(firstQuestBadge.id)) {
        await this.prisma.userBadge.create({
          data: { userId, badgeId: firstQuestBadge.id },
        });
        earnedBadges.push({
          code: firstQuestBadge.code,
          title: firstQuestBadge.title,
        });
      }
    }

    return earnedBadges;
  }

  private formatQuestResponse(quest: any): QuestResponseDto {
    return {
      id: quest.id,
      localDate: quest.localDate,
      status: quest.status,
      assignedAt: quest.assignedAt,
      completedAt: quest.completedAt,
      template: {
        id: quest.template.id,
        type: quest.template.type,
        title: quest.template.title,
        description: quest.template.description,
        estimatedMinutes: quest.template.estimatedMinutes,
        difficulty: quest.template.difficulty,
        tags: quest.template.tags,
        instructions: quest.template.instructionsJson,
      },
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

  private getYesterday(dateStr: string): string {
    const [year, month, day] = dateStr.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    date.setDate(date.getDate() - 1);
    return date.toISOString().split('T')[0];
  }
}
