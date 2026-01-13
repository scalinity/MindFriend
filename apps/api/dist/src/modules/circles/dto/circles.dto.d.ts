export declare class CreateCircleDto {
    name: string;
    description?: string;
    maxMembers?: number;
}
export declare class JoinCircleDto {
    inviteCode: string;
}
export declare class CircleCheckInDto {
    localDate: string;
    moodEmoji?: string;
    bodyText?: string;
}
export declare class CircleResponseDto {
    id: string;
    name: string;
    description: string | null;
    isPrivate: boolean;
    inviteCode: string;
    maxMembers: number;
    memberCount: number;
    role: string;
    createdAt: Date;
}
export declare class CircleListItemDto {
    id: string;
    name: string;
    memberCount: number;
    role: string;
}
export declare class CircleMemberDto {
    userId: string;
    handle: string;
    displayName: string;
    role: string;
    joinedAt: Date;
}
export declare class CircleDetailDto {
    id: string;
    name: string;
    description: string | null;
    isPrivate: boolean;
    inviteCode: string;
    maxMembers: number;
    members: CircleMemberDto[];
    createdAt: Date;
}
export declare class CirclePostDto {
    id: string;
    kind: string;
    user: {
        handle: string;
        displayName: string;
    };
    moodEmoji: string | null;
    bodyText: string | null;
    localDate: string;
    createdAt: Date;
}
export declare class JoinCircleResponseDto {
    circleId: string;
    role: string;
}
