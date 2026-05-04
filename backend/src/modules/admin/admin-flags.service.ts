import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';
import type { AdminCreateFlagDto } from './dto/admin-create-flag.dto';
import type { AdminUpdateFlagDto } from './dto/admin-update-flag.dto';

@Injectable()
export class AdminFlagsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
  ) {}

  list() {
    return this.prisma.featureFlag.findMany({ orderBy: { key: 'asc' } });
  }

  async create(dto: AdminCreateFlagDto, adminId: string, ip: string | null) {
    const row = await this.prisma.featureFlag.create({
      data: {
        key: dto.key.trim(),
        isEnabled: dto.isEnabled ?? false,
        rolloutPercentage: dto.rolloutPercentage ?? 0,
        enabledForUserIds: dto.enabledForUserIds ?? [],
        description: dto.description ?? null,
        updatedByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'FLAG_CREATE',
      targetType: 'FeatureFlag',
      targetId: row.id,
      newValue: { key: row.key },
      ipAddress: ip,
    });
    return row;
  }

  async updateByKey(
    key: string,
    dto: AdminUpdateFlagDto,
    adminId: string,
    ip: string | null,
  ) {
    const existing = await this.prisma.featureFlag.findUnique({
      where: { key },
    });
    if (!existing) throw new NotFoundException();
    const updated = await this.prisma.featureFlag.update({
      where: { key },
      data: {
        ...(dto.isEnabled !== undefined ? { isEnabled: dto.isEnabled } : {}),
        ...(dto.rolloutPercentage !== undefined
          ? { rolloutPercentage: dto.rolloutPercentage }
          : {}),
        ...(dto.enabledForUserIds !== undefined
          ? { enabledForUserIds: dto.enabledForUserIds }
          : {}),
        ...(dto.description !== undefined
          ? { description: dto.description }
          : {}),
        ...(dto.scheduledEnableAt !== undefined
          ? {
              scheduledEnableAt: dto.scheduledEnableAt
                ? new Date(dto.scheduledEnableAt)
                : null,
            }
          : {}),
        ...(dto.scheduledDisableAt !== undefined
          ? {
              scheduledDisableAt: dto.scheduledDisableAt
                ? new Date(dto.scheduledDisableAt)
                : null,
            }
          : {}),
        updatedByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'FLAG_UPDATE',
      targetType: 'FeatureFlag',
      targetId: existing.id,
      oldValue: {
        isEnabled: existing.isEnabled,
        rolloutPercentage: existing.rolloutPercentage,
      },
      newValue: {
        isEnabled: updated.isEnabled,
        rolloutPercentage: updated.rolloutPercentage,
      },
      ipAddress: ip,
    });
    return updated;
  }
}
