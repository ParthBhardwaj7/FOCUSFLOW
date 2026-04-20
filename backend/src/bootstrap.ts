import type { INestApplication } from '@nestjs/common';
import { VersioningType } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import helmet from 'helmet';

/**
 * Shared HTTP middleware and API options for `main` and e2e tests.
 */
export function configureApp(app: INestApplication): void {
  const config = app.get(ConfigService);
  const nodeEnv = config.get<string>('NODE_ENV') ?? 'development';
  const corsOrigin =
    nodeEnv === 'production'
      ? config
          .getOrThrow<string>('CORS_ORIGINS')
          .split(',')
          .map((o) => o.trim())
          .filter(Boolean)
      : true;

  app.use(cookieParser());
  app.use(helmet());
  app.use(compression());
  app.enableVersioning({
    type: VersioningType.URI,
    defaultVersion: '1',
  });
  // Production: strict CORS_ORIGINS. Development: reflect / allow (Dio/mobile often omits Origin).
  app.enableCors({
    origin: corsOrigin,
    credentials: true,
  });
}
