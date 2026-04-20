import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { BadRequestException } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { CreateTimelineSlotDto } from './dto/create-timeline-slot.dto';
import { UpdateTimelineSlotDto } from './dto/update-timeline-slot.dto';
import { TimelineService } from './timeline.service';

@Controller({ path: 'timeline', version: '1' })
export class TimelineController {
  constructor(private readonly timeline: TimelineService) {}

  @Get()
  list(@CurrentUser() u: JwtUserPayload, @Query('on') on?: string) {
    if (!on) {
      throw new BadRequestException('Query ?on=YYYY-MM-DD is required');
    }
    return this.timeline.listForDay(u.userId, on);
  }

  @Post()
  create(@CurrentUser() u: JwtUserPayload, @Body() dto: CreateTimelineSlotDto) {
    return this.timeline.create(u.userId, dto);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: JwtUserPayload,
    @Param('id') id: string,
    @Body() dto: UpdateTimelineSlotDto,
  ) {
    return this.timeline.update(u.userId, id, dto);
  }

  @Delete(':id')
  remove(@CurrentUser() u: JwtUserPayload, @Param('id') id: string) {
    return this.timeline.remove(u.userId, id);
  }
}
