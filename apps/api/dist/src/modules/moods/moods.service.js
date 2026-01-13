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
exports.MoodsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let MoodsService = class MoodsService {
    prisma;
    constructor(prisma) {
        this.prisma = prisma;
    }
    async createOrUpdateMood(userId, dto) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { timezone: true },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const localDate = this.getLocalDate(user.timezone);
        const source = dto.source || 'manual';
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
        await this.checkMoodBadge(userId);
        return this.formatMoodResponse(mood);
    }
    async getMoodHistory(userId, from, to) {
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
        const moodScores = entries.map((e) => e.moodScore);
        const anxietyScores = entries
            .filter((e) => e.anxietyScore !== null)
            .map((e) => e.anxietyScore);
        const energyScores = entries
            .filter((e) => e.energyScore !== null)
            .map((e) => e.energyScore);
        const avgMoodScore = moodScores.length > 0
            ? moodScores.reduce((a, b) => a + b, 0) / moodScores.length
            : 0;
        const avgAnxietyScore = anxietyScores.length > 0
            ? anxietyScores.reduce((a, b) => a + b, 0) / anxietyScores.length
            : null;
        const avgEnergyScore = energyScores.length > 0
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
    async checkMoodBadge(userId) {
        const count = await this.prisma.moodEntry.count({
            where: { userId },
        });
        if (count >= 7) {
            const badge = await this.prisma.badge.findUnique({
                where: { code: 'mood_tracker' },
            });
            if (badge) {
                await this.prisma.userBadge
                    .create({
                    data: { userId, badgeId: badge.id },
                })
                    .catch(() => {
                });
            }
        }
    }
    formatMoodResponse(mood) {
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
};
exports.MoodsService = MoodsService;
exports.MoodsService = MoodsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], MoodsService);
//# sourceMappingURL=moods.service.js.map