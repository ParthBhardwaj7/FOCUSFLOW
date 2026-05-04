import { Body, Controller, Post, Req } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Throttle } from '@nestjs/throttler';
import { ErrorResolutionStatus } from '@prisma/client';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { PrismaService } from '../../prisma/prisma.service';
import { MobileRuntimeService } from './mobile-runtime.service';
import { ErrorReportDto } from './dto/error-report.dto';

@Public()
@Throttle({ default: { limit: 30, ttl: 60_000 } })
@Controller({ path: 'errors', version: '1' })
export class ErrorReportController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly mobile: MobileRuntimeService,
    private readonly jwt: JwtService,
  ) {}

  @Post('report')
  async report(@Body() dto: ErrorReportDto, @Req() req: Request) {
    let userId: string | null = null;
    const authz = req.headers.authorization;
    const bearer =
      typeof authz === 'string' && authz.toLowerCase().startsWith('bearer ')
        ? authz.slice(7).trim()
        : '';
    if (bearer) {
      try {
        const payload = await this.jwt.verifyAsync<{ sub?: string }>(bearer);
        if (typeof payload?.sub === 'string' && payload.sub.length > 0) {
          const row = await this.prisma.user.findUnique({
            where: { id: payload.sub },
            select: { id: true },
          });
          if (row) userId = row.id;
        }
      } catch {
        /* invalid or expired token — still accept anonymous error report */
      }
    }

    const tech = this.mobile.redactForErrorStorage(dto.message);
    const surfaceRaw = dto.surfaceMessage?.trim();
    const surface = surfaceRaw
      ? this.mobile.redactForErrorStorage(surfaceRaw)
      : '';
    const combined = surface ? `USER: ${surface}\n---\nTECH: ${tech}` : tech;

    const fingerprint = this.mobile.fingerprintForClient(
      dto.errorType,
      combined,
      dto.screen,
    );

    return this.prisma.errorLog.create({
      data: {
        userId,
        errorType: dto.errorType.slice(0, 200),
        errorMessage: combined.slice(0, 8000),
        screen: dto.screen?.slice(0, 200) ?? null,
        appVersion: dto.appVersion?.slice(0, 100) ?? null,
        deviceOs: dto.deviceOs?.slice(0, 100) ?? null,
        fingerprint,
        status: ErrorResolutionStatus.UNRESOLVED,
      },
    });
  }
}
