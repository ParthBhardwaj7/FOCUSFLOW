import {
  MiddlewareConsumer,
  Module,
  NestModule,
  ValidationPipe,
  HttpStatus,
} from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { LoggerModule } from 'nestjs-pino';
import { validateEnv } from './config/env.validation';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RequestIdInterceptor } from './common/interceptors/request-id.interceptor';
import { AuthModule } from './modules/auth/auth.module';
import { FocusSessionsModule } from './modules/focus-sessions/focus-sessions.module';
import { HealthModule } from './modules/health/health.module';
import { NotesModule } from './modules/notes/notes.module';
import { TasksModule } from './modules/tasks/tasks.module';
import { AiModule } from './modules/ai/ai.module';
import { AnalyticsModule } from './modules/analytics/analytics.module';
import { TimelineModule } from './modules/timeline/timeline.module';
import { UsersModule } from './modules/users/users.module';
import { PlannerModule } from './modules/planner/planner.module';
import { PrismaModule } from './prisma/prisma.module';
import { MaintenanceMiddleware } from './common/middleware/maintenance.middleware';
import { AdminModule } from './modules/admin/admin.module';
import { ClientHooksModule } from './modules/client-hooks/client-hooks.module';
import { RecordingsModule } from './modules/recordings/recordings.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: validateEnv,
    }),
    LoggerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        pinoHttp: {
          level: config.get<string>('LOG_LEVEL', 'info'),
          autoLogging: true,
          customProps: () => ({
            context: 'HTTP',
          }),
        },
      }),
    }),
    ThrottlerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const ttlSeconds = config.getOrThrow<number>('THROTTLE_TTL');
        const limit = config.getOrThrow<number>('THROTTLE_LIMIT');
        return {
          throttlers: [
            {
              ttl: ttlSeconds * 1000,
              limit,
            },
          ],
        };
      },
    }),
    PrismaModule,
    HealthModule,
    AuthModule,
    UsersModule,
    TasksModule,
    NotesModule,
    FocusSessionsModule,
    TimelineModule,
    AnalyticsModule,
    AiModule,
    PlannerModule,
    AdminModule,
    ClientHooksModule,
    RecordingsModule,
  ],
  providers: [
    {
      provide: APP_PIPE,
      useFactory: () =>
        new ValidationPipe({
          whitelist: true,
          forbidNonWhitelisted: true,
          transform: true,
          transformOptions: { enableImplicitConversion: true },
          errorHttpStatusCode: HttpStatus.UNPROCESSABLE_ENTITY,
        }),
    },
    { provide: APP_FILTER, useClass: HttpExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: RequestIdInterceptor },
    /** Throttle before JWT so limits apply even when auth fails (e.g. missing token). */
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    MaintenanceMiddleware,
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(MaintenanceMiddleware).forRoutes('*');
  }
}
