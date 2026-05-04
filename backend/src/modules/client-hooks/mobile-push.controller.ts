import { Body, Controller, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { PushDevicePlatform } from '@prisma/client';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { PrismaService } from '../../prisma/prisma.service';
import { IsEnum, IsString, MinLength } from 'class-validator';

class RegisterPushDto {
  @IsString()
  @MinLength(10)
  deviceToken!: string;

  @IsEnum(PushDevicePlatform)
  platform!: PushDevicePlatform;
}

@Throttle({ default: { limit: 20, ttl: 60_000 } })
@Controller({ path: 'notifications', version: '1' })
export class MobilePushController {
  constructor(private readonly prisma: PrismaService) {}

  @Post('register')
  async register(
    @CurrentUser() u: JwtUserPayload,
    @Body() dto: RegisterPushDto,
  ) {
    return this.prisma.pushDevice.upsert({
      where: {
        userId_token: { userId: u.userId, token: dto.deviceToken },
      },
      create: {
        userId: u.userId,
        token: dto.deviceToken,
        platform: dto.platform,
      },
      update: { platform: dto.platform },
    });
  }
}
