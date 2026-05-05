import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { SignOptions } from 'jsonwebtoken';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';
import { OAuth2Client } from 'google-auth-library';
import { RefreshTokenScope } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { expiryToMs } from '../../common/utils/expiry-ms';
import { hashRefreshToken } from '../../common/utils/refresh-token-hash';
import type { AccessTokenPayload } from './strategies/jwt.strategy';

function isSuspended(user: { isBanned: boolean; banExpiresAt: Date | null }) {
  return (
    user.isBanned && (!user.banExpiresAt || user.banExpiresAt > new Date())
  );
}

@Injectable()
export class AuthService {
  private readonly googleOAuth = new OAuth2Client();

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async register(email: string, password: string) {
    const normalized = email.trim().toLowerCase();
    const existing = await this.prisma.user.findUnique({
      where: { email: normalized },
    });
    if (existing) {
      throw new ConflictException('Email already registered');
    }
    const passwordHash = await argon2.hash(password);
    const user = await this.prisma.user.create({
      data: { email: normalized, passwordHash },
    });
    return this.issueFreshSession(user.id, user.email);
  }

  async login(email: string, password: string) {
    const normalized = email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({
      where: { email: normalized },
    });
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }
    if (isSuspended(user)) {
      throw new UnauthorizedException('Account suspended');
    }
    const ok = await argon2.verify(user.passwordHash, password);
    if (!ok) {
      throw new UnauthorizedException('Invalid credentials');
    }
    return this.issueFreshSession(user.id, user.email);
  }

  async loginWithGoogleIdToken(idToken: string) {
    const audience = this.config
      .getOrThrow<string>('GOOGLE_AUTH_CLIENT_IDS')
      .split(',')
      .map((v) => v.trim())
      .filter((v) => v.length > 0);
    if (audience.length === 0) {
      throw new UnauthorizedException('Google auth is not configured');
    }

    let payload:
      | {
          email?: string;
          email_verified?: boolean;
        }
      | undefined;
    try {
      const ticket = await this.googleOAuth.verifyIdToken({ idToken, audience });
      payload = ticket.getPayload();
    } catch {
      throw new UnauthorizedException('Invalid Google ID token');
    }
    const email = payload?.email?.trim().toLowerCase();
    const emailVerified = payload?.email_verified === true;
    if (!email || !emailVerified) {
      throw new UnauthorizedException('Google account email not verified');
    }

    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) {
      if (isSuspended(existing)) {
        throw new UnauthorizedException('Account suspended');
      }
      return this.issueFreshSession(existing.id, existing.email);
    }

    const passwordHash = await argon2.hash(randomBytes(24).toString('base64url'));
    const user = await this.prisma.user.create({
      data: {
        email,
        emailVerifiedAt: new Date(),
        passwordHash,
      },
    });
    return this.issueFreshSession(user.id, user.email);
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
      row.scope !== RefreshTokenScope.USER
    ) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
    const user = await this.prisma.user.findUnique({
      where: { id: row.userId },
    });
    if (!user || isSuspended(user)) {
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
        scope: RefreshTokenScope.USER,
      },
    });

    await this.prisma.refreshToken.update({
      where: { id: row.id },
      data: { revokedAt: new Date(), replacedBy: newRow.id },
    });

    return this.buildAccessResponse(user.id, user.email, rawRefresh);
  }

  async logout(refreshTokenRaw: string) {
    const tokenHash = hashRefreshToken(refreshTokenRaw);
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  }

  private async issueFreshSession(userId: string, email: string) {
    const refreshExpiresIn = this.config.getOrThrow<string>(
      'JWT_REFRESH_EXPIRES_IN',
    );
    const refreshMs = expiryToMs(refreshExpiresIn, 7 * 86_400_000);
    const expiresAt = new Date(Date.now() + refreshMs);
    const rawRefresh = randomBytes(48).toString('base64url');
    const tokenHash = hashRefreshToken(rawRefresh);
    await this.prisma.refreshToken.create({
      data: { userId, tokenHash, expiresAt, scope: RefreshTokenScope.USER },
    });
    return this.buildAccessResponse(userId, email, rawRefresh);
  }

  private async buildAccessResponse(
    userId: string,
    email: string,
    refreshToken: string,
  ) {
    const accessSecret = this.config.getOrThrow<string>('JWT_ACCESS_SECRET');
    const accessExpiresIn = this.config.getOrThrow<string>(
      'JWT_ACCESS_EXPIRES_IN',
    );
    const payload: AccessTokenPayload = { sub: userId, email };
    const accessToken = await this.jwt.signAsync(payload, {
      secret: accessSecret,
      expiresIn: accessExpiresIn as SignOptions['expiresIn'],
    });
    const accessMs = expiryToMs(accessExpiresIn, 900_000);
    const expiresIn = Math.floor(accessMs / 1000);

    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        onboardingCompletedAt: true,
        timeZone: true,
        profileSummary: true,
        createdAt: true,
      },
    });

    return {
      accessToken,
      refreshToken,
      expiresIn,
      user,
    };
  }
}
