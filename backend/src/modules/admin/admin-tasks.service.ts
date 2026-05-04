import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class AdminTasksService {
  constructor(private readonly prisma: PrismaService) {}

  async analyticsOverview() {
    const [totalTasks, completed, skippedSessions] = await Promise.all([
      this.prisma.task.count({ where: { archivedAt: null } }),
      this.prisma.task.count({
        where: { archivedAt: null, completedAt: { not: null } },
      }),
      this.prisma.focusSession.count({
        where: { outcome: 'SKIPPED' },
      }),
    ]);
    const rate =
      totalTasks === 0 ? 0 : Math.round((completed / totalTasks) * 1000) / 10;
    const tagSkip = await this.prisma.$queryRaw<
      { tag: string | null; c: bigint }[]
    >(Prisma.sql`
      SELECT ts.tag, COUNT(*)::bigint AS c
      FROM "TimelineSlot" ts
      WHERE ts.status = 'SKIPPED' AND ts.tag IS NOT NULL AND ts.tag <> ''
      GROUP BY ts.tag
      ORDER BY c DESC
      LIMIT 1
    `);
    const peakHour = await this.prisma.$queryRaw<{ h: number; c: bigint }[]>(
      Prisma.sql`
        SELECT EXTRACT(HOUR FROM "createdAt")::int AS h, COUNT(*)::bigint AS c
        FROM "Task"
        GROUP BY 1
        ORDER BY c DESC
        LIMIT 1
      `,
    );
    return {
      totalTasks,
      completionRatePercent: rate,
      mostSkippedCategoryTag: tagSkip[0]?.tag ?? null,
      peakTaskCreationHour: peakHour[0] ? Number(peakHour[0].h) : null,
      skippedSessions,
    };
  }

  async heatmap() {
    const rows = await this.prisma.$queryRaw<
      { dow: number; hour: number; c: bigint }[]
    >(Prisma.sql`
      SELECT
        EXTRACT(DOW FROM "createdAt")::int AS dow,
        EXTRACT(HOUR FROM "createdAt")::int AS hour,
        COUNT(*)::bigint AS c
      FROM "Task"
      GROUP BY 1, 2
    `);
    return rows.map((r) => ({
      dayOfWeek: r.dow,
      hour: r.hour,
      count: Number(r.c),
    }));
  }

  async list(params: {
    page: number;
    limit: number;
    status?: string;
    userId?: string;
    from?: Date;
    to?: Date;
  }) {
    const { page, limit, userId, from, to } = params;
    const skip = (page - 1) * limit;
    const where: Prisma.TaskWhereInput = {
      archivedAt: null,
    };
    if (userId) where.userId = userId;
    if (from || to) {
      where.createdAt = {};
      if (from) where.createdAt.gte = from;
      if (to) where.createdAt.lte = to;
    }
    const [total, items] = await Promise.all([
      this.prisma.task.count({ where }),
      this.prisma.task.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        include: {
          user: { select: { email: true, id: true } },
        },
      }),
    ]);
    return { total, page, limit, items };
  }

  async completionByTag() {
    const rows = await this.prisma.$queryRaw<
      { tag: string; planned: bigint; done: bigint }[]
    >(Prisma.sql`
      SELECT ts.tag,
        COUNT(*)::bigint AS planned,
        COUNT(*) FILTER (WHERE ts.status = 'DONE')::bigint AS done
      FROM "TimelineSlot" ts
      WHERE ts.tag IS NOT NULL AND ts.tag <> ''
      GROUP BY ts.tag
      ORDER BY planned DESC
      LIMIT 20
    `);
    return rows.map((r) => ({
      tag: r.tag,
      planned: Number(r.planned),
      done: Number(r.done),
      ratePercent:
        Number(r.planned) === 0
          ? 0
          : Math.round((Number(r.done) / Number(r.planned)) * 1000) / 10,
    }));
  }

  async soundUsage() {
    const rows = await this.prisma.$queryRaw<
      { label: string | null; c: bigint }[]
    >(Prisma.sql`
      SELECT "soundLabel" AS label, COUNT(*)::bigint AS c
      FROM "TimelineSlot"
      WHERE "soundLabel" IS NOT NULL AND "soundLabel" <> ''
      GROUP BY "soundLabel"
      ORDER BY c DESC
      LIMIT 20
    `);
    return rows.map((r) => ({
      soundLabel: r.label ?? 'unknown',
      count: Number(r.c),
    }));
  }

  async insights() {
    const byTag = await this.completionByTag();
    if (byTag.length === 0) {
      return {
        lines: [
          'No tagged timeline blocks yet. Insights compare completion rates across categories once users plan with tags.',
        ],
        byTag,
      };
    }
    if (byTag.length < 2) {
      return {
        lines: [
          `Only one tag category (${byTag[0].tag}) has data so far. Add more tagged blocks to compare categories.`,
        ],
        byTag,
      };
    }
    const sorted = [...byTag].sort((a, b) => b.ratePercent - a.ratePercent);
    const best = sorted[0];
    const worst = sorted[sorted.length - 1];
    const lines = [
      `Users complete about ${best.ratePercent}% of ${best.tag} blocks vs ${worst.ratePercent}% for ${worst.tag}.`,
    ];
    return { lines, byTag };
  }
}
