import { ResourcesService } from './resources.service';
import { CrisisResourcesResponseDto } from './dto/resources.dto';
export declare class ResourcesController {
    private readonly resourcesService;
    constructor(resourcesService: ResourcesService);
    getCrisisResources(country?: string): Promise<CrisisResourcesResponseDto>;
}
