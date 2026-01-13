import { MoodsService } from './moods.service';
import { CreateMoodDto, MoodEntryResponseDto, MoodHistoryResponseDto } from './dto/moods.dto';
export declare class MoodsController {
    private readonly moodsService;
    constructor(moodsService: MoodsService);
    createMood(userId: string, dto: CreateMoodDto): Promise<MoodEntryResponseDto>;
    getMoodHistory(userId: string, from: string, to: string): Promise<MoodHistoryResponseDto>;
}
