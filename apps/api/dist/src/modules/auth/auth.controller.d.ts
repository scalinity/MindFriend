import { AuthService } from './auth.service';
import { AppleAuthDto, RefreshTokenDto, AuthResponseDto, LogoutDto } from './dto/auth.dto';
export declare class AuthController {
    private readonly authService;
    constructor(authService: AuthService);
    authenticateWithApple(dto: AppleAuthDto): Promise<AuthResponseDto>;
    refreshTokens(dto: RefreshTokenDto): Promise<AuthResponseDto>;
    logout(dto: LogoutDto): Promise<void>;
}
