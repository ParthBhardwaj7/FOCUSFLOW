import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { SignOptions } from 'jsonwebtoken';
import { PassportModule } from '@nestjs/passport';
import { PrismaModule } from '../../prisma/prisma.module';
import { ADMIN_JWT } from './admin.constants';
import { AdminAuthController } from './admin-auth.controller';
import { AdminAuthService } from './admin-auth.service';
import { AdminJwtStrategy } from './strategies/admin-jwt.strategy';
import { AuditLogService } from './audit-log.service';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from './admin-users.service';
import { AdminErrorsController } from './admin-errors.controller';
import { AdminErrorsService } from './admin-errors.service';
import { AdminFlagsController } from './admin-flags.controller';
import { AdminFlagsService } from './admin-flags.service';
import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminDashboardService } from './admin-dashboard.service';
import { AdminTasksController } from './admin-tasks.controller';
import { AdminTasksService } from './admin-tasks.service';
import {
  AdminAiInsightsController,
  AdminAiSuggestionsController,
  AdminCategoriesController,
  AdminSoundsController,
} from './admin-content.controllers';
import { AdminContentService } from './admin-content.service';
import { AdminNotificationsController } from './admin-notifications.controller';
import { AdminNotificationsService } from './admin-notifications.service';
import { AdminAppConfigController } from './admin-app-config.controller';
import { AdminAppConfigService } from './admin-app-config.service';
import { AdminAuditController } from './admin-audit.controller';
import { AdminSettingsController } from './admin-settings.controller';

@Module({
  imports: [PrismaModule, ConfigModule, PassportModule.register({})],
  controllers: [
    AdminAuthController,
    AdminUsersController,
    AdminErrorsController,
    AdminFlagsController,
    AdminDashboardController,
    AdminTasksController,
    AdminCategoriesController,
    AdminSoundsController,
    AdminAiSuggestionsController,
    AdminAiInsightsController,
    AdminNotificationsController,
    AdminAppConfigController,
    AdminAuditController,
    AdminSettingsController,
  ],
  providers: [
    AuditLogService,
    AdminAuthService,
    AdminJwtStrategy,
    AdminUsersService,
    AdminErrorsService,
    AdminFlagsService,
    AdminDashboardService,
    AdminTasksService,
    AdminContentService,
    AdminNotificationsService,
    AdminAppConfigService,
    {
      provide: ADMIN_JWT,
      useFactory: (config: ConfigService) => {
        const secret =
          config.get<string>('ADMIN_JWT_ACCESS_SECRET')?.trim() ||
          config.getOrThrow<string>('JWT_ACCESS_SECRET');
        const expiresIn = (config.get<string>('ADMIN_JWT_ACCESS_EXPIRES_IN') ??
          '15m') as SignOptions['expiresIn'];
        return new JwtService({
          secret,
          signOptions: { expiresIn },
        });
      },
      inject: [ConfigService],
    },
  ],
})
export class AdminModule {}
