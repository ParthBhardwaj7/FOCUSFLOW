import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { UserPlan, UserRole } from '@prisma/client';
import * as argon2 from 'argon2';
import type { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';
import type { AdminBanUserDto } from './dto/admin-ban-user.dto';

@Injectable()
export class AdminUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
  ) {}

  async list(params: {
    page: number;
    limit: number;
    search?: string;
    plan?: UserPlan;
    status?: 'active' | 'banned' | 'inactive';
    sort?: 'newest' | 'most_active' | 'lowest_completion';
    /** `all` matches dashboard “accounts”; `app` limits to mobile end-users only. */
    accountKind?: 'all' | 'app';
  }) {
    const { page, limit, search, plan, status, sort, accountKind } = params;
    const skip = (page - 1) * limit;
    const parts: Prisma.UserWhereInput[] = [];
    if (accountKind === 'app') {
      parts.push({ role: UserRole.USER });
    }
    if (plan) parts.push({ plan });
    if (status === 'banned') parts.push({ isBanned: true });
    if (status === 'active') parts.push({ isBanned: false });
    if (status === 'inactive') {
      const cutoff = new Date(Date.now() - 30 * 86_400_000);
      parts.push({
        OR: [{ lastActiveAt: null }, { lastActiveAt: { lt: cutoff } }],
      });
    }
    if (search?.trim()) {
      const q = search.trim();
      parts.push({
        OR: [
          { email: { contains: q, mode: 'insensitive' } },
          { displayName: { contains: q, mode: 'insensitive' } },
          { username: { contains: q, mode: 'insensitive' } },
        ],
      });
    }
    const where: Prisma.UserWhereInput =
      parts.length === 0 ? {} : parts.length === 1 ? parts[0] : { AND: parts };
    const orderBy =
      sort === 'most_active'
        ? [{ lastActiveAt: 'desc' as const }]
        : sort === 'lowest_completion'
          ? [{ createdAt: 'asc' as const }]
          : [{ createdAt: 'desc' as const }];

    const [total, rows] = await Promise.all([
      this.prisma.user.count({ where }),
      this.prisma.user.findMany({
        where,
        skip,
        take: limit,
        orderBy,
        select: {
          id: true,
          email: true,
          displayName: true,
          username: true,
          avatarUrl: true,
          role: true,
          plan: true,
          isBanned: true,
          banReason: true,
          lastActiveAt: true,
          deviceOs: true,
          appVersion: true,
          createdAt: true,
        },
      }),
    ]);

    const ids = rows.map((r) => r.id);
    const completionMap = await this.completionRates7d(ids);

    const items = rows.map((u) => ({
      ...u,
      tasksCount: undefined as number | undefined,
      completionRate7d: completionMap.get(u.id) ?? 0,
    }));
    for (const u of items) {
      u.tasksCount = await this.prisma.task.count({
        where: { userId: u.id, archivedAt: null },
      });
    }

    if (sort === 'lowest_completion') {
      items.sort(
        (a, b) => (a.completionRate7d ?? 0) - (b.completionRate7d ?? 0),
      );
    }

    return { total, page, limit, items };
  }

  private async completionRates7d(
    userIds: string[],
  ): Promise<Map<string, number>> {
    const map = new Map<string, number>();
    if (userIds.length === 0) return map;
    const since = new Date();
    since.setUTCDate(since.getUTCDate() - 7);
    const sinceDate = new Date(since.toISOString().slice(0, 10));
    for (const uid of userIds) {
      const [planned, completed] = await Promise.all([
        this.prisma.task.count({
          where: {
            userId: uid,
            archivedAt: null,
            scheduledOn: { gte: sinceDate },
          },
        }),
        this.prisma.task.count({
          where: {
            userId: uid,
            archivedAt: null,
            scheduledOn: { gte: sinceDate },
            completedAt: { not: null },
          },
        }),
      ]);
      map.set(
        uid,
        planned === 0 ? 0 : Math.round((completed / planned) * 1000) / 10,
      );
    }
    return map;
  }

  async getOne(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        displayName: true,
        username: true,
        avatarUrl: true,
        role: true,
        plan: true,
        isBanned: true,
        banReason: true,
        banExpiresAt: true,
        lastActiveAt: true,
        deviceOs: true,
        appVersion: true,
        timeZone: true,
        createdAt: true,
      },
    });
    if (!user) throw new NotFoundException();
    const [tasksCreated, completionRate7d, recentTasks, aiLogs, errors] =
      await Promise.all([
        this.prisma.task.count({ where: { userId: id, archivedAt: null } }),
        this.completionRates7d([id]).then((m) => m.get(id) ?? 0),
        this.prisma.task.findMany({
          where: { userId: id, archivedAt: null },
          orderBy: { createdAt: 'desc' },
          take: 20,
          select: {
            id: true,
            title: true,
            scheduledOn: true,
            completedAt: true,
            createdAt: true,
          },
        }),
        this.prisma.aiCoachLog.findMany({
          where: { userId: id },
          orderBy: { createdAt: 'desc' },
          take: 30,
          select: {
            id: true,
            messageUser: true,
            messageAi: true,
            createdAt: true,
            tokensUsed: true,
          },
        }),
        this.prisma.errorLog.findMany({
          where: { userId: id },
          orderBy: { createdAt: 'desc' },
          take: 30,
        }),
      ]);
    return {
      user,
      stats: { tasksCreated, completionRate7d },
      recentTasks,
      aiCoachLogs: aiLogs,
      errorLogs: errors,
    };
  }

  async ban(
    id: string,
    dto: AdminBanUserDto,
    adminId: string,
    ip: string | null,
  ) {
    const expires = dto.banExpiresAt ? new Date(dto.banExpiresAt) : null;
    if (expires && Number.isNaN(expires.getTime())) {
      throw new BadRequestException('Invalid banExpiresAt');
    }
    const before = await this.prisma.user.findUnique({ where: { id } });
    if (!before) throw new NotFoundException();
    if (before.role !== UserRole.USER) {
      throw new ForbiddenException('Cannot ban admin accounts');
    }
    const updated = await this.prisma.user.update({
      where: { id },
      data: {
        isBanned: true,
        banReason: dto.reason,
        banExpiresAt: expires,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'USER_BAN',
      targetType: 'User',
      targetId: id,
      oldValue: { isBanned: before.isBanned },
      newValue: { isBanned: true, banReason: dto.reason },
      ipAddress: ip,
    });
    return updated;
  }

  async unban(id: string, adminId: string, ip: string | null) {
    const before = await this.prisma.user.findUnique({ where: { id } });
    if (!before) throw new NotFoundException();
    const updated = await this.prisma.user.update({
      where: { id },
      data: {
        isBanned: false,
        banReason: null,
        banExpiresAt: null,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'USER_UNBAN',
      targetType: 'User',
      targetId: id,
      oldValue: { isBanned: before.isBanned },
      newValue: { isBanned: false },
      ipAddress: ip,
    });
    return updated;
  }

  async deleteUser(id: string, adminId: string, ip: string | null) {
    const before = await this.prisma.user.findUnique({ where: { id } });
    if (!before) throw new NotFoundException();
    if (before.role !== UserRole.USER) {
      throw new ForbiddenException('Cannot delete admin accounts');
    }
    await this.audit.log({
      adminUserId: adminId,
      action: 'USER_DELETE',
      targetType: 'User',
      targetId: id,
      oldValue: { email: before.email },
      ipAddress: ip,
    });
    await this.prisma.user.delete({ where: { id } });
  }

  async resetPassword(
    id: string,
    newPassword: string,
    adminId: string,
    ip: string | null,
    adminRole: UserRole,
  ) {
    if (adminRole !== UserRole.SUPERADMIN) {
      throw new ForbiddenException();
    }
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException();
    const passwordHash = await argon2.hash(newPassword);
    await this.prisma.user.update({
      where: { id },
      data: { passwordHash },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'USER_RESET_PASSWORD',
      targetType: 'User',
      targetId: id,
      ipAddress: ip,
    });
    return { ok: true };
  }

  async impersonateLog(id: string, adminId: string, ip: string | null) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException();
    await this.audit.log({
      adminUserId: adminId,
      action: 'IMPERSONATE_VIEW',
      targetType: 'User',
      targetId: id,
      ipAddress: ip,
    });
    return {
      ok: true,
      message:
        'Use the admin user detail drawer for read-only inspection. Mobile impersonation tokens are not issued from this endpoint.',
    };
  }

  async exportCsv(query: {
    search?: string;
    plan?: UserPlan;
    status?: 'active' | 'banned' | 'inactive';
    accountKind?: 'all' | 'app';
  }) {
    const { items } = await this.list({
      page: 1,
      limit: 50_000,
      search: query.search,
      plan: query.plan,
      status: query.status,
      sort: 'newest',
      accountKind: query.accountKind ?? 'all',
    });
    const header = [
      'id',
      'email',
      'displayName',
      'role',
      'plan',
      'isBanned',
      'lastActiveAt',
      'completionRate7d',
    ].join(',');
    const lines = items.map((u) =>
      [
        u.id,
        JSON.stringify(u.email),
        JSON.stringify(u.displayName ?? ''),
        u.role,
        u.plan,
        u.isBanned,
        u.lastActiveAt?.toISOString() ?? '',
        u.completionRate7d,
      ].join(','),
    );
    return `${header}\n${lines.join('\n')}`;
  }

  async createAdminUser(
    email: string,
    password: string,
    adminId: string,
    ip: string | null,
  ) {
    const normalized = email.trim().toLowerCase();
    const existing = await this.prisma.user.findUnique({
      where: { email: normalized },
    });
    if (existing) {
      throw new BadRequestException('Email already exists');
    }
    const passwordHash = await argon2.hash(password);
    const user = await this.prisma.user.create({
      data: {
        email: normalized,
        passwordHash,
        role: UserRole.ADMIN,
      },
      select: { id: true, email: true, role: true },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'ADMIN_USER_CREATE',
      targetType: 'User',
      targetId: user.id,
      newValue: { email: user.email, role: user.role },
      ipAddress: ip,
    });
    return user;
  }
}
