import { Controller, Get, VERSION_NEUTRAL } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { Public } from '../../common/decorators/public.decorator';
import { HealthService } from './health.service';

/**
 * Unversioned summary for load balancers and the admin “System health” page.
 * (Versioned liveness remains at GET /v1/health.)
 */
@Public()
@SkipThrottle()
@Controller({ path: 'health', version: VERSION_NEUTRAL })
export class HealthSummaryController {
  constructor(private readonly health: HealthService) {}

  @Get()
  async summary(): Promise<{
    status: 'ok' | 'degraded';
    service: string;
    time: string;
    checks: { process: string; database: 'up' | 'down' };
  }> {
    let database: 'up' | 'down' = 'down';
    try {
      const r = await this.health.getReadiness();
      database = r.status === 'ok' && r.database === 'up' ? 'up' : 'down';
    } catch {
      database = 'down';
    }
    return {
      status: database === 'up' ? 'ok' : 'degraded',
      service: 'focusflow-api',
      time: new Date().toISOString(),
      checks: { process: 'up', database },
    };
  }
}

@Public()
@SkipThrottle()
@Controller({ path: 'health', version: '1' })
export class HealthController {
  constructor(private readonly health: HealthService) {}

  /** Liveness: process is up (no external checks). */
  @Get()
  live() {
    return this.health.getLiveness();
  }
}

@Public()
@SkipThrottle()
@Controller({ path: 'ready', version: '1' })
export class ReadyController {
  constructor(private readonly health: HealthService) {}

  /** Readiness: database is reachable. */
  @Get()
  async ready() {
    return this.health.getReadiness();
  }
}
