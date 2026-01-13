import { Controller, Get, Patch, Post, Body } from '@nestjs/common';
import { UsersService } from './users.service';
import {
  UpdateProfileDto,
  UpdateSettingsDto,
  RegisterDeviceDto,
  UserProfileResponseDto,
} from './dto/users.dto';
import { CurrentUser } from '../../common/decorators';

@Controller('v1')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('me')
  async getProfile(
    @CurrentUser('sub') userId: string,
  ): Promise<UserProfileResponseDto> {
    return this.usersService.getProfile(userId);
  }

  @Patch('me')
  async updateProfile(
    @CurrentUser('sub') userId: string,
    @Body() dto: UpdateProfileDto,
  ) {
    return this.usersService.updateProfile(userId, dto);
  }

  @Patch('me/settings')
  async updateSettings(
    @CurrentUser('sub') userId: string,
    @Body() dto: UpdateSettingsDto,
  ) {
    return this.usersService.updateSettings(userId, dto);
  }

  @Post('devices/register')
  async registerDevice(
    @CurrentUser('sub') userId: string,
    @Body() dto: RegisterDeviceDto,
  ) {
    return this.usersService.registerDevice(userId, dto);
  }

  /**
   * Delete user account with data anonymization.
   * This is a soft delete that anonymizes PII for GDPR compliance.
   */
  @Post('me/delete')
  async deleteAccount(
    @CurrentUser('sub') userId: string,
  ): Promise<{ message: string }> {
    return this.usersService.deleteAccount(userId);
  }

  /**
   * Export all user data as JSON.
   * Returns comprehensive user data for GDPR data portability compliance.
   */
  @Post('me/export')
  async exportData(@CurrentUser('sub') userId: string): Promise<any> {
    return this.usersService.exportData(userId);
  }
}
