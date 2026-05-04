import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { parseYmdUtcStart } from '../../common/utils/ymd';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PlannerService {
  constructor(private readonly prisma: PrismaService) {}

  listMeta(userId: string) {
    return this.prisma.plannerDaySnapshot.findMany({
      where: { userId },
      select: {
        dayOn: true,
        updatedAt: true,
      },
      orderBy: { dayOn: 'asc' },
    });
  }

  async bulkInRange(userId: string, fromOn: string, toOn: string) {
    const start = parseYmdUtcStart(fromOn);
    const end = parseYmdUtcStart(toOn);
    if (start > end) {
      throw new BadRequestException('from must be on or before to');
    }
    const rows = await this.prisma.plannerDaySnapshot.findMany({
      where: {
        userId,
        dayOn: { gte: start, lte: end },
      },
      select: {
        dayOn: true,
        slots: true,
        updatedAt: true,
      },
      orderBy: { dayOn: 'asc' },
    });
    const days: Record<string, { updatedAt: string; slots: Prisma.JsonValue }> =
      {};
    for (const r of rows) {
      const key = r.dayOn.toISOString().slice(0, 10);
      days[key] = {
        updatedAt: r.updatedAt.toISOString(),
        slots: r.slots,
      };
    }
    return { days };
  }

  async getDay(userId: string, on: string) {
    const dayOn = parseYmdUtcStart(on);
    const row = await this.prisma.plannerDaySnapshot.findUnique({
      where: { userId_dayOn: { userId, dayOn } },
      select: { dayOn: true, slots: true, updatedAt: true },
    });
    if (!row) throw new NotFoundException('No planner snapshot for this day');
    return {
      dayOn: row.dayOn.toISOString().slice(0, 10),
      updatedAt: row.updatedAt.toISOString(),
      slots: row.slots,
    };
  }

  async upsertDay(userId: string, on: string, slots: unknown[]) {
    const dayOn = parseYmdUtcStart(on);
    return this.prisma.plannerDaySnapshot.upsert({
      where: { userId_dayOn: { userId, dayOn } },
      create: {
        userId,
        dayOn,
        slots: slots as Prisma.InputJsonValue,
      },
      update: {
        slots: slots as Prisma.InputJsonValue,
      },
      select: {
        dayOn: true,
        updatedAt: true,
      },
    });
  }
}
