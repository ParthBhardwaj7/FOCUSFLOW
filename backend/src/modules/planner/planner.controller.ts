import { Body, Controller, Get, Param, Put, Query } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { UpsertPlannerDayDto } from './dto/upsert-planner-day.dto';
import { PlannerService } from './planner.service';

@Controller({ path: 'planner/snapshots', version: '1' })
export class PlannerController {
  constructor(private readonly planner: PlannerService) {}

  @Get('meta')
  meta(@CurrentUser() u: JwtUserPayload) {
    return this.planner.listMeta(u.userId);
  }

  @Get('range')
  range(
    @CurrentUser() u: JwtUserPayload,
    @Query('from') from: string,
    @Query('to') to: string,
  ) {
    return this.planner.bulkInRange(u.userId, from, to);
  }

  @Get('day/:on')
  day(@CurrentUser() u: JwtUserPayload, @Param('on') on: string) {
    return this.planner.getDay(u.userId, on);
  }

  @Put('day/:on')
  putDay(
    @CurrentUser() u: JwtUserPayload,
    @Param('on') on: string,
    @Body() dto: UpsertPlannerDayDto,
  ) {
    return this.planner.upsertDay(u.userId, on, dto.slots);
  }
}
