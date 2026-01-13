export class CrisisResourceDto {
  name: string;
  contact: string;
  kind: string;
}

export class CrisisResourcesResponseDto {
  country: string;
  items: CrisisResourceDto[];
  disclaimer: string;
}
