export declare class CompleteSessionDto {
    rating?: number;
    note?: string;
}
export declare class ExerciseResponseDto {
    id: string;
    type: string;
    title: string;
    description: string;
    durationSeconds: number;
    contentKind: string;
    contentText: string | null;
    audioUrl: string | null;
    tags: string[];
}
export declare class StartSessionResponseDto {
    sessionId: string;
    startedAt: Date;
}
export declare class CompleteSessionResponseDto {
    ok: boolean;
    stats: {
        totalExercisesCompleted: number;
    };
}
