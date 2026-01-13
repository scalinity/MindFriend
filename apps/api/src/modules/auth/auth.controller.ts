import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import {
  AppleAuthDto,
  RefreshTokenDto,
  AuthResponseDto,
  LogoutDto,
} from './dto/auth.dto';
import { Public } from '../../common/decorators';

@Controller('v1/auth')
@Throttle({ default: { limit: 10, ttl: 60000 } }) // 10 requests per minute for auth
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('apple')
  @HttpCode(HttpStatus.OK)
  async authenticateWithApple(
    @Body() dto: AppleAuthDto,
  ): Promise<AuthResponseDto> {
    return this.authService.authenticateWithApple(dto);
  }

  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  async refreshTokens(@Body() dto: RefreshTokenDto): Promise<AuthResponseDto> {
    return this.authService.refreshTokens(dto);
  }

  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  async logout(@Body() dto: LogoutDto): Promise<void> {
    await this.authService.logout(dto.refreshToken);
  }
}
