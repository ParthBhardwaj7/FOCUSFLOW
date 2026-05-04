import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { UserRole } from '@prisma/client';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../../../prisma/prisma.service';

export type AdminJwtPayload = {
  sub: string;
  email: string;
  role: UserRole;
};

@Injectable()
export class AdminJwtStrategy extends PassportStrategy(Strategy, 'admin-jwt') {
  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    const adminSecret = config.get<string>('ADMIN_JWT_ACCESS_SECRET');
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey:
        adminSecret && adminSecret.trim().length > 0
          ? adminSecret.trim()
          : config.getOrThrow<string>('JWT_ACCESS_SECRET'),
    });
  }

  async validate(payload: AdminJwtPayload) {
    if (!payload?.sub || !payload.role) {
      throw new UnauthorizedException();
    }
    if (
      payload.role !== UserRole.ADMIN &&
      payload.role !== UserRole.SUPERADMIN
    ) {
      throw new UnauthorizedException();
    }
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, email: true, role: true, isBanned: true },
    });
    if (!user || user.isBanned) {
      throw new UnauthorizedException();
    }
    if (user.role !== UserRole.ADMIN && user.role !== UserRole.SUPERADMIN) {
      throw new UnauthorizedException();
    }
    return {
      userId: user.id,
      email: user.email,
      role: user.role,
    };
  }
}
