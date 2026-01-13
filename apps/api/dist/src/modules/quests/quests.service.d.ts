import { PrismaService } from '../prisma/prisma.service';
import { CompleteQuestDto, QuestResponseDto, QuestCompletionResponseDto } from './dto/quests.dto';
export declare class QuestsService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    getTodayQuest(userId: string): Promise<QuestResponseDto>;
    completeQuest(userId: string, questId: string, dto: CompleteQuestDto): Promise<QuestCompletionResponseDto>;
    skipQuest(userId: string, questId: string): Promise<{
        status: string;
    }>;
    private assignQuest;
    private updateStreak;
    private evaluateBadges;
    private formatQuestResponse;
    private getLocalDate;
    private getYesterday;
}
