import { BadRequestException, Injectable } from '@nestjs/common';
import { DateTime } from 'luxon';
import { parseYmdUtcStart } from '../../common/utils/ymd';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class AnalyticsService {
  constructor(private readonly prisma: PrismaService) {}

  async productivity(userId: string, rangeParam?: string) {
    const range = this.parseRange(rangeParam);
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { timeZone: true },
    });
    const zone =
      user?.timeZone && user.timeZone.trim().length > 0
        ? user.timeZone.trim()
        : 'UTC';

    let today: DateTime;
    try {
      today = DateTime.now().setZone(zone).startOf('day');
    } catch {
      today = DateTime.now().setZone('UTC').startOf('day');
    }

    const days: Array<{
      date: string;
      planned: number;
      completed: number;
      rate: number;
    }> = [];

    for (let offset = range - 1; offset >= 0; offset -= 1) {
      const d = today.minus({ days: offset });
      const on = d.toFormat('yyyy-MM-dd');
      const dayDate = parseYmdUtcStart(on);
      const [planned, completed] = await Promise.all([
        this.prisma.task.count({
          where: {
            userId,
            scheduledOn: dayDate,
            archivedAt: null,
          },
        }),
        this.prisma.task.count({
          where: {
            userId,
            scheduledOn: dayDate,
            archivedAt: null,
            completedAt: { not: null },
          },
        }),
      ]);
      const rate =
        planned === 0
          ? 0
          : Math.round((completed / planned) * 1000) / 10;
      days.push({ date: on, planned, completed, rate });
    }

    return { timeZone: zone, range, days };
  }

  private parseRange(rangeParam?: string): number {
    const r = rangeParam ?? '7';
    if (r === '7' || r === '14' || r === '30') {
      return Number(r);
    }
    throw new BadRequestException('Query ?range= must be 7, 14, or 30');
  }
}
