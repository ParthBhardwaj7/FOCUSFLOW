import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { InsightMood } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import {
  AdminUser,
  type AdminRequestUser,
} from './decorators/admin-user.decorator';
import { AdminContentService } from './admin-content.service';

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/categories', version: VERSION_NEUTRAL })
export class AdminCategoriesController {
  constructor(private readonly content: AdminContentService) {}

  @Get()
  list() {
    return this.content.categories();
  }

  @Post()
  create(
    @Body()
    body: {
      name: string;
      emoji?: string;
      themeColor?: string;
      defaultSoundId?: string;
      sortOrder?: number;
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.createCategory(body, admin.userId, clientIp(req));
  }

  @Put(':id')
  update(
    @Param('id') id: string,
    @Body()
    body: Partial<{
      name: string;
      emoji: string;
      themeColor: string;
      defaultSoundId: string | null;
      isActive: boolean;
      sortOrder: number;
    }>,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.updateCategory(id, body, admin.userId, clientIp(req));
  }

  @Delete(':id')
  remove(
    @Param('id') id: string,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.deleteCategory(id, admin.userId, clientIp(req));
  }

  @Patch('reorder')
  reorder(
    @Body() body: { orderedIds: string[] },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.reorderCategories(
      body.orderedIds ?? [],
      admin.userId,
      clientIp(req),
    );
  }
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/sounds', version: VERSION_NEUTRAL })
export class AdminSoundsController {
  constructor(
    private readonly content: AdminContentService,
    private readonly config: ConfigService,
  ) {}

  @Get()
  list() {
    return this.content.sounds();
  }

  @Post()
  create(
    @Body()
    body: {
      name: string;
      fileUrl: string;
      emoji?: string;
      durationSeconds?: number;
      categoryTag?: string;
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.createSound(body, admin.userId, clientIp(req));
  }

  @Post('upload')
  @UseInterceptors(
    FileInterceptor('file', { limits: { fileSize: 5 * 1024 * 1024 } }),
  )
  upload(@UploadedFile() file: { buffer: Buffer; originalname: string }) {
    const base = this.config.get<string>('SOUND_PUBLIC_BASE_URL')?.trim() ?? '';
    return this.content.saveUploadedSound(file, base);
  }

  @Put(':id')
  update(
    @Param('id') id: string,
    @Body()
    body: Partial<{
      name: string;
      emoji: string;
      fileUrl: string;
      categoryTag: string;
      isActive: boolean;
    }>,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.updateSound(id, body, admin.userId, clientIp(req));
  }

  @Delete(':id')
  remove(
    @Param('id') id: string,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.softDeleteSound(id, admin.userId, clientIp(req));
  }
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/ai-suggestions', version: VERSION_NEUTRAL })
export class AdminAiSuggestionsController {
  constructor(private readonly content: AdminContentService) {}

  @Get()
  list() {
    return this.content.aiSuggestions();
  }

  @Post()
  create(
    @Body()
    body: {
      title: string;
      subtitle: string;
      icon?: string;
      targetCondition: string;
      isActive?: boolean;
      variantParentId?: string;
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.upsertAiSuggestion(
      undefined,
      body,
      admin.userId,
      clientIp(req),
    );
  }

  @Put(':id')
  update(
    @Param('id') id: string,
    @Body()
    body: {
      title: string;
      subtitle: string;
      icon?: string;
      targetCondition: string;
      isActive?: boolean;
      variantParentId?: string | null;
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.upsertAiSuggestion(
      id,
      body,
      admin.userId,
      clientIp(req),
    );
  }

  @Delete(':id')
  remove(
    @Param('id') id: string,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.deleteAiSuggestion(id, admin.userId, clientIp(req));
  }
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin', version: VERSION_NEUTRAL })
export class AdminAiInsightsController {
  constructor(private readonly content: AdminContentService) {}

  @Get('ai-insights')
  list() {
    return this.content.aiInsights();
  }

  @Put('ai-insights')
  put(
    @Body()
    body: {
      items: {
        mood: InsightMood;
        title: string;
        subtitle: string;
        icon?: string;
      }[];
    },
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.content.putAiInsights(
      body.items ?? [],
      admin.userId,
      clientIp(req),
    );
  }
}
