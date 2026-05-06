import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { SignOptions } from 'jsonwebtoken';
import * as argon2 from 'argon2';
import { createHash, randomBytes, randomInt } from 'node:crypto';
import * as nodemailer from 'nodemailer';
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
  private readonly logger = new Logger(AuthService.name);
  private static readonly RESET_CODE_DIGITS = 6;
  private static readonly RESET_CODE_MAX_ATTEMPTS = 5;
  private smtpTransporter?: nodemailer.Transporter;

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

  private async verifyGoogleAccessToken(accessToken: string) {
    const res = await fetch(
      `https://www.googleapis.com/oauth2/v3/userinfo?access_token=${encodeURIComponent(accessToken)}`,
    );
    if (!res.ok) {
      throw new UnauthorizedException('Invalid Google access token');
    }
    const data = (await res.json()) as {
      email?: string;
      email_verified?: boolean;
    };
    return {
      email: data.email?.trim().toLowerCase(),
      emailVerified: data.email_verified === true,
    };
  }

  async loginWithGoogleTokens(idToken: string, accessToken?: string) {
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
      const ticket = await this.googleOAuth.verifyIdToken({
        idToken,
        audience,
      });
      payload = ticket.getPayload();
    } catch {
      if (!accessToken || accessToken.trim().length == 0) {
        throw new UnauthorizedException('Invalid Google ID token');
      }
      const fallback = await this.verifyGoogleAccessToken(accessToken.trim());
      payload = {
        email: fallback.email,
        email_verified: fallback.emailVerified,
      };
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

    const passwordHash = await argon2.hash(
      randomBytes(24).toString('base64url'),
    );
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

  async requestPasswordResetCode(email: string) {
    const normalized = email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({
      where: { email: normalized },
      select: { id: true, email: true, isBanned: true, banExpiresAt: true },
    });

    // Avoid user enumeration: always return the same success shape.

    if (!user || isSuspended(user)) {
      return { ok: true };
    }

    const now = new Date();
    const ttlMinutes = this.config.get<number>('PASSWORD_RESET_CODE_TTL_MINUTES') ?? 10;
    const expiresAt = new Date(now.getTime() + ttlMinutes * 60_000);
    const otpCode = this.generateResetCode();
    const codeHash = this.hashResetCode(user.id, otpCode);

    await this.prisma.$transaction([
      this.prisma.passwordResetOtp.updateMany({
        where: {
          userId: user.id,
          usedAt: null,
          expiresAt: { gt: now },
        },
        data: { usedAt: now },
      }),
      this.prisma.passwordResetOtp.create({
        data: {
          userId: user.id,
          codeHash,
          expiresAt,
        },
      }),
    ]);

    await this.queuePasswordResetCodeDelivery(user.email, otpCode, expiresAt);
    return { ok: true };
  }

  async resetPasswordWithCode(email: string, code: string, newPassword: string) {
    const normalized = email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({
      where: { email: normalized },
      select: { id: true },
    });
    if (!user) {
      throw new UnauthorizedException('Invalid or expired reset code');
    }

    const now = new Date();
    const row = await this.prisma.passwordResetOtp.findFirst({
      where: {
        userId: user.id,
        usedAt: null,
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!row || row.expiresAt <= now) {
      throw new UnauthorizedException('Invalid or expired reset code');
    }

    if (row.attempts >= AuthService.RESET_CODE_MAX_ATTEMPTS) {
      await this.prisma.passwordResetOtp.update({
        where: { id: row.id },
        data: { usedAt: now },
      });
      throw new UnauthorizedException('Invalid or expired reset code');
    }

    const expectedHash = this.hashResetCode(user.id, code);
    if (expectedHash !== row.codeHash) {
      const nextAttempts = row.attempts + 1;
      await this.prisma.passwordResetOtp.update({
        where: { id: row.id },
        data: {
          attempts: nextAttempts,
          usedAt:
            nextAttempts >= AuthService.RESET_CODE_MAX_ATTEMPTS ? now : null,
        },
      });
      throw new UnauthorizedException('Invalid or expired reset code');
    }

    const passwordHash = await argon2.hash(newPassword);
    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: user.id },
        data: { passwordHash },
      }),
      this.prisma.passwordResetOtp.updateMany({
        where: { userId: user.id, usedAt: null },
        data: { usedAt: now },
      }),
      this.prisma.refreshToken.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt: now },
      }),
    ]);

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

  private generateResetCode(): string {
    const max = 10 ** AuthService.RESET_CODE_DIGITS;
    return randomInt(0, max)
      .toString()
      .padStart(AuthService.RESET_CODE_DIGITS, '0');
  }

  private hashResetCode(userId: string, code: string): string {
    const pepper = this.config.getOrThrow<string>('JWT_ACCESS_SECRET');
    return createHash('sha256')
      .update(`${userId}:${code}:${pepper}`, 'utf8')
      .digest('hex');
  }

  private async queuePasswordResetCodeDelivery(
    email: string,
    code: string,
    expiresAt: Date,
  ) {
    const host = this.config.get<string>('SMTP_HOST')?.trim();
    const portRaw = this.config.get<string>('SMTP_PORT')?.trim();
    const user = this.config.get<string>('SMTP_USER')?.trim();
    const pass = this.config.get<string>('SMTP_PASS')?.trim();
    const from = this.config.get<string>('SMTP_FROM_EMAIL')?.trim();
    if (!host || !portRaw || !user || !pass || !from) {
      this.logger.error(
        `SMTP is not fully configured, cannot deliver password reset OTP email to ${email}.`,
      );
      return;
    }

    const port = Number(portRaw);
    if (!Number.isFinite(port) || port <= 0) {
      this.logger.error('SMTP_PORT is invalid. Password reset OTP email not sent.');
      return;
    }

    const secure = this.config.get<string>('SMTP_SECURE') === 'true';
    const transporter = this.getOrCreateSmtpTransporter({
      host,
      port,
      secure,
      user,
      pass,
    });
    const expiresAtLocal = expiresAt.toLocaleString('en-US', {
      hour12: true,
      timeZone: 'UTC',
      timeZoneName: 'short',
    });
    const html = `
      <div style="font-family: Arial, sans-serif; line-height: 1.5; color: #111827;">
        <h2 style="margin-bottom: 8px;">FocusFlow Password Reset</h2>
        <p>Your one-time verification code is:</p>
        <p style="font-size: 28px; font-weight: 700; letter-spacing: 6px; margin: 12px 0;">${code}</p>
        <p>This code expires at <strong>${expiresAtLocal}</strong>.</p>
        <p>If you did not request this, please ignore this email.</p>
      </div>
    `;
    const text = [
      'FocusFlow Password Reset',
      '',
      `Your one-time verification code is: ${code}`,
      `This code expires at ${expiresAt.toISOString()} UTC.`,
      '',
      'If you did not request this, please ignore this email.',
    ].join('\n');

    try {
      await transporter.sendMail({
        from,
        to: email,
        subject: 'FocusFlow password reset code',
        text,
        html,
      });
      this.logger.log(
        `Password reset OTP email sent to ${email} (expiresAt=${expiresAt.toISOString()})`,
      );
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      this.logger.error(
        `Failed to send password reset OTP email to ${email}: ${msg}`,
      );
    }
  }

  private getOrCreateSmtpTransporter(input: {
    host: string;
    port: number;
    secure: boolean;
    user: string;
    pass: string;
  }): nodemailer.Transporter {
    if (this.smtpTransporter) return this.smtpTransporter;
    this.smtpTransporter = nodemailer.createTransport({
      host: input.host,
      port: input.port,
      secure: input.secure,
      auth: {
        user: input.user,
        pass: input.pass,
      },
    });
    return this.smtpTransporter;
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
