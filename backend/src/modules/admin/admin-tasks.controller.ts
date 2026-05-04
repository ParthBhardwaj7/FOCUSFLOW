import {
  Controller,
  DefaultValuePipe,
  Get,
  ParseIntPipe,
  Query,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import { AdminTasksService } from './admin-tasks.service';

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/tasks', version: VERSION_NEUTRAL })
export class AdminTasksController {
  constructor(private readonly tasks: AdminTasksService) {}

  @Get('analytics')
  analytics() {
    return this.tasks.analyticsOverview();
  }

  @Get('heatmap')
  heatmap() {
    return this.tasks.heatmap();
  }

  @Get('insights')
  insights() {
    return this.tasks.insights();
  }

  @Get()
  list(
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('limit', new DefaultValuePipe(50), ParseIntPipe) limit: number,
    @Query('userId') userId?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    return this.tasks.list({
      page,
      limit: Math.min(limit, 200),
      userId,
      from: from ? new Date(from) : undefined,
      to: to ? new Date(to) : undefined,
    });
  }
}
