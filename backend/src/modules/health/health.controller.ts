import { Controller, Get } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { Public } from '../../common/decorators/public.decorator';
import { HealthService } from './health.service';

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
