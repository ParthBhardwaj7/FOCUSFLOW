import {
  Body,
  Controller,
  Get,
  Put,
  Param,
  Req,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import {
  AdminUser,
  type AdminRequestUser,
} from './decorators/admin-user.decorator';
import { AdminAppConfigService } from './admin-app-config.service';

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/config', version: VERSION_NEUTRAL })
export class AdminAppConfigController {
  constructor(private readonly cfg: AdminAppConfigService) {}

  @Get()
  list() {
    return this.cfg.list();
  }

  @Put(':key')
  put(
    @Param('key') key: string,
    @Body() body: { value: string; description?: string; isPublic?: boolean },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.cfg.putKey(
      key,
      body.value,
      admin.userId,
      clientIp(req),
      body.description,
      body.isPublic,
    );
  }
}
