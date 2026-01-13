import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CrisisResourcesResponseDto } from './dto/resources.dto';

const DISCLAIMER =
  'MindFriend is not a medical provider. If you are in immediate danger, call your local emergency number.';

@Injectable()
export class ResourcesService {
  constructor(private readonly prisma: PrismaService) {}

  async getCrisisResources(
    country?: string,
  ): Promise<CrisisResourcesResponseDto> {
    // Default to US if no country specified, also fetch global resources
    const countryCode = country?.toUpperCase() || 'US';

    const resources = await this.prisma.crisisResource.findMany({
      where: {
        OR: [{ countryCode }, { countryCode: 'GLOBAL' }],
        active: true,
      },
      orderBy: [
        { countryCode: 'asc' }, // Country-specific first
        { name: 'asc' },
      ],
    });

    // Prioritize country-specific resources over global ones
    const countryResources = resources.filter(
      (r) => r.countryCode === countryCode,
    );
    const globalResources = resources.filter((r) => r.countryCode === 'GLOBAL');

    // If no country-specific resources, use global
    const finalResources =
      countryResources.length > 0 ? countryResources : globalResources;

    return {
      country: countryCode,
      items: finalResources.map((r) => ({
        name: r.name,
        contact: r.contact,
        kind: r.kind,
      })),
      disclaimer: DISCLAIMER,
    };
  }
}
