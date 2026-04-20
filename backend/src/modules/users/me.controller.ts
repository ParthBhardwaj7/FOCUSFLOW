import { Body, Controller, Get, Patch } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { PrismaService } from '../../prisma/prisma.service';
import { PatchMeDto } from './dto/patch-me.dto';

@Controller({ path: 'me', version: '1' })
export class MeController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async me(@CurrentUser() u: JwtUserPayload) {
    return this.prisma.user.findUniqueOrThrow({
      where: { id: u.userId },
      select: {
        id: true,
        email: true,
        emailVerifiedAt: true,
        onboardingCompletedAt: true,
        timeZone: true,
        profileSummary: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  @Patch()
  async patchMe(@CurrentUser() u: JwtUserPayload, @Body() dto: PatchMeDto) {
    return this.prisma.user.update({
      where: { id: u.userId },
      data: {
        ...(dto.timeZone !== undefined ? { timeZone: dto.timeZone } : {}),
        ...(dto.onboardingCompletedAt !== undefined
          ? {
              onboardingCompletedAt: new Date(dto.onboardingCompletedAt),
            }
          : {}),
        ...(dto.profileSummary !== undefined
          ? { profileSummary: dto.profileSummary }
          : {}),
      },
      select: {
        id: true,
        email: true,
        emailVerifiedAt: true,
        onboardingCompletedAt: true,
        timeZone: true,
        profileSummary: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }
}
