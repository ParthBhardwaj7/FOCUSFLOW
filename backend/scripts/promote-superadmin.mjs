/**
 * Promote an existing user to SUPERADMIN by email (dev / break-glass).
 *
 * From `backend/`:
 *   node scripts/promote-superadmin.mjs you@example.com
 *
 * PowerShell (no `&&`): run one line at a time, or:
 *   cd backend; npx prisma migrate deploy; npx prisma db seed
 */
import { PrismaClient } from '@prisma/client';

const email = (process.argv[2] ?? '').trim().toLowerCase();
if (!email) {
  console.error('Usage: node scripts/promote-superadmin.mjs <email>');
  process.exit(1);
}

const prisma = new PrismaClient();
try {
  const existing = await prisma.user.findUnique({
    where: { email },
    select: { id: true, email: true, role: true },
  });
  if (!existing) {
    const sample = await prisma.user.findMany({
      take: 15,
      orderBy: { createdAt: 'asc' },
      select: { email: true },
    });
    console.error(`No user with email: ${email}`);
    console.error(
      'Register in the app first (same DATABASE_URL as this script), then run again. Check spelling and domain (e.g. gmail.com vs email.com).',
    );
    if (sample.length) {
      console.error(`First ${sample.length} account(s) in this database:`);
      for (const row of sample) console.error(`  - ${row.email}`);
    } else {
      console.error('This database has zero users.');
    }
    process.exit(1);
  }

  const u = await prisma.user.update({
    where: { email },
    data: { role: 'SUPERADMIN' },
    select: { id: true, email: true, role: true },
  });
  console.log('Updated:', u);
} catch (e) {
  console.error(e);
  process.exit(1);
} finally {
  await prisma.$disconnect();
}
