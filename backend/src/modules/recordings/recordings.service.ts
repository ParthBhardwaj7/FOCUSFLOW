import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createReadStream, existsSync } from 'fs';
import { mkdir, writeFile } from 'fs/promises';
import { join } from 'path';
import { randomUUID } from 'crypto';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class RecordingsService {
  constructor(private readonly config: ConfigService) {}

  private safeId(raw: string | undefined): string {
    if (!raw || !/^[a-zA-Z0-9_-]{8,128}$/.test(raw)) {
      return randomUUID();
    }
    return raw;
  }

  async saveUpload(
    userId: string,
    id: string | undefined,
    file: Express.Multer.File,
  ) {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Audio file is required');
    }
    const rid = this.safeId(id);
    const dir = join(process.cwd(), 'uploads', 'user-recordings', userId);
    await mkdir(dir, { recursive: true });
    const rel = join('uploads', 'user-recordings', userId, `${rid}.m4a`);
    const abs = join(process.cwd(), rel);
    await writeFile(abs, file.buffer);

    const base =
      this.config
        .get<string>('SOUND_PUBLIC_BASE_URL', { infer: true })
        ?.trim() || '';
    const path = `/v1/recordings/stream/${encodeURIComponent(userId)}/${encodeURIComponent(rid)}`;
    if (base) {
      return { url: `${base.replace(/\/+$/, '')}${path}` };
    }
    return { url: path };
  }

  streamFile(userId: string, recordingId: string) {
    const uid = decodeURIComponent(userId);
    const rid = decodeURIComponent(recordingId);
    const rel = join('uploads', 'user-recordings', uid, `${rid}.m4a`);
    const abs = join(process.cwd(), rel);
    if (!existsSync(abs)) {
      throw new NotFoundException('Recording not found');
    }
    const stream = createReadStream(abs);
    return { stream, mime: 'audio/mp4' as const };
  }
}
