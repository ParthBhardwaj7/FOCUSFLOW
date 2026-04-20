import { Body, Controller, Param, Patch, Post } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { CreateFocusSessionDto } from './dto/create-focus-session.dto';
import { PatchFocusSessionDto } from './dto/patch-focus-session.dto';
import { FocusSessionsService } from './focus-sessions.service';

@Controller({ path: 'focus-sessions', version: '1' })
export class FocusSessionsController {
  constructor(private readonly sessions: FocusSessionsService) {}

  @Post()
  create(@CurrentUser() u: JwtUserPayload, @Body() dto: CreateFocusSessionDto) {
    return this.sessions.create(u.userId, dto);
  }

  @Patch(':id')
  patch(
    @CurrentUser() u: JwtUserPayload,
    @Param('id') id: string,
    @Body() dto: PatchFocusSessionDto,
  ) {
    return this.sessions.patch(u.userId, id, dto);
  }
}
