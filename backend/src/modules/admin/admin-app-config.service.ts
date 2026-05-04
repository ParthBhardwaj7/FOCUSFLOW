import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';

@Injectable()
export class AdminAppConfigService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
  ) {}

  list() {
    return this.prisma.appConfig.findMany({ orderBy: { key: 'asc' } });
  }

  async putKey(
    key: string,
    value: string,
    adminId: string,
    ip: string | null,
    description?: string,
    isPublic?: boolean,
  ) {
    const existing = await this.prisma.appConfig.findUnique({ where: { key } });
    const row = await this.prisma.appConfig.upsert({
      where: { key },
      create: {
        key,
        value,
        description: description ?? null,
        isPublic: isPublic ?? false,
        updatedByUserId: adminId,
      },
      update: {
        value,
        ...(description !== undefined ? { description } : {}),
        ...(isPublic !== undefined ? { isPublic } : {}),
        updatedByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'APP_CONFIG_PUT',
      targetType: 'AppConfig',
      targetId: row.id,
      oldValue: existing ? { value: existing.value } : undefined,
      newValue: { value: row.value, isPublic: row.isPublic },
      ipAddress: ip,
    });
    return row;
  }

  async getByKey(key: string) {
    const row = await this.prisma.appConfig.findUnique({ where: { key } });
    if (!row) throw new NotFoundException();
    return row;
  }
}
