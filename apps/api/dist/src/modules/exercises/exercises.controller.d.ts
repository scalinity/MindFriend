import { ExercisesService } from './exercises.service';
import { CompleteSessionDto, ExerciseResponseDto, StartSessionResponseDto, CompleteSessionResponseDto } from './dto/exercises.dto';
export declare class ExercisesController {
    private readonly exercisesService;
    constructor(exercisesService: ExercisesService);
    getExercises(type?: string): Promise<ExerciseResponseDto[]>;
    startSession(userId: string, exerciseId: string): Promise<StartSessionResponseDto>;
    completeSession(userId: string, sessionId: string, dto: CompleteSessionDto): Promise<CompleteSessionResponseDto>;
}
