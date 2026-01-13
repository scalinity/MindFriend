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
exports.CirclesService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
const crypto_1 = require("crypto");
let CirclesService = class CirclesService {
    prisma;
    constructor(prisma) {
        this.prisma = prisma;
    }
    generateInviteCode() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        const bytes = (0, crypto_1.randomBytes)(12);
        let code = '';
        for (let i = 0; i < 12; i++) {
            code += chars[bytes[i] % chars.length];
        }
        return code;
    }
    async createCircle(userId, dto) {
        let inviteCode;
        let isUnique = false;
        while (!isUnique) {
            inviteCode = this.generateInviteCode();
            const existing = await this.prisma.circle.findUnique({
                where: { inviteCode },
            });
            if (!existing)
                isUnique = true;
        }
        const circle = await this.prisma.circle.create({
            data: {
                ownerUserId: userId,
                name: dto.name,
                description: dto.description || null,
                maxMembers: dto.maxMembers || 8,
                inviteCode: inviteCode,
                isPrivate: true,
                members: {
                    create: {
                        userId,
                        role: 'owner',
                        status: 'active',
                    },
                },
            },
            include: {
                _count: {
                    select: { members: true },
                },
            },
        });
        await this.checkCircleCreatorBadge(userId);
        return {
            id: circle.id,
            name: circle.name,
            description: circle.description,
            isPrivate: circle.isPrivate,
            inviteCode: circle.inviteCode,
            maxMembers: circle.maxMembers,
            memberCount: circle._count.members,
            role: 'owner',
            createdAt: circle.createdAt,
        };
    }
    async joinCircle(userId, dto) {
        const circle = await this.prisma.circle.findUnique({
            where: { inviteCode: dto.inviteCode },
            include: {
                _count: {
                    select: { members: true },
                },
                members: {
                    where: { userId },
                },
            },
        });
        if (!circle) {
            throw new common_1.NotFoundException({
                code: 'INVITE_CODE_INVALID',
                message: 'Invalid invite code',
            });
        }
        if (circle.members.length > 0) {
            throw new common_1.ConflictException({
                code: 'ALREADY_MEMBER',
                message: 'You are already a member of this circle',
            });
        }
        if (circle._count.members >= circle.maxMembers) {
            throw new common_1.ConflictException({
                code: 'CIRCLE_FULL',
                message: 'This circle has reached its maximum member limit',
            });
        }
        await this.prisma.circleMember.create({
            data: {
                circleId: circle.id,
                userId,
                role: 'member',
                status: 'active',
            },
        });
        return {
            circleId: circle.id,
            role: 'member',
        };
    }
    async getCircles(userId) {
        const memberships = await this.prisma.circleMember.findMany({
            where: { userId, status: 'active' },
            include: {
                circle: {
                    include: {
                        _count: {
                            select: { members: true },
                        },
                    },
                },
            },
            orderBy: {
                joinedAt: 'desc',
            },
        });
        return memberships.map((m) => ({
            id: m.circle.id,
            name: m.circle.name,
            memberCount: m.circle._count.members,
            role: m.role,
        }));
    }
    async getCircleDetail(userId, circleId) {
        const membership = await this.prisma.circleMember.findUnique({
            where: {
                circleId_userId: { circleId, userId },
            },
        });
        if (!membership || membership.status !== 'active') {
            throw new common_1.ForbiddenException({
                code: 'NOT_A_MEMBER',
                message: 'You are not a member of this circle',
            });
        }
        const circle = await this.prisma.circle.findUnique({
            where: { id: circleId },
            include: {
                members: {
                    where: { status: 'active' },
                    include: {
                        user: {
                            select: {
                                id: true,
                                handle: true,
                                displayName: true,
                            },
                        },
                    },
                    orderBy: {
                        joinedAt: 'asc',
                    },
                },
            },
        });
        if (!circle) {
            throw new common_1.NotFoundException('Circle not found');
        }
        return {
            id: circle.id,
            name: circle.name,
            description: circle.description,
            isPrivate: circle.isPrivate,
            inviteCode: circle.inviteCode,
            maxMembers: circle.maxMembers,
            members: circle.members.map((m) => ({
                userId: m.user.id,
                handle: m.user.handle,
                displayName: m.user.displayName,
                role: m.role,
                joinedAt: m.joinedAt,
            })),
            createdAt: circle.createdAt,
        };
    }
    async getCircleFeed(userId, circleId, from, to) {
        const membership = await this.prisma.circleMember.findUnique({
            where: {
                circleId_userId: { circleId, userId },
            },
        });
        if (!membership || membership.status !== 'active') {
            throw new common_1.ForbiddenException({
                code: 'NOT_A_MEMBER',
                message: 'You are not a member of this circle',
            });
        }
        const dateFilter = {};
        if (from)
            dateFilter.gte = from;
        if (to)
            dateFilter.lte = to;
        const posts = await this.prisma.circlePost.findMany({
            where: {
                circleId,
                ...(Object.keys(dateFilter).length > 0
                    ? { localDate: dateFilter }
                    : {}),
            },
            include: {
                user: {
                    select: {
                        handle: true,
                        displayName: true,
                    },
                },
            },
            orderBy: {
                createdAt: 'desc',
            },
            take: 50,
        });
        return posts.map((p) => ({
            id: p.id,
            kind: p.kind,
            user: {
                handle: p.user.handle,
                displayName: p.user.displayName,
            },
            moodEmoji: p.moodEmoji,
            bodyText: p.bodyText,
            localDate: p.localDate,
            createdAt: p.createdAt,
        }));
    }
    async postCheckIn(userId, circleId, dto) {
        const membership = await this.prisma.circleMember.findUnique({
            where: {
                circleId_userId: { circleId, userId },
            },
        });
        if (!membership || membership.status !== 'active') {
            throw new common_1.ForbiddenException({
                code: 'NOT_A_MEMBER',
                message: 'You are not a member of this circle',
            });
        }
        const post = await this.prisma.circlePost.upsert({
            where: {
                circleId_userId_localDate_kind: {
                    circleId,
                    userId,
                    localDate: dto.localDate,
                    kind: 'checkin',
                },
            },
            create: {
                circleId,
                userId,
                kind: 'checkin',
                moodEmoji: dto.moodEmoji || null,
                bodyText: dto.bodyText || null,
                localDate: dto.localDate,
            },
            update: {
                moodEmoji: dto.moodEmoji || null,
                bodyText: dto.bodyText || null,
            },
            include: {
                user: {
                    select: {
                        handle: true,
                        displayName: true,
                    },
                },
            },
        });
        return {
            id: post.id,
            kind: post.kind,
            user: {
                handle: post.user.handle,
                displayName: post.user.displayName,
            },
            moodEmoji: post.moodEmoji,
            bodyText: post.bodyText,
            localDate: post.localDate,
            createdAt: post.createdAt,
        };
    }
    async checkCircleCreatorBadge(userId) {
        const circleCount = await this.prisma.circle.count({
            where: { ownerUserId: userId },
        });
        if (circleCount === 1) {
            const badge = await this.prisma.badge.findUnique({
                where: { code: 'circle_creator' },
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
};
exports.CirclesService = CirclesService;
exports.CirclesService = CirclesService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], CirclesService);
//# sourceMappingURL=circles.service.js.map