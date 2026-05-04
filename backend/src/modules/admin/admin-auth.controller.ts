import { Body, Controller, Post, Req } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminAuthService } from './admin-auth.service';
import { AdminLoginDto } from './dto/admin-login.dto';
import { AdminRefreshDto } from './dto/admin-refresh.dto';
import { VERSION_NEUTRAL } from '@nestjs/common';

function clientIp(req: Request): string {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? 'unknown';
}

@Public()
@Throttle({ default: { limit: 30, ttl: 60_000 } })
@Controller({ path: 'admin/auth', version: VERSION_NEUTRAL })
export class AdminAuthController {
  constructor(private readonly adminAuth: AdminAuthService) {}

  @Post('login')
  login(@Body() dto: AdminLoginDto, @Req() req: Request) {
    return this.adminAuth.login(dto.email, dto.password, clientIp(req));
  }

  @Post('refresh')
  refresh(@Body() dto: AdminRefreshDto) {
    return this.adminAuth.refresh(dto.refreshToken);
  }

  @Post('logout')
  logout(@Body() dto: AdminRefreshDto) {
    return this.adminAuth.logout(dto.refreshToken);
  }
}
