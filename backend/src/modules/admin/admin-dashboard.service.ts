import { Injectable } from '@nestjs/common';
import { Prisma, UserRole } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { interval, map, type Observable } from 'rxjs';
import type { MessageEvent } from '@nestjs/common';

@Injectable()
export class AdminDashboardService {
  constructor(private readonly prisma: PrismaService) {}

  async stats() {
    const todayStart = new Date();
    todayStart.setUTCHours(0, 0, 0, 0);
    const [totalUsers, appUsers, activeToday, tasksCreated, tasksCompleted] =
      await Promise.all([
        this.prisma.user.count({ where: { isBanned: false } }),
        this.prisma.user.count({
          where: { isBanned: false, role: UserRole.USER },
        }),
        this.prisma.user.count({
          where: {
            isBanned: false,
            lastActiveAt: { gte: todayStart },
          },
        }),
        this.prisma.task.count({
          where: { createdAt: { gte: todayStart } },
        }),
        this.prisma.task.count({
          where: { completedAt: { gte: todayStart } },
        }),
      ]);
    const plannedWeek = await this.prisma.task.count({
      where: {
        archivedAt: null,
        scheduledOn: {
          gte: new Date(Date.now() - 7 * 86_400_000),
        },
      },
    });
    const completedWeek = await this.prisma.task.count({
      where: {
        archivedAt: null,
        scheduledOn: {
          gte: new Date(Date.now() - 7 * 86_400_000),
        },
        completedAt: { not: null },
      },
    });
    const avgCompletion =
      plannedWeek === 0
        ? 0
        : Math.round((completedWeek / plannedWeek) * 1000) / 10;
    return {
      totalUsers,
      appUsers,
      activeToday,
      tasksCreated,
      tasksCompleted,
      avgCompletionPercent7d: avgCompletion,
    };
  }

  async charts(rangeDays: number) {
    const days = Math.min(Math.max(rangeDays, 1), 90);
    const dau: { date: string; count: number }[] = [];
    const tasksByDay: { date: string; created: number; completed: number }[] =
      [];
    const aiByDay: { date: string; messages: number }[] = [];
    for (let i = days - 1; i >= 0; i--) {
      const day = new Date();
      day.setUTCDate(day.getUTCDate() - i);
      day.setUTCHours(0, 0, 0, 0);
      const next = new Date(day);
      next.setUTCDate(next.getUTCDate() + 1);
      const dateStr = day.toISOString().slice(0, 10);
      const [u, tc, td, ai] = await Promise.all([
        this.prisma.user.count({
          where: {
            isBanned: false,
            lastActiveAt: { gte: day, lt: next },
          },
        }),
        this.prisma.task.count({
          where: { createdAt: { gte: day, lt: next } },
        }),
        this.prisma.task.count({
          where: { completedAt: { gte: day, lt: next } },
        }),
        this.prisma.aiCoachLog.count({
          where: { createdAt: { gte: day, lt: next } },
        }),
      ]);
      dau.push({ date: dateStr, count: u });
      tasksByDay.push({ date: dateStr, created: tc, completed: td });
      aiByDay.push({ date: dateStr, messages: ai });
    }
    const tagRows = await this.prisma.$queryRaw<
      { tag: string | null; c: bigint }[]
    >(Prisma.sql`
      SELECT ts.tag, COUNT(*)::bigint AS c
      FROM "TimelineSlot" ts
      WHERE ts.tag IS NOT NULL AND ts.tag <> ''
      GROUP BY ts.tag
      ORDER BY c DESC
      LIMIT 12
    `);
    const categoryDistribution = tagRows.map((r) => ({
      name: r.tag ?? 'unknown',
      value: Number(r.c),
    }));
    return { dau, tasksByDay, aiByDay, categoryDistribution };
  }

  async alerts() {
    const hourAgo = new Date(Date.now() - 3600 * 1000);
    const dayAgo = new Date(Date.now() - 86_400_000);
    const [unresolvedErrors, banned24h, flagsChangedToday, errorsLastHour] =
      await Promise.all([
        this.prisma.errorLog.count({
          where: { status: 'UNRESOLVED' },
        }),
        this.prisma.user.count({
          where: {
            isBanned: true,
            updatedAt: { gte: dayAgo },
          },
        }),
        this.prisma.featureFlag.count({
          where: { updatedAt: { gte: dayAgo } },
        }),
        this.prisma.errorLog.count({
          where: { createdAt: { gte: hourAgo } },
        }),
      ]);
    return {
      unresolvedErrors,
      usersBanned24h: banned24h,
      featureFlagsChangedToday: flagsChangedToday,
      errorsLastHour,
    };
  }

  liveFeed$(): Observable<MessageEvent> {
    return interval(3000).pipe(
      map(
        (): MessageEvent => ({
          data: JSON.stringify({ t: Date.now(), type: 'ping' }),
        }),
      ),
    );
  }

  async recentEvents(limit = 30) {
    const [audits, errors, signups] = await Promise.all([
      this.prisma.auditLog.findMany({
        orderBy: { createdAt: 'desc' },
        take: limit,
        include: { admin: { select: { email: true } } },
      }),
      this.prisma.errorLog.findMany({
        orderBy: { createdAt: 'desc' },
        take: Math.floor(limit / 2),
      }),
      this.prisma.user.findMany({
        where: { role: UserRole.USER },
        orderBy: { createdAt: 'desc' },
        take: Math.floor(limit / 3),
        select: { id: true, email: true, createdAt: true },
      }),
    ]);
    return { audits, errors, signups };
  }
}
