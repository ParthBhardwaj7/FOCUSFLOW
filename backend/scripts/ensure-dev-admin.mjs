/**
 * Creates or updates a local SUPERADMIN with known credentials (development only).
 *
 * Refuses when NODE_ENV=production unless FORCE_DEV_ADMIN_BOOTSTRAP=1.
 *
 * Defaults (override with env):
 *   DEV_ADMIN_EMAIL    dev-admin@focusflow.local
 *   DEV_ADMIN_PASSWORD FocusFlow_Dev1!   (≥12 chars for /admin/auth/login)
 *
 * Usage (from backend/):
 *   node scripts/ensure-dev-admin.mjs
 *   PowerShell: $env:DEV_ADMIN_PASSWORD='MyOwnLongPass123!'; node scripts/ensure-dev-admin.mjs
 */
import { PrismaClient } from '@prisma/client';
import argon2 from 'argon2';

const email = (process.env.DEV_ADMIN_EMAIL ?? 'dev-admin@focusflow.local')
  .trim()
  .toLowerCase();
const password = process.env.DEV_ADMIN_PASSWORD ?? 'FocusFlow_Dev1!';

if (password.length < 12) {
  console.error('DEV_ADMIN_PASSWORD must be at least 12 characters (admin login rule).');
  process.exit(1);
}

const isProd = process.env.NODE_ENV === 'production';
const forced = process.env.FORCE_DEV_ADMIN_BOOTSTRAP === '1';
if (isProd && !forced) {
  console.error(
    'Refusing: NODE_ENV=production. Set FORCE_DEV_ADMIN_BOOTSTRAP=1 if you really mean it.',
  );
  process.exit(1);
}

const prisma = new PrismaClient();
try {
  const passwordHash = await argon2.hash(password);
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    await prisma.user.update({
      where: { email },
      data: { passwordHash, role: 'SUPERADMIN' },
    });
    console.log('Updated existing user → SUPERADMIN:', email);
  } else {
    await prisma.user.create({
      data: {
        email,
        passwordHash,
        role: 'SUPERADMIN',
      },
    });
    console.log('Created SUPERADMIN:', email);
  }
  console.log('');
  console.log('── Admin panel login (dev) ─────────────────────────────');
  console.log('  Email:   ', email);
  console.log('  Password:', password);
  console.log('────────────────────────────────────────────────────────');
  console.log('Change password after first login in production.');
} catch (e) {
  console.error(e);
  process.exit(1);
} finally {
  await prisma.$disconnect();
}
