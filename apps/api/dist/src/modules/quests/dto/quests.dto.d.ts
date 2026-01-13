export declare class CompleteQuestDto {
    reflectionNote?: string;
    rating?: number;
}
export declare class QuestResponseDto {
    id: string;
    localDate: string;
    status: string;
    assignedAt: Date;
    completedAt: Date | null;
    template: {
        id: string;
        type: string;
        title: string;
        description: string;
        estimatedMinutes: number;
        difficulty: number;
        tags: string[];
        instructions: unknown;
    };
}
export declare class QuestCompletionResponseDto {
    questId: string;
    status: string;
    completedAt: Date;
    streakDays: number;
    badgesEarned: Array<{
        code: string;
        title: string;
    }>;
}
