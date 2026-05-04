import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { UserRole } from '@prisma/client';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import { AdminRoles } from './decorators/admin-roles.decorator';
import {
  AdminUser,
  type AdminRequestUser,
} from './decorators/admin-user.decorator';
import { AdminUsersService } from './admin-users.service';
import { AdminAppConfigService } from './admin-app-config.service';
import { assertSlackIncomingWebhookUrl } from '../../common/utils/slack-webhook-url';

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/settings', version: VERSION_NEUTRAL })
export class AdminSettingsController {
  constructor(
    private readonly users: AdminUsersService,
    private readonly cfg: AdminAppConfigService,
    private readonly config: ConfigService,
  ) {}

  @Get('integrations')
  integrations() {
    return {
      llmConfigured: Boolean(
        this.config.get('LLM_PROVIDER') &&
        this.config.get('LLM_API_KEY') &&
        this.config.get('LLM_MODEL'),
      ),
      fcmConfigured: Boolean(this.config.get('FCM_SERVER_KEY')),
      hasSmtpHost: Boolean(this.config.get('SMTP_HOST')),
    };
  }

  @Post('admins')
  /** Any signed-in admin may create additional ADMIN accounts (not SUPERADMIN). */
  @AdminRoles(UserRole.SUPERADMIN, UserRole.ADMIN)
  createAdmin(
    @Body() body: { email: string; password: string },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.users.createAdminUser(
      body.email,
      body.password,
      admin.userId,
      clientIp(req),
    );
  }

  @Post('slack-webhook')
  @AdminRoles(UserRole.SUPERADMIN)
  async slackWebhook(
    @Body() body: { url: string },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    if (typeof body?.url !== 'string' || !body.url.trim()) {
      throw new BadRequestException('url is required');
    }
    assertSlackIncomingWebhookUrl(body.url);
    return this.cfg.putKey(
      'slack_webhook_url',
      body.url.trim(),
      admin.userId,
      clientIp(req),
      'Slack webhook for alerts',
      false,
    );
  }

  @Post('maintenance')
  @AdminRoles(UserRole.SUPERADMIN)
  maintenance(
    @Body() body: { enabled: boolean },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.cfg.putKey(
      'maintenance_mode',
      body.enabled ? 'true' : 'false',
      admin.userId,
      clientIp(req),
      'When true, mobile API returns maintenance for non-essential routes',
      true,
    );
  }
}
