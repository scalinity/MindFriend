import { PrismaService } from '../prisma/prisma.service';
import { CrisisResourcesResponseDto } from './dto/resources.dto';
export declare class ResourcesService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    getCrisisResources(country?: string): Promise<CrisisResourcesResponseDto>;
}
