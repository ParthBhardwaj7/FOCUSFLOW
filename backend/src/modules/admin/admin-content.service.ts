import { BadRequestException, Injectable } from '@nestjs/common';
import { InsightMood } from '@prisma/client';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';

@Injectable()
export class AdminContentService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
  ) {}

  categories() {
    return this.prisma.category.findMany({ orderBy: { sortOrder: 'asc' } });
  }

  async createCategory(
    data: {
      name: string;
      emoji?: string;
      themeColor?: string;
      defaultSoundId?: string;
      sortOrder?: number;
    },
    adminId: string,
    ip: string | null,
  ) {
    const row = await this.prisma.category.create({
      data: {
        name: data.name,
        emoji: data.emoji,
        themeColor: data.themeColor,
        defaultSoundId: data.defaultSoundId,
        sortOrder: data.sortOrder ?? 0,
        createdByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'CATEGORY_CREATE',
      targetType: 'Category',
      targetId: row.id,
      ipAddress: ip,
    });
    return row;
  }

  async updateCategory(
    id: string,
    data: Partial<{
      name: string;
      emoji: string;
      themeColor: string;
      defaultSoundId: string | null;
      isActive: boolean;
      sortOrder: number;
    }>,
    adminId: string,
    ip: string | null,
  ) {
    const row = await this.prisma.category.update({
      where: { id },
      data,
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'CATEGORY_UPDATE',
      targetType: 'Category',
      targetId: id,
      ipAddress: ip,
    });
    return row;
  }

  async deleteCategory(id: string, adminId: string, ip: string | null) {
    await this.prisma.category.delete({ where: { id } }).catch(() => {
      throw new BadRequestException('Category not found or in use');
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'CATEGORY_DELETE',
      targetType: 'Category',
      targetId: id,
      ipAddress: ip,
    });
    return { ok: true };
  }

  async reorderCategories(
    orderedIds: string[],
    adminId: string,
    ip: string | null,
  ) {
    let order = 0;
    for (const id of orderedIds) {
      await this.prisma.category.update({
        where: { id },
        data: { sortOrder: order++ },
      });
    }
    await this.audit.log({
      adminUserId: adminId,
      action: 'CATEGORY_REORDER',
      targetType: 'Category',
      ipAddress: ip,
    });
    return this.categories();
  }

  sounds() {
    return this.prisma.sound.findMany({
      where: { deletedAt: null },
      orderBy: { createdAt: 'desc' },
    });
  }

  async createSound(
    data: {
      name: string;
      fileUrl: string;
      emoji?: string;
      durationSeconds?: number;
      categoryTag?: string;
    },
    adminId: string,
    ip: string | null,
  ) {
    const row = await this.prisma.sound.create({
      data: {
        name: data.name,
        fileUrl: data.fileUrl,
        emoji: data.emoji,
        durationSeconds: data.durationSeconds,
        categoryTag: data.categoryTag,
        createdByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'SOUND_CREATE',
      targetType: 'Sound',
      targetId: row.id,
      ipAddress: ip,
    });
    return row;
  }

  async updateSound(
    id: string,
    data: Partial<{
      name: string;
      emoji: string;
      fileUrl: string;
      categoryTag: string;
      isActive: boolean;
    }>,
    adminId: string,
    ip: string | null,
  ) {
    const row = await this.prisma.sound.update({ where: { id }, data });
    await this.audit.log({
      adminUserId: adminId,
      action: 'SOUND_UPDATE',
      targetType: 'Sound',
      targetId: id,
      ipAddress: ip,
    });
    return row;
  }

  async softDeleteSound(id: string, adminId: string, ip: string | null) {
    await this.prisma.sound.update({
      where: { id },
      data: { deletedAt: new Date(), isActive: false },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'SOUND_SOFT_DELETE',
      targetType: 'Sound',
      targetId: id,
      ipAddress: ip,
    });
    return { ok: true };
  }

  async saveUploadedSound(
    file: { buffer: Buffer; originalname: string },
    publicBase: string,
  ) {
    if (!file?.buffer?.length) {
      throw new BadRequestException('Empty file');
    }
    const lower = file.originalname.toLowerCase();
    let ext: '.mp3' | '.ogg' | '.wav';
    if (lower.endsWith('.ogg')) {
      ext = '.ogg';
    } else if (lower.endsWith('.wav')) {
      ext = '.wav';
    } else if (lower.endsWith('.mp3')) {
      ext = '.mp3';
    } else {
      throw new BadRequestException(
        'Only .mp3, .ogg, and .wav uploads are allowed',
      );
    }
    const sniff = sniffAudioContainer(file.buffer);
    if (sniff === null || sniff !== ext.slice(1)) {
      throw new BadRequestException(
        'File content does not match an allowed audio type',
      );
    }
    const dir = join(process.cwd(), 'uploads', 'sounds');
    await mkdir(dir, { recursive: true });
    const name = `${randomBytes(16).toString('hex')}${ext}`;
    const full = join(dir, name);
    await writeFile(full, file.buffer);
    const base = publicBase.replace(/\/$/, '');
    const fileUrl = base
      ? `${base}/uploads/sounds/${name}`
      : `/uploads/sounds/${name}`;
    return { fileUrl, bytes: file.buffer.length };
  }

  aiSuggestions() {
    return this.prisma.aiSuggestion.findMany({
      orderBy: { createdAt: 'desc' },
    });
  }

  async upsertAiSuggestion(
    id: string | undefined,
    data: {
      title: string;
      subtitle: string;
      icon?: string;
      targetCondition: string;
      isActive?: boolean;
      variantParentId?: string | null;
    },
    adminId: string,
    ip: string | null,
  ) {
    if (id) {
      const row = await this.prisma.aiSuggestion.update({
        where: { id },
        data: {
          title: data.title,
          subtitle: data.subtitle,
          icon: data.icon,
          targetCondition: data.targetCondition,
          ...(data.isActive !== undefined ? { isActive: data.isActive } : {}),
          variantParentId: data.variantParentId ?? undefined,
        },
      });
      await this.audit.log({
        adminUserId: adminId,
        action: 'AI_SUGGESTION_UPDATE',
        targetType: 'AiSuggestion',
        targetId: id,
        ipAddress: ip,
      });
      return row;
    }
    const row = await this.prisma.aiSuggestion.create({
      data: {
        title: data.title,
        subtitle: data.subtitle,
        icon: data.icon,
        targetCondition: data.targetCondition,
        isActive: data.isActive ?? true,
        variantParentId: data.variantParentId ?? undefined,
        createdByUserId: adminId,
      },
    });
    await this.audit.log({
      adminUserId: adminId,
      action: 'AI_SUGGESTION_CREATE',
      targetType: 'AiSuggestion',
      targetId: row.id,
      ipAddress: ip,
    });
    return row;
  }

  async deleteAiSuggestion(id: string, adminId: string, ip: string | null) {
    await this.prisma.aiSuggestion.delete({ where: { id } });
    await this.audit.log({
      adminUserId: adminId,
      action: 'AI_SUGGESTION_DELETE',
      targetType: 'AiSuggestion',
      targetId: id,
      ipAddress: ip,
    });
    return { ok: true };
  }

  aiInsights() {
    return this.prisma.aiInsightTemplate.findMany();
  }

  async putAiInsights(
    items: {
      mood: InsightMood;
      title: string;
      subtitle: string;
      icon?: string;
    }[],
    adminId: string,
    ip: string | null,
  ) {
    for (const it of items) {
      await this.prisma.aiInsightTemplate.upsert({
        where: { mood: it.mood },
        create: {
          mood: it.mood,
          title: it.title,
          subtitle: it.subtitle,
          icon: it.icon,
        },
        update: {
          title: it.title,
          subtitle: it.subtitle,
          icon: it.icon,
        },
      });
    }
    await this.audit.log({
      adminUserId: adminId,
      action: 'AI_INSIGHTS_UPDATE',
      targetType: 'AiInsightTemplate',
      ipAddress: ip,
    });
    return this.prisma.aiInsightTemplate.findMany();
  }
}

/** Server-side audio sniff — extension must match container (not only filename). */
function sniffAudioContainer(buf: Buffer): 'mp3' | 'ogg' | 'wav' | null {
  if (buf.length < 4) return null;
  if (buf.subarray(0, 4).equals(Buffer.from('OggS'))) return 'ogg';
  if (
    buf.length >= 12 &&
    buf.subarray(0, 4).equals(Buffer.from('RIFF')) &&
    buf.subarray(8, 12).equals(Buffer.from('WAVE'))
  ) {
    return 'wav';
  }
  if (buf.length >= 3 && buf.subarray(0, 3).equals(Buffer.from('ID3')))
    return 'mp3';
  if (buf.length >= 2 && buf[0] === 0xff && (buf[1] & 0xe0) === 0xe0)
    return 'mp3';
  return null;
}
