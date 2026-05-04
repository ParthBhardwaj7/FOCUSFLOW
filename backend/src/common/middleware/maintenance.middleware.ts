import {
  Injectable,
  NestMiddleware,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class MaintenanceMiddleware implements NestMiddleware {
  /** Coalesce concurrent DB reads; do not cache the boolean (ops toggles must apply immediately). */
  private inFlightMode: Promise<boolean> | null = null;

  constructor(private readonly prisma: PrismaService) {}

  async use(req: Request, _res: Response, next: NextFunction) {
    if (!req.path.startsWith('/v1')) {
      next();
      return;
    }
    if (
      req.path.startsWith('/v1/auth') ||
      req.path === '/v1/config/public' ||
      req.path.startsWith('/v1/health') ||
      req.path === '/v1/ready' ||
      req.path === '/v1/errors/report' ||
      req.path === '/v1/notifications/register'
    ) {
      next();
      return;
    }
    if (await this.isMaintenanceMode()) {
      throw new ServiceUnavailableException(
        'FocusFlow is temporarily unavailable for maintenance.',
      );
    }
    next();
  }

  private async isMaintenanceMode(): Promise<boolean> {
    this.inFlightMode ??= this.prisma.appConfig
      .findUnique({
        where: { key: 'maintenance_mode' },
        select: { value: true },
      })
      .then((row) => row?.value === 'true')
      .finally(() => {
        this.inFlightMode = null;
      });
    return await this.inFlightMode;
  }
}
