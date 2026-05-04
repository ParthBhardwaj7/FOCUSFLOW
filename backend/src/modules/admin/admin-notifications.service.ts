import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PushTargetType, UserPlan, type Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';

function chunkStrings(tokens: string[], size: number): string[][] {
  const out: string[][] = [];
  for (let i = 0; i < tokens.length; i += size) {
    out.push(tokens.slice(i, i + size));
  }
  return out;
}

@Injectable()
export class AdminNotificationsService {
  private readonly log = new Logger(AdminNotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
    private readonly config: ConfigService,
  ) {}

  history() {
    return this.prisma.pushNotification.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
  }

  async send(
    input: {
      title: string;
      body: string;
      targetType: PushTargetType;
      targetUserIds?: string[];
      scheduledAt?: Date | null;
    },
    adminId: string,
    ip: string | null,
  ) {
    const row = await this.prisma.pushNotification.create({
      data: {
        title: input.title.slice(0, 200),
        body: input.body.slice(0, 2000),
        targetType: input.targetType,
        targetUserIds: input.targetUserIds ?? [],
        scheduledAt: input.scheduledAt ?? null,
        createdByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'PUSH_CREATE',
      targetType: 'PushNotification',
      targetId: row.id,
      ipAddress: ip,
    });
    let dispatchMeta:
      | {
          targetUserCount: number;
          deviceTokenCount: number;
          fcmDelivered?: number;
        }
      | undefined;
    if (!input.scheduledAt || input.scheduledAt <= new Date()) {
      dispatchMeta = await this.dispatchNow(row.id);
    }
    const notification = await this.prisma.pushNotification.findUniqueOrThrow({
      where: { id: row.id },
    });
    const warnings = this.buildDispatchWarnings(
      dispatchMeta,
      Boolean(this.config.get<string>('FCM_SERVER_KEY')?.trim()),
    );
    return { ...notification, ...dispatchMeta, warnings };
  }

  private buildDispatchWarnings(
    meta:
      | {
          targetUserCount: number;
          deviceTokenCount: number;
          fcmDelivered?: number;
        }
      | undefined,
    fcmConfigured: boolean,
  ): string[] {
    const w: string[] = [];
    if (!meta) return w;
    if (meta.targetUserCount === 0) {
      w.push('No accounts matched this audience.');
    }
    if (meta.deviceTokenCount === 0 && meta.targetUserCount > 0) {
      w.push(
        'No device tokens in PushDevice — the mobile app must call POST /v1/notifications/register after sign-in (FCM token).',
      );
    }
    if (!fcmConfigured) {
      w.push(
        'FCM_SERVER_KEY is not set on the API — notification was recorded but not sent via FCM.',
      );
    } else if (
      meta.deviceTokenCount > 0 &&
      (meta.fcmDelivered === undefined || meta.fcmDelivered === 0)
    ) {
      w.push(
        'FCM returned no successes — check server logs, token validity, and that the server key matches your Firebase project.',
      );
    }
    return w;
  }

  /**
   * Resolves targets, updates sentCount (registered device rows), and optionally
   * calls FCM legacy HTTP API when FCM_SERVER_KEY is set.
   */
  private async dispatchNow(id: string): Promise<{
    targetUserCount: number;
    deviceTokenCount: number;
    fcmDelivered?: number;
  }> {
    const row = await this.prisma.pushNotification.findUniqueOrThrow({
      where: { id },
    });
    let userIds: string[] = [];
    if (row.targetType === PushTargetType.SPECIFIC) {
      userIds = row.targetUserIds;
    } else if (row.targetType === PushTargetType.ALL) {
      const users = await this.prisma.user.findMany({
        where: { isBanned: false },
        select: { id: true },
      });
      userIds = users.map((u) => u.id);
    } else if (row.targetType === PushTargetType.SEGMENT) {
      const filter = row.segmentFilter as Record<string, unknown> | null;
      const kind = filter?.['kind'];
      if (kind === 'free') {
        const u = await this.prisma.user.findMany({
          where: { isBanned: false, plan: UserPlan.FREE },
          select: { id: true },
        });
        userIds = u.map((x) => x.id);
      } else if (kind === 'pro') {
        const u = await this.prisma.user.findMany({
          where: { isBanned: false, plan: UserPlan.PRO },
          select: { id: true },
        });
        userIds = u.map((x) => x.id);
      } else if (kind === 'inactive') {
        const cutoff = new Date(Date.now() - 7 * 86_400_000);
        const u = await this.prisma.user.findMany({
          where: {
            isBanned: false,
            OR: [{ lastActiveAt: null }, { lastActiveAt: { lt: cutoff } }],
          },
          select: { id: true },
        });
        userIds = u.map((x) => x.id);
      }
    }

    const deviceRows = await this.prisma.pushDevice.findMany({
      where: { userId: { in: userIds } },
      select: { token: true },
    });
    const tokens = deviceRows.map((d) => d.token);
    const deviceTokenCount = tokens.length;

    const fcmKey = this.config.get<string>('FCM_SERVER_KEY')?.trim();
    let fcmDelivered: number | undefined;
    if (fcmKey && tokens.length > 0) {
      fcmDelivered = await this.tryFcmLegacyMulticast(
        fcmKey,
        tokens,
        row.title,
        row.body,
      );
    }

    await this.prisma.pushNotification.update({
      where: { id },
      data: {
        sentAt: new Date(),
        sentCount: deviceTokenCount,
      },
    });

    return {
      targetUserCount: userIds.length,
      deviceTokenCount,
      fcmDelivered,
    };
  }

  /** Legacy FCM HTTP API (server key). Returns aggregate success count from batches. */
  private async tryFcmLegacyMulticast(
    serverKey: string,
    tokens: string[],
    title: string,
    body: string,
  ): Promise<number> {
    const url = 'https://fcm.googleapis.com/fcm/send';
    let success = 0;
    for (const batch of chunkStrings(tokens, 500)) {
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `key=${serverKey}`,
          },
          body: JSON.stringify({
            registration_ids: batch,
            notification: { title, body },
            priority: 'high',
          }),
        });
        const text = await res.text();
        if (!res.ok) {
          this.log.warn(
            `FCM batch failed status=${res.status} body=${text.slice(0, 400)}`,
          );
          continue;
        }
        let parsed: { success?: number } = {};
        try {
          parsed = JSON.parse(text) as { success?: number };
        } catch {
          this.log.warn(`FCM non-JSON response: ${text.slice(0, 200)}`);
          continue;
        }
        success += typeof parsed.success === 'number' ? parsed.success : 0;
      } catch (e) {
        this.log.warn(
          `FCM batch error: ${e instanceof Error ? e.message : String(e)}`,
        );
      }
    }
    return success;
  }

  async schedule(
    input: {
      title: string;
      body: string;
      targetType: PushTargetType;
      targetUserIds?: string[];
      segmentFilter?: Record<string, unknown>;
      scheduledAt: Date;
    },
    adminId: string,
    ip: string | null,
  ) {
    const row = await this.prisma.pushNotification.create({
      data: {
        title: input.title.slice(0, 200),
        body: input.body.slice(0, 2000),
        targetType: input.targetType,
        targetUserIds: input.targetUserIds ?? [],
        segmentFilter: (input.segmentFilter ?? undefined) as
          | Prisma.InputJsonValue
          | undefined,
        scheduledAt: input.scheduledAt,
        createdByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'PUSH_SCHEDULE',
      targetType: 'PushNotification',
      targetId: row.id,
      ipAddress: ip,
    });
    return row;
  }
}
