import { Body, Controller, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../../common/decorators/public.decorator';
import { AuthService } from './auth.service';
import { ForgotPasswordRequestDto } from './dto/forgot-password-request.dto';
import { ForgotPasswordResetDto } from './dto/forgot-password-reset.dto';
import { GoogleLoginDto } from './dto/google-login.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';
import { RegisterDto } from './dto/register.dto';

@Public()
@Throttle({ default: { limit: 25, ttl: 60_000 } })
@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto.email, dto.password);
  }

  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.email, dto.password);
  }

  @Post('google')
  googleLogin(@Body() dto: GoogleLoginDto) {
    return this.auth.loginWithGoogleTokens(dto.idToken, dto.accessToken);
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @Post('logout')
  logout(@Body() dto: RefreshDto) {
    return this.auth.logout(dto.refreshToken);
  }

  @Post('forgot-password/request')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  forgotPasswordRequest(@Body() dto: ForgotPasswordRequestDto) {
    return this.auth.requestPasswordResetCode(dto.email);
  }

  @Post('forgot-password/reset')
  @Throttle({ default: { limit: 8, ttl: 60_000 } })
  forgotPasswordReset(@Body() dto: ForgotPasswordResetDto) {
    return this.auth.resetPasswordWithCode(dto.email, dto.code, dto.newPassword);
  }
}
