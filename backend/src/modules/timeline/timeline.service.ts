import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { TimelineSlotStatus } from '@prisma/client';
import type { Prisma } from '@prisma/client';
import { parseDayUtcBounds } from '../../common/utils/ymd';
import { PrismaService } from '../../prisma/prisma.service';
import type { CreateTimelineSlotDto } from './dto/create-timeline-slot.dto';
import type { UpdateTimelineSlotDto } from './dto/update-timeline-slot.dto';

@Injectable()
export class TimelineService {
  constructor(private readonly prisma: PrismaService) {}

  listForDay(userId: string, on: string) {
    const { start, end } = parseDayUtcBounds(on);
    return this.prisma.timelineSlot.findMany({
      where: {
        userId,
        startsAt: { gte: start, lt: end },
      },
      orderBy: [{ startsAt: 'asc' }, { sortOrder: 'asc' }],
    });
  }

  async create(userId: string, dto: CreateTimelineSlotDto) {
    const startsAt = new Date(dto.startsAt);
    const endsAt = new Date(dto.endsAt);
    if (!(startsAt < endsAt)) {
      throw new BadRequestException('startsAt must be before endsAt');
    }
    await this.ensureLinkedTask(userId, dto.linkedTaskId);
    return this.prisma.$transaction(async (tx) => {
      const created = await tx.timelineSlot.create({
        data: {
          userId,
          startsAt,
          endsAt,
          title: dto.title,
          iconKey: dto.iconKey,
          tag: dto.tag,
          soundLabel: dto.soundLabel,
          ...(dto.status !== undefined ? { status: dto.status } : {}),
          linkedTaskId: dto.linkedTaskId,
          sortOrder: dto.sortOrder ?? 0,
        },
      });
      if (created.linkedTaskId) {
        await this.syncLinkedTaskCompletion(tx, userId, created.linkedTaskId);
      }
      return created;
    });
  }

  async update(userId: string, id: string, dto: UpdateTimelineSlotDto) {
    const existing = await this.ensureOwner(userId, id);
    const startsAt =
      dto.startsAt !== undefined ? new Date(dto.startsAt) : existing.startsAt;
    const endsAt =
      dto.endsAt !== undefined ? new Date(dto.endsAt) : existing.endsAt;
    if (!(startsAt < endsAt)) {
      throw new BadRequestException('startsAt must be before endsAt');
    }
    const data: Record<string, unknown> = {
      startsAt,
      endsAt,
    };
    if (dto.title !== undefined) data.title = dto.title;
    if (dto.iconKey !== undefined) data.iconKey = dto.iconKey;
    if (dto.tag !== undefined) data.tag = dto.tag;
    if (dto.soundLabel !== undefined) data.soundLabel = dto.soundLabel;
    if (dto.status !== undefined) data.status = dto.status;
    if (dto.sortOrder !== undefined) data.sortOrder = dto.sortOrder;
    if (dto.linkedTaskId !== undefined) {
      await this.ensureLinkedTask(userId, dto.linkedTaskId);
      data.linkedTaskId = dto.linkedTaskId;
    }

    const linkedBefore = existing.linkedTaskId;
    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.timelineSlot.update({
        where: { id },
        data: data as Prisma.TimelineSlotUncheckedUpdateInput,
      });
      const toSync = new Set<string>();
      if (linkedBefore) toSync.add(linkedBefore);
      if (updated.linkedTaskId) toSync.add(updated.linkedTaskId);
      for (const taskId of toSync) {
        await this.syncLinkedTaskCompletion(tx, userId, taskId);
      }
      return updated;
    });
  }

  /** Any DONE slot for this task marks it complete; none DONE clears completion. */
  private async syncLinkedTaskCompletion(
    tx: Prisma.TransactionClient,
    userId: string,
    taskId: string,
  ) {
    const task = await tx.task.findFirst({
      where: { id: taskId, userId },
    });
    if (!task) return;
    const doneCount = await tx.timelineSlot.count({
      where: {
        userId,
        linkedTaskId: taskId,
        status: TimelineSlotStatus.DONE,
      },
    });
    await tx.task.update({
      where: { id: taskId },
      data: {
        completedAt:
          doneCount > 0 ? (task.completedAt ?? new Date()) : null,
      },
    });
  }

  async remove(userId: string, id: string) {
    const slot = await this.ensureOwner(userId, id);
    const linkedTaskId = slot.linkedTaskId;
    await this.prisma.$transaction(async (tx) => {
      await tx.timelineSlot.delete({ where: { id } });
      if (linkedTaskId) {
        await this.syncLinkedTaskCompletion(tx, userId, linkedTaskId);
      }
    });
    return { ok: true };
  }

  private async ensureOwner(userId: string, id: string) {
    const s = await this.prisma.timelineSlot.findUnique({ where: { id } });
    if (!s) throw new NotFoundException('Timeline slot not found');
    if (s.userId !== userId) throw new ForbiddenException();
    return s;
  }

  private async ensureLinkedTask(userId: string, taskId?: string) {
    if (!taskId) return;
    const t = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!t || t.userId !== userId) {
      throw new ForbiddenException('Invalid linkedTaskId');
    }
  }
}
