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
Object.defineProperty(exports, "__esModule", { value: true });
exports.QuestsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let QuestsService = class QuestsService {
    prisma;
    constructor(prisma) {
        this.prisma = prisma;
    }
    async getTodayQuest(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { timezone: true },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const localDate = this.getLocalDate(user.timezone);
        let quest = await this.prisma.questInstance.findUnique({
            where: {
                userId_localDate: { userId, localDate },
            },
            include: { template: true },
        });
        if (!quest) {
            quest = await this.assignQuest(userId, localDate);
        }
        return this.formatQuestResponse(quest);
    }
    async completeQuest(userId, questId, dto) {
        const quest = await this.prisma.questInstance.findFirst({
            where: { id: questId, userId },
            include: { template: true },
        });
        if (!quest) {
            throw new common_1.NotFoundException('Quest not found');
        }
        if (quest.status !== 'assigned') {
            throw new common_1.BadRequestException('Quest already completed or skipped');
        }
        const completedAt = new Date();
        await this.prisma.$transaction(async (tx) => {
            await tx.questInstance.update({
                where: { id: questId },
                data: {
                    status: 'completed',
                    completedAt,
                },
            });
            await tx.questCompletion.create({
                data: {
                    questInstanceId: questId,
                    userId,
                    reflectionNote: dto.reflectionNote,
                    rating: dto.rating,
                },
            });
        });
        const streakInfo = await this.updateStreak(userId, quest.localDate);
        const badgesEarned = await this.evaluateBadges(userId, streakInfo);
        return {
            questId,
            status: 'completed',
            completedAt,
            streakDays: streakInfo.currentStreakDays,
            badgesEarned,
        };
    }
    async skipQuest(userId, questId) {
        const quest = await this.prisma.questInstance.findFirst({
            where: { id: questId, userId },
        });
        if (!quest) {
            throw new common_1.NotFoundException('Quest not found');
        }
        if (quest.status !== 'assigned') {
            throw new common_1.BadRequestException('Quest already completed or skipped');
        }
        await this.prisma.$transaction(async (tx) => {
            await tx.questInstance.update({
                where: { id: questId },
                data: { status: 'skipped' },
            });
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
    async assignQuest(userId, localDate) {
        const recentQuests = await this.prisma.questInstance.findMany({
            where: { userId },
            orderBy: { assignedAt: 'desc' },
            take: 2,
            select: { templateId: true },
        });
        const recentTemplateIds = recentQuests.map((q) => q.templateId);
        const recentMood = await this.prisma.moodEntry.findFirst({
            where: { userId },
            orderBy: { createdAt: 'desc' },
        });
        let templates = await this.prisma.questTemplate.findMany({
            where: {
                active: true,
                id: { notIn: recentTemplateIds },
            },
        });
        if (templates.length === 0) {
            templates = await this.prisma.questTemplate.findMany({
                where: { active: true },
            });
        }
        if (recentMood && recentMood.moodScore <= 2) {
            const calmingTemplates = templates.filter((t) => t.tags.includes('calming') || t.tags.includes('stress-relief'));
            if (calmingTemplates.length > 0) {
                templates = calmingTemplates;
            }
        }
        const selectedTemplate = templates[Math.floor(Math.random() * templates.length)];
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
    async updateStreak(userId, completedLocalDate) {
        const stats = await this.prisma.userStats.findUnique({
            where: { userId },
        });
        if (!stats) {
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
        const lastDate = stats.lastStreakLocalDate;
        const yesterday = this.getYesterday(completedLocalDate);
        let newStreak = stats.currentStreakDays;
        if (lastDate === yesterday) {
            newStreak = stats.currentStreakDays + 1;
        }
        else if (lastDate === completedLocalDate) {
            newStreak = stats.currentStreakDays;
        }
        else {
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
    async evaluateBadges(userId, streakInfo) {
        const earnedBadges = [];
        const existingBadges = await this.prisma.userBadge.findMany({
            where: { userId },
            select: { badgeId: true },
        });
        const existingBadgeIds = new Set(existingBadges.map((b) => b.badgeId));
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
    formatQuestResponse(quest) {
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
    getYesterday(dateStr) {
        const [year, month, day] = dateStr.split('-').map(Number);
        const date = new Date(year, month - 1, day);
        date.setDate(date.getDate() - 1);
        return date.toISOString().split('T')[0];
    }
};
exports.QuestsService = QuestsService;
exports.QuestsService = QuestsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], QuestsService);
//# sourceMappingURL=quests.service.js.map