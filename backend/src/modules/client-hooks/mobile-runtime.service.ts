import { Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { UserPlan } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class MobileRuntimeService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Redacts obvious secrets / tokens for storage in ErrorLog while keeping
   * enough detail for engineers (paths, status codes, exception types).
   */
  redactForErrorStorage(raw: string, extraKeywords?: string[]): string {
    let m = raw.replace(/\r\n/g, '\n');
    m = m.replace(/Bearer\s+[\w-]+\.[\w-]+\.[\w-]+/gi, 'Bearer [REDACTED_JWT]');
    m = m.replace(/\beyJ[\w-]+\.[\w-]+\.[\w-]+\b/g, '[REDACTED_JWT]');
    m = m.replace(/\b(sk|pk)_(live|test)_[\w]+\b/gi, '[REDACTED_TOKEN]');
    const keys = [...(extraKeywords ?? [])];
    for (const k of keys) {
      if (k.trim() && m.toUpperCase().includes(k.toUpperCase())) {
        m = m.replace(
          new RegExp(k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'),
          '[REDACTED]',
        );
      }
    }
    if (m.length > 8000) m = `${m.slice(0, 8000)}…`;
    return m;
  }

  /** @deprecated Prefer [redactForErrorStorage] — kept for tests / callers. */
  scrubErrorMessage(raw: string, extraKeywords?: string[]): string {
    return this.redactForErrorStorage(raw, extraKeywords);
  }

  fingerprintForClient(
    errorType: string,
    message: string,
    screen?: string,
  ): string {
    const normalized = `${errorType}|${screen ?? ''}|${message.slice(0, 400)}`;
    return createHash('sha256').update(normalized, 'utf8').digest('hex');
  }

  async publicConfig() {
    return this.prisma.appConfig.findMany({
      where: { isPublic: true },
      select: { key: true, value: true, updatedAt: true },
    });
  }

  async evaluateFlags(userId: string) {
    const rows = await this.prisma.featureFlag.findMany();
    const out: Record<string, boolean> = {};
    for (const f of rows) {
      if (f.enabledForUserIds.includes(userId)) {
        out[f.key] = true;
        continue;
      }
      if (!f.isEnabled) {
        out[f.key] = false;
        continue;
      }
      if (f.rolloutPercentage >= 100) {
        out[f.key] = true;
        continue;
      }
      if (f.rolloutPercentage <= 0) {
        out[f.key] = false;
        continue;
      }
      const bucket = this.rolloutBucket(userId, f.key);
      out[f.key] = bucket < f.rolloutPercentage;
    }
    return out;
  }

  private rolloutBucket(userId: string, key: string): number {
    const h = createHash('sha256').update(`${userId}:${key}`, 'utf8').digest();
    return h[0] % 100;
  }

  async matchingAiSuggestions(userId: string) {
    const rows = await this.prisma.aiSuggestion.findMany({
      where: { isActive: true },
    });
    const stats = await this.userStatsForSuggestions(userId);
    return rows.filter((r) => this.matchesCondition(r.targetCondition, stats));
  }

  private async userStatsForSuggestions(userId: string) {
    const sinceDay = new Date();
    sinceDay.setUTCHours(0, 0, 0, 0);
    const weekAgo = new Date(Date.now() - 7 * 86_400_000);
    const weekStart = new Date(Date.now() - 7 * 86_400_000);
    const [tasksToday, skippedWeek, user, plannedWeek, completedWeek] =
      await Promise.all([
      this.prisma.task.count({
        where: { userId, createdAt: { gte: sinceDay } },
      }),
      this.prisma.timelineSlot.count({
        where: {
          userId,
          status: 'SKIPPED',
          updatedAt: { gte: weekAgo },
        },
      }),
      this.prisma.user.findUnique({
        where: { id: userId },
        select: { createdAt: true, plan: true },
      }),
      this.prisma.task.count({
        where: {
          userId,
          archivedAt: null,
          scheduledOn: {
            gte: weekStart,
          },
        },
      }),
      this.prisma.task.count({
        where: {
          userId,
          archivedAt: null,
          completedAt: { not: null },
          scheduledOn: {
            gte: weekStart,
          },
        },
      }),
    ]);
    const completionRate = plannedWeek === 0 ? 1 : completedWeek / plannedWeek;
    const firstWeek =
      user && Date.now() - user.createdAt.getTime() < 7 * 86_400_000;
    return {
      completionRate,
      tasksToday,
      skippedWeek,
      firstWeek,
      plan: user?.plan ?? UserPlan.FREE,
    };
  }

  private matchesCondition(condition: string, s: Record<string, unknown>) {
    const c = condition.trim();
    if (c === 'completion_rate_lt_40')
      return (s.completionRate as number) < 0.4;
    if (c === 'completion_rate_lt_40_pct')
      return (s.completionRate as number) < 0.4;
    if (c === 'no_tasks_today') return (s.tasksToday as number) === 0;
    if (c === 'skipped_3_plus_week') return (s.skippedWeek as number) >= 3;
    if (c === 'first_week_user') return Boolean(s.firstWeek);
    if (c.startsWith('custom:')) return false;
    return false;
  }
}
