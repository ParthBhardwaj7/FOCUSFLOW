import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { CreateNoteDto } from './dto/create-note.dto';
import { PatchNoteDto } from './dto/patch-note.dto';
import { NotesService } from './notes.service';

@Controller({ path: 'notes', version: '1' })
export class NotesController {
  constructor(private readonly notes: NotesService) {}

  @Get()
  list(@CurrentUser() u: JwtUserPayload) {
    return this.notes.list(u.userId);
  }

  @Get(':id')
  getOne(@CurrentUser() u: JwtUserPayload, @Param('id') id: string) {
    return this.notes.getOne(u.userId, id);
  }

  @Post()
  create(@CurrentUser() u: JwtUserPayload, @Body() dto: CreateNoteDto) {
    return this.notes.create(u.userId, dto);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: JwtUserPayload,
    @Param('id') id: string,
    @Body() dto: PatchNoteDto,
  ) {
    return this.notes.update(u.userId, id, dto);
  }

  @Delete(':id')
  remove(@CurrentUser() u: JwtUserPayload, @Param('id') id: string) {
    return this.notes.softDelete(u.userId, id);
  }
}
