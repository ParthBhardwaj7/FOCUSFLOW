import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { FocusSessionOutcome, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import type { CreateFocusSessionDto } from './dto/create-focus-session.dto';
import type { PatchFocusSessionDto } from './dto/patch-focus-session.dto';

@Injectable()
export class FocusSessionsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, dto: CreateFocusSessionDto) {
    if (dto.taskId) {
      const t = await this.prisma.task.findUnique({
        where: { id: dto.taskId },
      });
      if (!t || t.userId !== userId) {
        throw new ForbiddenException('Task not found');
      }
    }
    return this.prisma.focusSession.create({
      data: {
        userId,
        taskId: dto.taskId,
        plannedDurationSec: dto.plannedDurationSec,
        subtasksSnapshot:
          dto.subtasksSnapshot === undefined
            ? undefined
            : (dto.subtasksSnapshot as Prisma.InputJsonValue),
      },
    });
  }

  async patch(userId: string, sessionId: string, dto: PatchFocusSessionDto) {
    const row = await this.prisma.focusSession.findUnique({
      where: { id: sessionId },
    });
    if (!row) {
      throw new NotFoundException('Focus session not found');
    }
    if (row.userId !== userId) {
      throw new ForbiddenException();
    }
    if (row.outcome !== 'PENDING') {
      throw new BadRequestException('Session already ended');
    }
    return this.prisma.focusSession.update({
      where: { id: sessionId },
      data: {
        outcome: dto.outcome as FocusSessionOutcome,
        endedAt: new Date(),
      },
    });
  }
}
