import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { PushTargetType } from '@prisma/client';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import {
  AdminUser,
  type AdminRequestUser,
} from './decorators/admin-user.decorator';
import { AdminNotificationsService } from './admin-notifications.service';

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/notifications', version: VERSION_NEUTRAL })
export class AdminNotificationsController {
  constructor(private readonly notifications: AdminNotificationsService) {}

  @Get('history')
  history() {
    return this.notifications.history();
  }

  @Post('send')
  send(
    @Body()
    body: {
      title: string;
      body: string;
      targetType: PushTargetType;
      targetUserIds?: string[];
      scheduledAt?: string | null;
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.notifications.send(
      {
        title: body.title,
        body: body.body,
        targetType: body.targetType,
        targetUserIds: body.targetUserIds,
        scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : null,
      },
      admin.userId,
      clientIp(req),
    );
  }

  @Post('schedule')
  schedule(
    @Body()
    body: {
      title: string;
      body: string;
      targetType: PushTargetType;
      targetUserIds?: string[];
      segmentFilter?: Record<string, unknown>;
      scheduledAt: string;
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.notifications.schedule(
      {
        title: body.title,
        body: body.body,
        targetType: body.targetType,
        targetUserIds: body.targetUserIds,
        segmentFilter: body.segmentFilter,
        scheduledAt: new Date(body.scheduledAt),
      },
      admin.userId,
      clientIp(req),
    );
  }
}
