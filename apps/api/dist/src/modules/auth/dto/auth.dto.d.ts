export declare class AppleAuthDto {
    identityToken: string;
    authorizationCode?: string;
    fullName?: string;
    email?: string;
}
export declare class RefreshTokenDto {
    refreshToken: string;
}
export declare class AuthResponseDto {
    accessToken: string;
    refreshToken: string;
    expiresIn: number;
    user: {
        id: string;
        handle: string;
        displayName: string;
        tier: 'free' | 'premium';
    };
}
export declare class LogoutDto {
    refreshToken: string;
}
