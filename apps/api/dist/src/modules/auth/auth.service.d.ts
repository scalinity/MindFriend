import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { AppleAuthDto, AuthResponseDto, RefreshTokenDto } from './dto/auth.dto';
export declare class AuthService {
    private readonly prisma;
    private readonly jwtService;
    private readonly configService;
    private readonly logger;
    private readonly isMockAuth;
    private readonly accessTokenTtl;
    private readonly refreshTokenTtl;
    private appleJWKS;
    constructor(prisma: PrismaService, jwtService: JwtService, configService: ConfigService);
    authenticateWithApple(dto: AppleAuthDto): Promise<AuthResponseDto>;
    refreshTokens(dto: RefreshTokenDto): Promise<AuthResponseDto>;
    logout(refreshToken: string): Promise<void>;
    private createMockApplePayload;
    private verifyAppleToken;
    private findOrCreateUser;
    private generateUniqueHandle;
    private getUserTier;
    private generateAuthResponse;
    private hashToken;
}
