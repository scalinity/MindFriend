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
exports.UsersService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const prisma_service_1 = require("../prisma/prisma.service");
let UsersService = class UsersService {
    prisma;
    configService;
    dailyFreeQuota;
    premiumQuota;
    constructor(prisma, configService) {
        this.prisma = prisma;
        this.configService = configService;
        this.dailyFreeQuota = parseInt(this.configService.get('AI_DAILY_FREE_QUOTA', '20'), 10);
        this.premiumQuota = 9999;
    }
    async getProfile(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            include: {
                settings: true,
                stats: true,
                userBadges: {
                    include: { badge: true },
                    orderBy: { earnedAt: 'desc' },
                },
                subscriptions: {
                    where: { status: { in: ['active', 'grace'] } },
                    take: 1,
                },
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const today = this.getLocalDate(user.timezone);
        const dailyUsage = await this.prisma.dailyAiUsage.findUnique({
            where: {
                userId_localDate: {
                    userId,
                    localDate: today,
                },
            },
        });
        const tier = user.subscriptions.length > 0 ? 'premium' : 'free';
        const dailyQuota = tier === 'premium' ? this.premiumQuota : this.dailyFreeQuota;
        return {
            id: user.id,
            handle: user.handle,
            displayName: user.displayName,
            email: user.email,
            timezone: user.timezone,
            createdAt: user.createdAt,
            settings: {
                dailyQuestTimeLocal: user.settings?.dailyQuestTimeLocal || '09:00:00',
                quietHoursStartLocal: user.settings?.quietHoursStartLocal || null,
                quietHoursEndLocal: user.settings?.quietHoursEndLocal || null,
                remindersEnabled: user.settings?.remindersEnabled ?? true,
                nudgeAfterDaysInactive: user.settings?.nudgeAfterDaysInactive ?? 2,
                shareMoodInCircles: user.settings?.shareMoodInCircles ?? true,
                aiTone: user.settings?.aiTone || 'friendly',
                privacyMode: user.settings?.privacyMode || 'standard',
            },
            stats: {
                currentStreakDays: user.stats?.currentStreakDays ?? 0,
                longestStreakDays: user.stats?.longestStreakDays ?? 0,
                totalQuestsCompleted: user.stats?.totalQuestsCompleted ?? 0,
                totalExercisesCompleted: user.stats?.totalExercisesCompleted ?? 0,
            },
            entitlements: {
                tier,
                dailyAiQuota: dailyQuota,
                dailyAiUsed: dailyUsage?.messageCount ?? 0,
            },
            badges: user.userBadges.map((ub) => ({
                code: ub.badge.code,
                title: ub.badge.title,
                earnedAt: ub.earnedAt,
            })),
        };
    }
    async updateProfile(userId, dto) {
        const user = await this.prisma.user.update({
            where: { id: userId },
            data: {
                ...(dto.displayName && { displayName: dto.displayName }),
                ...(dto.timezone && { timezone: dto.timezone }),
            },
            select: {
                id: true,
                handle: true,
                displayName: true,
                timezone: true,
            },
        });
        return user;
    }
    async updateSettings(userId, dto) {
        if (dto.quietHoursStartLocal && dto.quietHoursEndLocal) {
            const spanHours = this.calculateQuietHoursSpan(dto.quietHoursStartLocal, dto.quietHoursEndLocal);
            if (spanHours >= 16) {
                throw new common_1.BadRequestException('Quiet hours span must be less than 16 hours');
            }
        }
        await this.prisma.userSettings.upsert({
            where: { userId },
            create: {
                userId,
                ...dto,
            },
            update: dto,
        });
        return { message: 'Settings updated successfully' };
    }
    async registerDevice(userId, dto) {
        const existingDevice = await this.prisma.device.findFirst({
            where: {
                userId,
                apnsToken: dto.apnsToken,
            },
        });
        if (existingDevice) {
            const device = await this.prisma.device.update({
                where: { id: existingDevice.id },
                data: {
                    deviceModel: dto.deviceModel,
                    osVersion: dto.osVersion,
                    locale: dto.locale || 'en-US',
                    timezone: dto.timezone || 'UTC',
                    lastSeenAt: new Date(),
                },
            });
            return { deviceId: device.id };
        }
        const tokenInUse = await this.prisma.device.findUnique({
            where: { apnsToken: dto.apnsToken },
        });
        if (tokenInUse) {
            const device = await this.prisma.device.update({
                where: { id: tokenInUse.id },
                data: {
                    userId,
                    deviceModel: dto.deviceModel,
                    osVersion: dto.osVersion,
                    locale: dto.locale || 'en-US',
                    timezone: dto.timezone || 'UTC',
                    lastSeenAt: new Date(),
                },
            });
            return { deviceId: device.id };
        }
        const device = await this.prisma.device.create({
            data: {
                userId,
                apnsToken: dto.apnsToken,
                deviceModel: dto.deviceModel,
                osVersion: dto.osVersion,
                locale: dto.locale || 'en-US',
                timezone: dto.timezone || 'UTC',
            },
        });
        return { deviceId: device.id };
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
    calculateQuietHoursSpan(start, end) {
        const [startHour, startMin] = start.split(':').map(Number);
        const [endHour, endMin] = end.split(':').map(Number);
        const startMinutes = startHour * 60 + startMin;
        let endMinutes = endHour * 60 + endMin;
        if (endMinutes <= startMinutes) {
            endMinutes += 24 * 60;
        }
        return (endMinutes - startMinutes) / 60;
    }
    async deleteAccount(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const anonymizedHandle = `deleted-${Date.now()}`;
        await this.prisma.$transaction(async (tx) => {
            await tx.refreshToken.updateMany({
                where: { userId },
                data: { revokedAt: new Date() },
            });
            await tx.circleMember.deleteMany({
                where: { userId },
            });
            await tx.device.deleteMany({
                where: { userId },
            });
            await tx.user.update({
                where: { id: userId },
                data: {
                    handle: anonymizedHandle,
                    displayName: 'Deleted User',
                    email: null,
                    deletedAt: new Date(),
                },
            });
            await tx.userSettings.deleteMany({
                where: { userId },
            });
        });
        return { message: 'Account deleted successfully' };
    }
    async exportData(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            include: {
                settings: true,
                stats: true,
                userBadges: {
                    include: { badge: true },
                },
                moodEntries: {
                    orderBy: { createdAt: 'desc' },
                    take: 365,
                },
                questInstances: {
                    include: {
                        template: true,
                        completion: true,
                    },
                    orderBy: { assignedAt: 'desc' },
                    take: 365,
                },
                conversations: {
                    include: {
                        messages: {
                            orderBy: { createdAt: 'asc' },
                        },
                    },
                    orderBy: { updatedAt: 'desc' },
                },
                exerciseSessions: {
                    include: {
                        exercise: true,
                    },
                    orderBy: { startedAt: 'desc' },
                    take: 100,
                },
                circleMemberships: {
                    include: {
                        circle: {
                            select: {
                                id: true,
                                name: true,
                                description: true,
                            },
                        },
                    },
                },
                circlePosts: {
                    orderBy: { createdAt: 'desc' },
                    take: 365,
                },
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const exportData = {
            exportedAt: new Date().toISOString(),
            user: {
                id: user.id,
                handle: user.handle,
                displayName: user.displayName,
                email: user.email,
                timezone: user.timezone,
                createdAt: user.createdAt,
            },
            settings: user.settings,
            stats: user.stats,
            badges: user.userBadges.map((ub) => ({
                code: ub.badge.code,
                title: ub.badge.title,
                description: ub.badge.description,
                earnedAt: ub.earnedAt,
            })),
            moods: user.moodEntries.map((m) => ({
                localDate: m.localDate,
                moodScore: m.moodScore,
                anxietyScore: m.anxietyScore,
                energyScore: m.energyScore,
                note: m.note,
                source: m.source,
                createdAt: m.createdAt,
            })),
            quests: user.questInstances.map((q) => ({
                localDate: q.localDate,
                status: q.status,
                template: {
                    type: q.template.type,
                    title: q.template.title,
                },
                completion: q.completion
                    ? {
                        reflectionNote: q.completion.reflectionNote,
                        rating: q.completion.rating,
                        createdAt: q.completion.createdAt,
                    }
                    : null,
                completedAt: q.completedAt,
                assignedAt: q.assignedAt,
            })),
            conversations: user.conversations.map((c) => ({
                id: c.id,
                title: c.title,
                status: c.status,
                createdAt: c.createdAt,
                messages: c.messages.map((m) => ({
                    role: m.role,
                    content: m.content,
                    createdAt: m.createdAt,
                })),
            })),
            exerciseSessions: user.exerciseSessions.map((s) => ({
                exercise: {
                    type: s.exercise.type,
                    title: s.exercise.title,
                },
                completed: s.completed,
                rating: s.rating,
                note: s.note,
                startedAt: s.startedAt,
                endedAt: s.endedAt,
            })),
            circles: user.circleMemberships.map((cm) => ({
                id: cm.circle.id,
                name: cm.circle.name,
                description: cm.circle.description,
                role: cm.role,
                joinedAt: cm.joinedAt,
            })),
            circlePosts: user.circlePosts.map((p) => ({
                kind: p.kind,
                moodEmoji: p.moodEmoji,
                bodyText: p.bodyText,
                localDate: p.localDate,
                createdAt: p.createdAt,
            })),
        };
        return exportData;
    }
};
exports.UsersService = UsersService;
exports.UsersService = UsersService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], UsersService);
//# sourceMappingURL=users.service.js.map