import {
  Body,
  Controller,
  DefaultValuePipe,
  Get,
  Param,
  ParseIntPipe,
  Put,
  Query,
  Req,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { ErrorResolutionStatus } from '@prisma/client';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import {
  AdminUser,
  type AdminRequestUser,
} from './decorators/admin-user.decorator';
import { AdminErrorsService } from './admin-errors.service';

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/errors', version: VERSION_NEUTRAL })
export class AdminErrorsController {
  constructor(private readonly errors: AdminErrorsService) {}

  @Get()
  list(
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('limit', new DefaultValuePipe(50), ParseIntPipe) limit: number,
    @Query('screen') screen?: string,
    @Query('errorType') errorType?: string,
    @Query('status') status?: ErrorResolutionStatus,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('appVersion') appVersion?: string,
    @Query('deviceOs') deviceOs?: string,
  ) {
    return this.errors.list({
      page,
      limit: Math.min(limit, 200),
      screen,
      errorType,
      status,
      from: from ? new Date(from) : undefined,
      to: to ? new Date(to) : undefined,
      appVersion,
      deviceOs,
    });
  }

  @Get('grouped')
  grouped(
    @Query('sinceHours', new DefaultValuePipe(24), ParseIntPipe) h: number,
  ) {
    return this.errors.grouped(h);
  }

  @Get('alert-config')
  alertConfig() {
    return this.errors.getAlertConfig();
  }

  @Put('alert-config')
  putAlertConfig(@Body() body: Record<string, unknown>) {
    return this.errors.updateAlertConfig(
      body as Parameters<AdminErrorsService['updateAlertConfig']>[0],
    );
  }

  @Put(':id/resolve')
  resolve(
    @Param('id') id: string,
    @Body() body: { note?: string },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.errors.resolve(id, admin.userId, clientIp(req), body?.note);
  }
}
