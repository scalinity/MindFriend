export declare class CrisisResourceDto {
    name: string;
    contact: string;
    kind: string;
}
export declare class CrisisResourcesResponseDto {
    country: string;
    items: CrisisResourceDto[];
    disclaimer: string;
}
