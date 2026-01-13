import { UsersService } from './users.service';
import { UpdateProfileDto, UpdateSettingsDto, RegisterDeviceDto, UserProfileResponseDto } from './dto/users.dto';
export declare class UsersController {
    private readonly usersService;
    constructor(usersService: UsersService);
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
    deleteAccount(userId: string): Promise<{
        message: string;
    }>;
    exportData(userId: string): Promise<any>;
}
