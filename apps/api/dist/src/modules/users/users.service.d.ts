import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateProfileDto, UpdateSettingsDto, RegisterDeviceDto, UserProfileResponseDto } from './dto/users.dto';
export declare class UsersService {
    private readonly prisma;
    private readonly configService;
    private readonly dailyFreeQuota;
    private readonly premiumQuota;
    constructor(prisma: PrismaService, configService: ConfigService);
    getProfile(userId: string): Promise<UserProfileResponseDto>;
    updateProfile(userId: string, dto: UpdateProfileDto): Promise<{
        id: string;
        handle: string;
        displayName: string;
        timezone: string;
    }>;
    updateSettings(userId: string, dto: UpdateSettingsDto): Promise<{
        message: string;
    }>;
    registerDevice(userId: string, dto: RegisterDeviceDto): Promise<{
        deviceId: string;
    }>;
    private getLocalDate;
    private calculateQuietHoursSpan;
    deleteAccount(userId: string): Promise<{
        message: string;
    }>;
    exportData(userId: string): Promise<any>;
}
