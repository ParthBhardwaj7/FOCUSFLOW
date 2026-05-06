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

    const firstDay = today.minus({ days: range - 1 });
    const dayStart = parseYmdUtcStart(firstDay.toFormat('yyyy-MM-dd'));
    const dayEnd = parseYmdUtcStart(today.plus({ days: 1 }).toFormat('yyyy-MM-dd'));
    const tasks = await this.prisma.task.findMany({
      where: {
        userId,
        archivedAt: null,
        scheduledOn: {
          gte: dayStart,
          lt: dayEnd,
        },
      },
      select: {
        scheduledOn: true,
        completedAt: true,
      },
    });

    const counts = new Map<string, { planned: number; completed: number }>();
    for (const t of tasks) {
      const key = DateTime.fromJSDate(t.scheduledOn, { zone: 'utc' }).toFormat(
        'yyyy-MM-dd',
      );
      const row = counts.get(key) ?? { planned: 0, completed: 0 };
      row.planned += 1;
      if (t.completedAt) row.completed += 1;
      counts.set(key, row);
    }

    const offsets = Array.from({ length: range }, (_, i) => range - 1 - i);
    const dayRows = offsets.map((offset) => {
      const d = today.minus({ days: offset });
      const on = d.toFormat('yyyy-MM-dd');
      const row = counts.get(on) ?? { planned: 0, completed: 0 };
      const rate =
        row.planned === 0
          ? 0
          : Math.round((row.completed / row.planned) * 1000) / 10;
      return { date: on, planned: row.planned, completed: row.completed, rate };
    });

    return { timeZone: zone, range, days: dayRows };
  }

  private parseRange(rangeParam?: string): number {
    const r = rangeParam ?? '7';
    if (r === '7' || r === '14' || r === '30') {
      return Number(r);
    }
    throw new BadRequestException('Query ?range= must be 7, 14, or 30');
  }
}
