import {
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { RefreshTokenScope, UserRole } from '@prisma/client';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { expiryToMs } from '../../common/utils/expiry-ms';
import { hashRefreshToken } from '../../common/utils/refresh-token-hash';
import { ADMIN_JWT } from './admin.constants';
import type { AdminJwtPayload } from './strategies/admin-jwt.strategy';

const _kMaxFails = 5;
const _kLockWindowMs = 15 * 60 * 1000;

@Injectable()
export class AdminAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    @Inject(ADMIN_JWT) private readonly adminJwt: JwtService,
  ) {}

  async assertNotLocked(emailNormalized: string, ip: string) {
    const since = new Date(Date.now() - _kLockWindowMs);
    const [byEmail, byIp] = await Promise.all([
      this.prisma.adminFailedLogin.count({
        where: { emailNormalized, createdAt: { gte: since } },
      }),
      this.prisma.adminFailedLogin.count({
        where: { ipAddress: ip, createdAt: { gte: since } },
      }),
    ]);
    if (byEmail >= _kMaxFails || byIp >= _kMaxFails) {
      throw new HttpException(
        'Too many failed login attempts. Try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  async recordFailure(emailNormalized: string, ip: string) {
    await this.prisma.adminFailedLogin.create({
      data: { emailNormalized, ipAddress: ip },
    });
  }

  async login(email: string, password: string, ip: string) {
    const normalized = email.trim().toLowerCase();
    await this.assertNotLocked(normalized, ip);
    const user = await this.prisma.user.findUnique({
      where: { email: normalized },
    });
    if (!user) {
      await this.recordFailure(normalized, ip);
      throw new UnauthorizedException('Invalid credentials');
    }
    if (user.role !== UserRole.ADMIN && user.role !== UserRole.SUPERADMIN) {
      await this.recordFailure(normalized, ip);
      throw new UnauthorizedException('Invalid credentials');
    }
    if (user.isBanned) {
      await this.recordFailure(normalized, ip);
      throw new UnauthorizedException('Account suspended');
    }
    const ok = await argon2.verify(user.passwordHash, password);
    if (!ok) {
      await this.recordFailure(normalized, ip);
      throw new UnauthorizedException('Invalid credentials');
    }
    return this.issueAdminSession(user.id, user.email, user.role);
  }

  async refresh(refreshTokenRaw: string) {
    const tokenHash = hashRefreshToken(refreshTokenRaw);
    const row = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
    });
    if (
      !row ||
      row.revokedAt ||
      row.expiresAt <= new Date() ||
      row.scope !== RefreshTokenScope.ADMIN
    ) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
    const user = await this.prisma.user.findUnique({
      where: { id: row.userId },
    });
    if (
      !user ||
      user.isBanned ||
      (user.role !== UserRole.ADMIN && user.role !== UserRole.SUPERADMIN)
    ) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
    const refreshExpiresIn = this.config.getOrThrow<string>(
      'JWT_REFRESH_EXPIRES_IN',
    );
    const refreshMs = expiryToMs(refreshExpiresIn, 7 * 86_400_000);
    const expiresAt = new Date(Date.now() + refreshMs);
    const rawRefresh = randomBytes(48).toString('base64url');
    const newHash = hashRefreshToken(rawRefresh);
    const newRow = await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: newHash,
        expiresAt,
        scope: RefreshTokenScope.ADMIN,
      },
    });
    await this.prisma.refreshToken.update({
      where: { id: row.id },
      data: { revokedAt: new Date(), replacedBy: newRow.id },
    });
    return this.buildAdminAccessResponse(
      user.id,
      user.email,
      user.role,
      rawRefresh,
    );
  }

  async logout(refreshTokenRaw: string) {
    const tokenHash = hashRefreshToken(refreshTokenRaw);
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null, scope: RefreshTokenScope.ADMIN },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  }

  private async issueAdminSession(
    userId: string,
    email: string,
    role: UserRole,
  ) {
    const refreshExpiresIn = this.config.getOrThrow<string>(
      'JWT_REFRESH_EXPIRES_IN',
    );
    const refreshMs = expiryToMs(refreshExpiresIn, 7 * 86_400_000);
    const expiresAt = new Date(Date.now() + refreshMs);
    const rawRefresh = randomBytes(48).toString('base64url');
    const tokenHash = hashRefreshToken(rawRefresh);
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash,
        expiresAt,
        scope: RefreshTokenScope.ADMIN,
      },
    });
    return this.buildAdminAccessResponse(userId, email, role, rawRefresh);
  }

  private async buildAdminAccessResponse(
    userId: string,
    email: string,
    role: UserRole,
    refreshToken: string,
  ) {
    const payload: AdminJwtPayload = { sub: userId, email, role };
    const accessToken = await this.adminJwt.signAsync(payload);
    const accessExpiresIn =
      this.config.get<string>('ADMIN_JWT_ACCESS_EXPIRES_IN') ?? '15m';
    const accessMs = expiryToMs(accessExpiresIn, 900_000);
    const expiresIn = Math.floor(accessMs / 1000);
    return {
      accessToken,
      refreshToken,
      expiresIn,
      user: { id: userId, email, role },
    };
  }
}
