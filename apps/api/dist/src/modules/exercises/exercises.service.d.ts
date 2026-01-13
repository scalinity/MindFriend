import { PrismaService } from '../prisma/prisma.service';
import { CompleteSessionDto, ExerciseResponseDto, StartSessionResponseDto, CompleteSessionResponseDto } from './dto/exercises.dto';
export declare class ExercisesService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    getExercises(type?: string): Promise<ExerciseResponseDto[]>;
    startSession(userId: string, exerciseId: string): Promise<StartSessionResponseDto>;
    completeSession(userId: string, sessionId: string, dto: CompleteSessionDto): Promise<CompleteSessionResponseDto>;
}
