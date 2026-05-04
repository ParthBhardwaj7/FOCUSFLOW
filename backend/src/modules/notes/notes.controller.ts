import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { CreateNoteDto } from './dto/create-note.dto';
import { CreateVoiceNoteDto } from './dto/create-voice-note.dto';
import { PatchNoteDto } from './dto/patch-note.dto';
import { NotesService } from './notes.service';

@Controller({ path: 'notes', version: '1' })
export class NotesController {
  constructor(private readonly notes: NotesService) {}

  @Get()
  list(@CurrentUser() u: JwtUserPayload) {
    return this.notes.list(u.userId);
  }

  @Post('voice')
  @UseInterceptors(
    FileInterceptor('audio', {
      limits: { fileSize: 8 * 1024 * 1024 },
    }),
  )
  createVoice(
    @CurrentUser() u: JwtUserPayload,
    @Body() dto: CreateVoiceNoteDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.notes.createWithVoice(u.userId, dto, file);
  }

  @Post()
  create(@CurrentUser() u: JwtUserPayload, @Body() dto: CreateNoteDto) {
    return this.notes.create(u.userId, dto);
  }

  @Get(':id/audio')
  async streamAudio(@CurrentUser() u: JwtUserPayload, @Param('id') id: string) {
    const { stream, mime } = await this.notes.streamAudio(u.userId, id);
    return new StreamableFile(stream, {
      type: mime,
      disposition: `inline; filename="voice-${id}.m4a"`,
    });
  }

  @Get(':id')
  getOne(@CurrentUser() u: JwtUserPayload, @Param('id') id: string) {
    return this.notes.getOne(u.userId, id);
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
