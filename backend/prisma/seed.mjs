/**
 * Optional dev seed: demo [TimelineSlot] rows for one UTC calendar day.
 *
 * Usage (from `backend/`):
 *   npx prisma db seed
 *
 * Picks the first user (by `createdAt`). Skips if that user already has slots that day.
 * Override day with env: `TIMELINE_SEED_ON=2026-04-18 npx prisma db seed`
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

function utcDayBounds(on) {
  const start = new Date(`${on}T00:00:00.000Z`);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);
  return { start, end };
}

async function main() {
  const on = process.env.TIMELINE_SEED_ON || new Date().toISOString().slice(0, 10);
  const user = await prisma.user.findFirst({ orderBy: { createdAt: 'asc' } });
  if (!user) {
    console.log('timeline seed: no users — register via POST /v1/auth/register first.');
    return;
  }
  const { start, end } = utcDayBounds(on);
  const existing = await prisma.timelineSlot.count({
    where: { userId: user.id, startsAt: { gte: start, lt: end } },
  });
  if (existing > 0) {
    console.log(`timeline seed: ${existing} slot(s) already exist for ${on} — skipping.`);
    return;
  }

  const blocks = [
    {
      startsAt: `${on}T09:00:00.000Z`,
      endsAt: `${on}T10:00:00.000Z`,
      title: 'Deep work — spec',
      iconKey: '📌',
      tag: 'Focus',
      soundLabel: 'Rain',
      status: 'ACTIVE',
      sortOrder: 0,
    },
    {
      startsAt: `${on}T10:30:00.000Z`,
      endsAt: `${on}T11:15:00.000Z`,
      title: 'Email + triage',
      iconKey: '✉️',
      tag: 'Admin',
      soundLabel: 'Lo-fi',
      status: 'UPCOMING',
      sortOrder: 1,
    },
    {
      startsAt: `${on}T13:00:00.000Z`,
      endsAt: `${on}T14:30:00.000Z`,
      title: 'Build timeline UI',
      iconKey: '🔨',
      tag: 'Build',
      soundLabel: 'White noise',
      status: 'UPCOMING',
      sortOrder: 2,
    },
  ];

  for (const b of blocks) {
    await prisma.timelineSlot.create({
      data: {
        userId: user.id,
        startsAt: new Date(b.startsAt),
        endsAt: new Date(b.endsAt),
        title: b.title,
        iconKey: b.iconKey,
        tag: b.tag,
        soundLabel: b.soundLabel,
        status: b.status,
        sortOrder: b.sortOrder,
      },
    });
  }
  console.log(`timeline seed: created ${blocks.length} demo slots for user ${user.id} on ${on} (UTC day).`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
