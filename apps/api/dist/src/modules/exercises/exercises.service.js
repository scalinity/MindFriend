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
exports.ExercisesService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let ExercisesService = class ExercisesService {
    prisma;
    constructor(prisma) {
        this.prisma = prisma;
    }
    async getExercises(type) {
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
    async startSession(userId, exerciseId) {
        const exercise = await this.prisma.exercise.findUnique({
            where: { id: exerciseId },
        });
        if (!exercise || !exercise.active) {
            throw new common_1.NotFoundException('Exercise not found');
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
    async completeSession(userId, sessionId, dto) {
        const session = await this.prisma.exerciseSession.findFirst({
            where: { id: sessionId, userId },
        });
        if (!session) {
            throw new common_1.NotFoundException('Session not found');
        }
        if (session.completed) {
            throw new common_1.BadRequestException('Session already completed');
        }
        await this.prisma.exerciseSession.update({
            where: { id: sessionId },
            data: {
                completed: true,
                endedAt: new Date(),
                rating: dto.rating || null,
                note: dto.note || null,
            },
        });
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
};
exports.ExercisesService = ExercisesService;
exports.ExercisesService = ExercisesService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], ExercisesService);
//# sourceMappingURL=exercises.service.js.map