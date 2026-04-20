import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import type { CreateNoteDto } from './dto/create-note.dto';
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
        pinned: dto.pinned ?? false,
      },
    });
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
      const driftMs = Math.abs(existing.updatedAt.getTime() - expected.getTime());
      if (driftMs > 1500) {
        throw new ConflictException('Note was modified elsewhere');
      }
    }

    return this.prisma.note.update({
      where: { id: noteId },
      data: {
        ...(dto.title !== undefined ? { title: dto.title } : {}),
        ...(dto.body !== undefined ? { body: dto.body } : {}),
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
