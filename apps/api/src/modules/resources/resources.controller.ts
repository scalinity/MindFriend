import { Controller, Get, Query } from '@nestjs/common';
import { ResourcesService } from './resources.service';
import { CrisisResourcesResponseDto } from './dto/resources.dto';
import { Public } from '../../common/decorators';

@Controller('v1/resources')
export class ResourcesController {
  constructor(private readonly resourcesService: ResourcesService) {}

  /**
   * Get crisis resources/hotlines.
   * This endpoint is PUBLIC for safety - anyone should be able to access crisis resources.
   */
  @Public()
  @Get('crisis')
  async getCrisisResources(
    @Query('country') country?: string,
  ): Promise<CrisisResourcesResponseDto> {
    return this.resourcesService.getCrisisResources(country);
  }
}
