export declare class CreateMoodDto {
    moodScore: number;
    anxietyScore?: number;
    energyScore?: number;
    note?: string;
    source?: string;
}
export declare class MoodEntryResponseDto {
    id: string;
    localDate: string;
    moodScore: number;
    anxietyScore: number | null;
    energyScore: number | null;
    note: string | null;
    source: string;
    createdAt: Date;
}
export declare class MoodHistoryResponseDto {
    entries: MoodEntryResponseDto[];
    summary: {
        avgMoodScore: number;
        avgAnxietyScore: number | null;
        avgEnergyScore: number | null;
        totalEntries: number;
    };
}
