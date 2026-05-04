import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
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
import { AdminFlagsService } from './admin-flags.service';
import { AdminCreateFlagDto } from './dto/admin-create-flag.dto';
import { AdminUpdateFlagDto } from './dto/admin-update-flag.dto';

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/flags', version: VERSION_NEUTRAL })
export class AdminFlagsController {
  constructor(private readonly flags: AdminFlagsService) {}

  @Get()
  list() {
    return this.flags.list();
  }

  @Post()
  create(
    @Body() dto: AdminCreateFlagDto,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.flags.create(dto, admin.userId, clientIp(req));
  }

  @Put(':key')
  update(
    @Param('key') key: string,
    @Body() dto: AdminUpdateFlagDto,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.flags.updateByKey(key, dto, admin.userId, clientIp(req));
  }
}
