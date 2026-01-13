import { PrismaService } from '../prisma/prisma.service';
import { CreateMoodDto, MoodEntryResponseDto, MoodHistoryResponseDto } from './dto/moods.dto';
export declare class MoodsService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    createOrUpdateMood(userId: string, dto: CreateMoodDto): Promise<MoodEntryResponseDto>;
    getMoodHistory(userId: string, from: string, to: string): Promise<MoodHistoryResponseDto>;
    private checkMoodBadge;
    private formatMoodResponse;
    private getLocalDate;
}
