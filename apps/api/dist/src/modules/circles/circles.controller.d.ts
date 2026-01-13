import { CirclesService } from './circles.service';
import { CreateCircleDto, JoinCircleDto, CircleCheckInDto, CircleResponseDto, CircleListItemDto, CircleDetailDto, CirclePostDto, JoinCircleResponseDto } from './dto/circles.dto';
export declare class CirclesController {
    private readonly circlesService;
    constructor(circlesService: CirclesService);
    createCircle(userId: string, dto: CreateCircleDto): Promise<CircleResponseDto>;
    joinCircle(userId: string, dto: JoinCircleDto): Promise<JoinCircleResponseDto>;
    getCircles(userId: string): Promise<CircleListItemDto[]>;
    getCircleDetail(userId: string, circleId: string): Promise<CircleDetailDto>;
    getCircleFeed(userId: string, circleId: string, from?: string, to?: string): Promise<CirclePostDto[]>;
    postCheckIn(userId: string, circleId: string, dto: CircleCheckInDto): Promise<CirclePostDto>;
}
