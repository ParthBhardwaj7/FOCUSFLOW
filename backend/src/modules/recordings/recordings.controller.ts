import {
  BadRequestException,
  Controller,
  ForbiddenException,
  Get,
  Param,
  Post,
  Query,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { RecordingsService } from './recordings.service';

@Controller({ path: 'recordings', version: '1' })
export class RecordingsController {
  constructor(private readonly recordings: RecordingsService) {}

  @Post('upload')
  @UseInterceptors(
    FileInterceptor('audio', {
      limits: { fileSize: 20 * 1024 * 1024 },
    }),
  )
  upload(
    @CurrentUser() u: JwtUserPayload,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Query('id') id?: string,
  ) {
    if (!file) {
      throw new BadRequestException('Audio file is required');
    }
    return this.recordings.saveUpload(u.userId, id, file);
  }

  @Get('stream/:userId/:recordingId')
  stream(
    @CurrentUser() u: JwtUserPayload,
    @Param('userId') userId: string,
    @Param('recordingId') recordingId: string,
  ) {
    if (userId !== u.userId) {
      throw new ForbiddenException();
    }
    const { stream, mime } = this.recordings.streamFile(userId, recordingId);
    return new StreamableFile(stream, {
      type: mime,
      disposition: `inline; filename="recording-${recordingId}.m4a"`,
    });
  }
}
