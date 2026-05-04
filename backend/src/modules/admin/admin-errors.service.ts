import { Injectable, NotFoundException } from '@nestjs/common';
import { ErrorResolutionStatus, type Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';
import { assertSlackIncomingWebhookUrl } from '../../common/utils/slack-webhook-url';

@Injectable()
export class AdminErrorsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
  ) {}

  async list(params: {
    page: number;
    limit: number;
    screen?: string;
    errorType?: string;
    status?: ErrorResolutionStatus;
    from?: Date;
    to?: Date;
    appVersion?: string;
    deviceOs?: string;
  }) {
    const {
      page,
      limit,
      screen,
      errorType,
      status,
      from,
      to,
      appVersion,
      deviceOs,
    } = params;
    const skip = (page - 1) * limit;
    const where: Prisma.ErrorLogWhereInput = {};
    if (screen) where.screen = screen;
    if (errorType) where.errorType = errorType;
    if (status) where.status = status;
    if (appVersion) where.appVersion = appVersion;
    if (deviceOs) where.deviceOs = deviceOs;
    if (from || to) {
      where.createdAt = {};
      if (from) where.createdAt.gte = from;
      if (to) where.createdAt.lte = to;
    }
    const [total, items] = await Promise.all([
      this.prisma.errorLog.count({ where }),
      this.prisma.errorLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
    ]);
    return { total, page, limit, items };
  }

  async grouped(sinceHours = 24) {
    const since = new Date(Date.now() - sinceHours * 3600 * 1000);
    const rows = await this.prisma.errorLog.groupBy({
      by: ['fingerprint'],
      where: { createdAt: { gte: since } },
      _count: { id: true },
    });
    const enriched = await Promise.all(
      rows.map(async (r) => {
        const sample = await this.prisma.errorLog.findFirst({
          where: { fingerprint: r.fingerprint },
          orderBy: { createdAt: 'desc' },
        });
        const users = await this.prisma.errorLog.findMany({
          where: { fingerprint: r.fingerprint, createdAt: { gte: since } },
          select: { userId: true },
          distinct: ['userId'],
        });
        return {
          fingerprint: r.fingerprint,
          count: r._count.id,
          sample,
          distinctUserCount: users.filter((u) => u.userId).length,
        };
      }),
    );
    return enriched.sort((a, b) => b.count - a.count);
  }

  async resolve(id: string, adminId: string, ip: string | null, note?: string) {
    const row = await this.prisma.errorLog.findUnique({ where: { id } });
    if (!row) throw new NotFoundException();
    const updated = await this.prisma.errorLog.update({
      where: { id },
      data: {
        status: ErrorResolutionStatus.RESOLVED,
        resolvedById: adminId,
        resolvedAt: new Date(),
        ...(note !== undefined ? { internalNote: note } : {}),
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'ERROR_RESOLVE',
      targetType: 'ErrorLog',
      targetId: id,
      ipAddress: ip,
    });
    return updated;
  }

  async updateAlertConfig(body: {
    maxOccurrences?: number;
    windowMinutes?: number;
    slackWebhookUrl?: string | null;
    alertEmail?: string | null;
    scrubKeywords?: string[];
    isEnabled?: boolean;
  }) {
    if (
      body.slackWebhookUrl !== undefined &&
      body.slackWebhookUrl !== null &&
      body.slackWebhookUrl.trim() !== ''
    ) {
      assertSlackIncomingWebhookUrl(body.slackWebhookUrl);
    }
    const data = await this.prisma.errorAlertConfig.upsert({
      where: { name: 'default' },
      create: {
        name: 'default',
        maxOccurrences: body.maxOccurrences ?? 10,
        windowMinutes: body.windowMinutes ?? 60,
        slackWebhookUrl: body.slackWebhookUrl ?? null,
        alertEmail: body.alertEmail ?? null,
        scrubKeywords: body.scrubKeywords
          ? (body.scrubKeywords as object)
          : undefined,
        isEnabled: body.isEnabled ?? true,
      },
      update: {
        ...(body.maxOccurrences !== undefined
          ? { maxOccurrences: body.maxOccurrences }
          : {}),
        ...(body.windowMinutes !== undefined
          ? { windowMinutes: body.windowMinutes }
          : {}),
        ...(body.slackWebhookUrl !== undefined
          ? { slackWebhookUrl: body.slackWebhookUrl }
          : {}),
        ...(body.alertEmail !== undefined
          ? { alertEmail: body.alertEmail }
          : {}),
        ...(body.scrubKeywords !== undefined
          ? { scrubKeywords: body.scrubKeywords as object }
          : {}),
        ...(body.isEnabled !== undefined ? { isEnabled: body.isEnabled } : {}),
      },
    });
    return data;
  }

  getAlertConfig() {
    return this.prisma.errorAlertConfig.findUnique({
      where: { name: 'default' },
    });
  }
}

export function fingerprintForError(
  errorType: string,
  message: string,
  screen?: string,
): string {
  const normalized = `${errorType}|${screen ?? ''}|${message.slice(0, 400)}`;
  return createHash('sha256').update(normalized, 'utf8').digest('hex');
}
