"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var AuthService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const config_1 = require("@nestjs/config");
const jose = __importStar(require("jose"));
const bcrypt = __importStar(require("bcrypt"));
const uuid_1 = require("uuid");
const prisma_service_1 = require("../prisma/prisma.service");
let AuthService = AuthService_1 = class AuthService {
    prisma;
    jwtService;
    configService;
    logger = new common_1.Logger(AuthService_1.name);
    isMockAuth;
    accessTokenTtl;
    refreshTokenTtl;
    appleJWKS = null;
    constructor(prisma, jwtService, configService) {
        this.prisma = prisma;
        this.jwtService = jwtService;
        this.configService = configService;
        this.isMockAuth = this.configService.get('APPLE_AUTH_MOCK') === 'true';
        this.accessTokenTtl = parseInt(this.configService.get('JWT_ACCESS_TTL_SECONDS', '900'), 10);
        this.refreshTokenTtl = parseInt(this.configService.get('JWT_REFRESH_TTL_SECONDS', '2592000'), 10);
    }
    async authenticateWithApple(dto) {
        let applePayload;
        if (this.isMockAuth) {
            applePayload = this.createMockApplePayload(dto);
            this.logger.warn('Using mocked Apple authentication');
        }
        else {
            applePayload = await this.verifyAppleToken(dto.identityToken);
        }
        const user = await this.findOrCreateUser(applePayload, dto);
        return this.generateAuthResponse(user);
    }
    async refreshTokens(dto) {
        const tokenHash = await this.hashToken(dto.refreshToken);
        const storedToken = await this.prisma.refreshToken.findFirst({
            where: {
                tokenHash,
                revokedAt: null,
                expiresAt: { gt: new Date() },
            },
            include: { user: true },
        });
        if (!storedToken) {
            throw new common_1.UnauthorizedException('Invalid or expired refresh token');
        }
        const newTokenId = (0, uuid_1.v4)();
        await this.prisma.refreshToken.update({
            where: { id: storedToken.id },
            data: {
                revokedAt: new Date(),
                replacedById: newTokenId,
            },
        });
        const tier = await this.getUserTier(storedToken.userId);
        const user = {
            id: storedToken.user.id,
            handle: storedToken.user.handle,
            displayName: storedToken.user.displayName,
            tier,
        };
        return this.generateAuthResponse(user, storedToken.deviceId || undefined);
    }
    async logout(refreshToken) {
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
    createMockApplePayload(dto) {
        const mockId = dto.identityToken.startsWith('mock_')
            ? dto.identityToken
            : `mock_${(0, uuid_1.v4)().substring(0, 8)}`;
        return {
            sub: mockId,
            email: dto.email || `${mockId}@mock.mindfriend.app`,
            email_verified: true,
            aud: this.configService.get('APPLE_AUDIENCE', 'com.yourcompany.mindfriend'),
            iss: 'https://appleid.apple.com',
        };
    }
    async verifyAppleToken(identityToken) {
        try {
            if (!this.appleJWKS) {
                this.appleJWKS = jose.createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
            }
            const { payload } = await jose.jwtVerify(identityToken, this.appleJWKS, {
                issuer: 'https://appleid.apple.com',
                audience: this.configService.get('APPLE_AUDIENCE'),
            });
            return payload;
        }
        catch (error) {
            this.logger.error('Apple token verification failed', error);
            throw new common_1.UnauthorizedException('Invalid Apple identity token');
        }
    }
    async findOrCreateUser(applePayload, dto) {
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
            tier: 'free',
        };
    }
    async generateUniqueHandle(name) {
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
        return `user${(0, uuid_1.v4)().substring(0, 8)}`;
    }
    async getUserTier(userId) {
        const subscription = await this.prisma.subscription.findFirst({
            where: {
                userId,
                status: { in: ['active', 'grace'] },
            },
        });
        return subscription ? 'premium' : 'free';
    }
    async generateAuthResponse(user, deviceId) {
        const accessPayload = {
            sub: user.id,
            tier: user.tier,
        };
        const accessToken = this.jwtService.sign(accessPayload, {
            secret: this.configService.get('JWT_ACCESS_SECRET'),
            expiresIn: this.accessTokenTtl,
        });
        const refreshTokenValue = (0, uuid_1.v4)();
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
    async hashToken(token) {
        return bcrypt.hash(token, 10);
    }
};
exports.AuthService = AuthService;
exports.AuthService = AuthService = AuthService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        jwt_1.JwtService,
        config_1.ConfigService])
], AuthService);
//# sourceMappingURL=auth.service.js.map