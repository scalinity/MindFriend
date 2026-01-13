import { QuestsService } from './quests.service';
import { CompleteQuestDto, QuestResponseDto, QuestCompletionResponseDto } from './dto/quests.dto';
export declare class QuestsController {
    private readonly questsService;
    constructor(questsService: QuestsService);
    getTodayQuest(userId: string): Promise<QuestResponseDto>;
    completeQuest(userId: string, questId: string, dto: CompleteQuestDto): Promise<QuestCompletionResponseDto>;
    skipQuest(userId: string, questId: string): Promise<{
        status: string;
    }>;
}
