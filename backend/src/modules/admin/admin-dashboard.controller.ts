import {
  Controller,
  DefaultValuePipe,
  Get,
  Query,
  Sse,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import type { MessageEvent } from '@nestjs/common';
import type { Observable } from 'rxjs';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import { AdminDashboardService } from './admin-dashboard.service';

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/dashboard', version: VERSION_NEUTRAL })
export class AdminDashboardController {
  constructor(private readonly dash: AdminDashboardService) {}

  @Get('stats')
  stats() {
    return this.dash.stats();
  }

  @Get('charts')
  charts(@Query('range', new DefaultValuePipe('30d')) range: string) {
    const m = /^(\d+)d$/.exec(range.trim());
    const days = m ? Math.min(90, Math.max(1, parseInt(m[1], 10))) : 30;
    return this.dash.charts(days);
  }

  @Get('alerts')
  alerts() {
    return this.dash.alerts();
  }

  @Get('live-feed/poll')
  liveFeedPoll() {
    return this.dash.recentEvents(40);
  }

  @Sse('live-feed')
  liveFeed(): Observable<MessageEvent> {
    return this.dash.liveFeed$();
  }
}
