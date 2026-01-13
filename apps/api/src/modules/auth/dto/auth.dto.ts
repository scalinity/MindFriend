import { IsString, IsNotEmpty, IsOptional, IsEmail } from 'class-validator';

export class AppleAuthDto {
  @IsString()
  @IsNotEmpty()
  identityToken: string;

  @IsString()
  @IsOptional()
  authorizationCode?: string;

  @IsString()
  @IsOptional()
  fullName?: string;

  @IsEmail()
  @IsOptional()
  email?: string;
}

export class RefreshTokenDto {
  @IsString()
  @IsNotEmpty()
  refreshToken: string;
}

export class AuthResponseDto {
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

export class LogoutDto {
  @IsString()
  @IsNotEmpty()
  refreshToken: string;
}
