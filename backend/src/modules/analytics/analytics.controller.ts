import { Controller, Get, Query } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { AnalyticsService } from './analytics.service';

@Controller({ path: 'analytics', version: '1' })
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get('productivity')
  productivity(
    @CurrentUser() u: JwtUserPayload,
    @Query('range') range?: string,
  ) {
    return this.analytics.productivity(u.userId, range);
  }
}
