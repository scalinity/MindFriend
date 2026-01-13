import {
  Injectable,
  UnauthorizedException,
  Logger,
  ConflictException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as jose from 'jose';
import * as bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';
import { PrismaService } from '../prisma/prisma.service';
import { AppleAuthDto, AuthResponseDto, RefreshTokenDto } from './dto/auth.dto';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

interface AppleTokenPayload {
  sub: string;
  email?: string;
  email_verified?: boolean;
  aud: string;
  iss: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly isMockAuth: boolean;
  private readonly accessTokenTtl: number;
  private readonly refreshTokenTtl: number;
  private appleJWKS: jose.JWTVerifyGetKey | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {
    this.isMockAuth = this.configService.get('APPLE_AUTH_MOCK') === 'true';
    this.accessTokenTtl = parseInt(
      this.configService.get('JWT_ACCESS_TTL_SECONDS', '900'),
      10,
    );
    this.refreshTokenTtl = parseInt(
      this.configService.get('JWT_REFRESH_TTL_SECONDS', '2592000'),
      10,
    );
  }

  async authenticateWithApple(dto: AppleAuthDto): Promise<AuthResponseDto> {
    let applePayload: AppleTokenPayload;

    if (this.isMockAuth) {
      // Mock authentication for development
      applePayload = this.createMockApplePayload(dto);
      this.logger.warn('Using mocked Apple authentication');
    } else {
      // Real Apple token verification
      applePayload = await this.verifyAppleToken(dto.identityToken);
    }

    // Find or create user
    const user = await this.findOrCreateUser(applePayload, dto);

    // Generate tokens
    return this.generateAuthResponse(user);
  }

  async refreshTokens(dto: RefreshTokenDto): Promise<AuthResponseDto> {
    const tokenHash = await this.hashToken(dto.refreshToken);

    // Find the refresh token
    const storedToken = await this.prisma.refreshToken.findFirst({
      where: {
        tokenHash,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      include: { user: true },
    });

    if (!storedToken) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    // Revoke the old token (rotation)
    const newTokenId = uuidv4();
    await this.prisma.refreshToken.update({
      where: { id: storedToken.id },
      data: {
        revokedAt: new Date(),
        replacedById: newTokenId,
      },
    });

    // Get user tier
    const tier = await this.getUserTier(storedToken.userId);

    // Generate new tokens
    const user = {
      id: storedToken.user.id,
      handle: storedToken.user.handle,
      displayName: storedToken.user.displayName,
      tier,
    };

    return this.generateAuthResponse(user, storedToken.deviceId || undefined);
  }

  async logout(refreshToken: string): Promise<void> {
    const tokenHash = await this.hashToken(refreshToken);

    await this.prisma.refreshToken.updateMany({
      where: {
        tokenHash,
        revokedAt: null,
      },
      data: {
        revokedAt: new Date(),
      },
    });
  }

  private createMockApplePayload(dto: AppleAuthDto): AppleTokenPayload {
    // For mocked auth, the identityToken is treated as a mock user identifier
    // Format: "mock_<userId>" or any string for new user creation
    const mockId = dto.identityToken.startsWith('mock_')
      ? dto.identityToken
      : `mock_${uuidv4().substring(0, 8)}`;

    return {
      sub: mockId,
      email: dto.email || `${mockId}@mock.mindfriend.app`,
      email_verified: true,
      aud: this.configService.get(
        'APPLE_AUDIENCE',
        'com.yourcompany.mindfriend',
      ),
      iss: 'https://appleid.apple.com',
    };
  }

  private async verifyAppleToken(
    identityToken: string,
  ): Promise<AppleTokenPayload> {
    try {
      // Initialize JWKS if not already done
      if (!this.appleJWKS) {
        this.appleJWKS = jose.createRemoteJWKSet(
          new URL('https://appleid.apple.com/auth/keys'),
        );
      }

      const { payload } = await jose.jwtVerify(identityToken, this.appleJWKS, {
        issuer: 'https://appleid.apple.com',
        audience: this.configService.get('APPLE_AUDIENCE'),
      });

      return payload as unknown as AppleTokenPayload;
    } catch (error) {
      this.logger.error('Apple token verification failed', error);
      throw new UnauthorizedException('Invalid Apple identity token');
    }
  }

  private async findOrCreateUser(
    applePayload: AppleTokenPayload,
    dto: AppleAuthDto,
  ) {
    // Check if user already exists with this Apple ID
    const existingIdentity = await this.prisma.authIdentity.findUnique({
      where: {
        provider_providerSubject: {
          provider: 'apple',
          providerSubject: applePayload.sub,
        },
      },
      include: { user: true },
    });

    if (existingIdentity) {
      // User exists, update email if provided
      if (applePayload.email && !existingIdentity.email) {
        await this.prisma.authIdentity.update({
          where: { id: existingIdentity.id },
          data: {
            email: applePayload.email,
            emailVerified: applePayload.email_verified || false,
          },
        });
      }

      const tier = await this.getUserTier(existingIdentity.user.id);
      return {
        id: existingIdentity.user.id,
        handle: existingIdentity.user.handle,
        displayName: existingIdentity.user.displayName,
        tier,
      };
    }

    // Create new user
    const handle = await this.generateUniqueHandle(dto.fullName);
    const displayName = dto.fullName || 'Friend';

    const user = await this.prisma.user.create({
      data: {
        handle,
        displayName,
        email: applePayload.email,
        authIdentities: {
          create: {
            provider: 'apple',
            providerSubject: applePayload.sub,
            email: applePayload.email,
            emailVerified: applePayload.email_verified || false,
          },
        },
        settings: {
          create: {},
        },
        stats: {
          create: {},
        },
      },
    });

    return {
      id: user.id,
      handle: user.handle,
      displayName: user.displayName,
      tier: 'free' as const,
    };
  }

  private async generateUniqueHandle(name?: string): Promise<string> {
    const base = name
      ? name
          .toLowerCase()
          .replace(/[^a-z0-9]/g, '')
          .substring(0, 16)
      : 'friend';

    let handle = base;
    let suffix = Math.floor(Math.random() * 9999);
    let attempts = 0;

    while (attempts < 10) {
      const exists = await this.prisma.user.findUnique({
        where: { handle },
        select: { id: true },
      });

      if (!exists) {
        return handle;
      }

      handle = `${base}${suffix}`;
      suffix = Math.floor(Math.random() * 9999);
      attempts++;
    }

    // Fallback to UUID-based handle
    return `user${uuidv4().substring(0, 8)}`;
  }

  private async getUserTier(userId: string): Promise<'free' | 'premium'> {
    const subscription = await this.prisma.subscription.findFirst({
      where: {
        userId,
        status: { in: ['active', 'grace'] },
      },
    });

    return subscription ? 'premium' : 'free';
  }

  private async generateAuthResponse(
    user: {
      id: string;
      handle: string;
      displayName: string;
      tier: 'free' | 'premium';
    },
    deviceId?: string,
  ): Promise<AuthResponseDto> {
    // Generate access token
    const accessPayload: Omit<JwtPayload, 'iat' | 'exp'> = {
      sub: user.id,
      tier: user.tier,
    };

    const accessToken = this.jwtService.sign(accessPayload, {
      secret: this.configService.get('JWT_ACCESS_SECRET'),
      expiresIn: this.accessTokenTtl,
    });

    // Generate refresh token
    const refreshTokenValue = uuidv4();
    const refreshTokenHash = await this.hashToken(refreshTokenValue);

    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: refreshTokenHash,
        deviceId: deviceId || null,
        expiresAt: new Date(Date.now() + this.refreshTokenTtl * 1000),
      },
    });

    return {
      accessToken,
      refreshToken: refreshTokenValue,
      expiresIn: this.accessTokenTtl,
      user: {
        id: user.id,
        handle: user.handle,
        displayName: user.displayName,
        tier: user.tier,
      },
    };
  }

  private async hashToken(token: string): Promise<string> {
    return bcrypt.hash(token, 10);
  }
}
