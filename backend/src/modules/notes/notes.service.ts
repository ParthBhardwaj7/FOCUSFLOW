import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createReadStream, existsSync } from 'fs';
import { mkdir, writeFile } from 'fs/promises';
import { join } from 'path';
import { PrismaService } from '../../prisma/prisma.service';
import type { CreateNoteDto } from './dto/create-note.dto';
import type { CreateVoiceNoteDto } from './dto/create-voice-note.dto';
import type { PatchNoteDto } from './dto/patch-note.dto';

@Injectable()
export class NotesService {
  constructor(private readonly prisma: PrismaService) {}

  list(userId: string) {
    return this.prisma.note.findMany({
      where: { userId, deletedAt: null },
      orderBy: [{ pinned: 'desc' }, { updatedAt: 'desc' }],
    });
  }

  async getOne(userId: string, noteId: string) {
    const n = await this.prisma.note.findUnique({ where: { id: noteId } });
    if (!n || n.deletedAt) throw new NotFoundException('Note not found');
    if (n.userId !== userId) throw new ForbiddenException();
    return n;
  }

  create(userId: string, dto: CreateNoteDto) {
    return this.prisma.note.create({
      data: {
        userId,
        title: dto.title ?? '',
        body: dto.body ?? '',
        tags: dto.tags ?? '',
        pinned: dto.pinned ?? false,
      },
    });
  }

  /**
   * Creates a voice note with uploaded audio stored under `uploads/inbox-voice/{userId}/{noteId}.m4a`.
   */
  async createWithVoice(
    userId: string,
    dto: CreateVoiceNoteDto,
    file: Express.Multer.File | undefined,
  ) {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Audio file is required');
    }
    const title = (dto.title ?? '').trim() || 'Voice note';
    const transcript = (dto.transcript ?? '').trim();
    let tags = (dto.tags ?? '').trim();
    if (
      !tags
        .split(',')
        .map((t) => t.trim())
        .includes('Voice')
    ) {
      tags = tags.length ? `${tags},Voice` : 'Voice';
    }

    const note = await this.prisma.note.create({
      data: {
        userId,
        title,
        body: transcript,
        tags,
        pinned: false,
      },
    });

    const dir = join(process.cwd(), 'uploads', 'inbox-voice', userId);
    await mkdir(dir, { recursive: true });
    const ext = file.mimetype?.includes('mpeg') ? 'mp3' : 'm4a';
    const rel = join('uploads', 'inbox-voice', userId, `${note.id}.${ext}`);
    const abs = join(process.cwd(), rel);
    await writeFile(abs, file.buffer);

    return this.prisma.note.update({
      where: { id: note.id },
      data: { audioKey: rel },
    });
  }

  async streamAudio(userId: string, noteId: string) {
    const n = await this.prisma.note.findUnique({ where: { id: noteId } });
    if (!n || n.deletedAt) throw new NotFoundException('Note not found');
    if (n.userId !== userId) throw new ForbiddenException();
    if (!n.audioKey?.length)
      throw new NotFoundException('No audio for this note');

    const abs = join(process.cwd(), n.audioKey);
    if (!existsSync(abs)) throw new NotFoundException('Audio file missing');

    const stream = createReadStream(abs);
    return { stream, mime: 'audio/mp4' };
  }

  async update(userId: string, noteId: string, dto: PatchNoteDto) {
    const existing = await this.prisma.note.findUnique({
      where: { id: noteId },
    });
    if (!existing || existing.deletedAt) {
      throw new NotFoundException('Note not found');
    }
    if (existing.userId !== userId) throw new ForbiddenException();

    if (dto.expectedUpdatedAt !== undefined) {
      const expected = new Date(dto.expectedUpdatedAt);
      if (Number.isNaN(expected.getTime())) {
        throw new ConflictException('Invalid expectedUpdatedAt');
      }
      const driftMs = Math.abs(
        existing.updatedAt.getTime() - expected.getTime(),
      );
      if (driftMs > 1500) {
        throw new ConflictException('Note was modified elsewhere');
      }
    }

    return this.prisma.note.update({
      where: { id: noteId },
      data: {
        ...(dto.title !== undefined ? { title: dto.title } : {}),
        ...(dto.body !== undefined ? { body: dto.body } : {}),
        ...(dto.tags !== undefined ? { tags: dto.tags } : {}),
        ...(dto.pinned !== undefined ? { pinned: dto.pinned } : {}),
      },
    });
  }

  async softDelete(userId: string, noteId: string) {
    const existing = await this.prisma.note.findUnique({
      where: { id: noteId },
    });
    if (!existing || existing.deletedAt) {
      throw new NotFoundException('Note not found');
    }
    if (existing.userId !== userId) throw new ForbiddenException();
    await this.prisma.note.update({
      where: { id: noteId },
      data: { deletedAt: new Date() },
    });
    return { ok: true };
  }
}
