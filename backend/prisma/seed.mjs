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

/** Default feature flags + public app config for admin/mobile runtime (idempotent). */
async function seedAdminDefaults() {
  const flags = [
    {
      key: 'block_other_apps',
      isEnabled: false,
      rolloutPercentage: 0,
      description: 'Block other apps (coming soon)',
    },
    {
      key: 'ai_coach_enabled',
      isEnabled: true,
      rolloutPercentage: 100,
      description: 'AI coach chat',
    },
    {
      key: 'voice_input_enabled',
      isEnabled: false,
      rolloutPercentage: 0,
      description: 'Voice input',
    },
    {
      key: 'offline_mode',
      isEnabled: true,
      rolloutPercentage: 100,
      description: 'Offline-first planner',
    },
    {
      key: 'smart_capture_suggestions',
      isEnabled: true,
      rolloutPercentage: 100,
      description: 'Smart capture suggestions',
    },
    {
      key: 'sound_picker_enabled',
      isEnabled: true,
      rolloutPercentage: 100,
      description: 'Sound picker in add-task',
    },
  ];
  for (const f of flags) {
    await prisma.featureFlag.upsert({
      where: { key: f.key },
      create: {
        key: f.key,
        isEnabled: f.isEnabled,
        rolloutPercentage: f.rolloutPercentage,
        description: f.description,
      },
      update: {
        description: f.description,
      },
    });
  }
  const configs = [
    ['max_tasks_per_day', '20', 'Max tasks per calendar day', true],
    ['max_recording_seconds', '60', 'Max voice note seconds', false],
    ['ai_response_max_tokens', '300', 'AI max tokens', false],
    ['task_name_max_chars', '100', 'Task title max length', true],
    ['notes_max_chars', '500', 'Notes max length', true],
    ['default_task_duration', '25', 'Default block minutes', true],
    ['offline_sync_interval_s', '30', 'Client sync interval seconds', true],
    ['completion_threshold_low', '0.4', 'Low completion threshold', true],
    ['completion_threshold_high', '0.6', 'High completion threshold', true],
    ['onboarding_enabled', 'true', 'Show onboarding', true],
    ['maintenance_mode', 'false', 'Global maintenance gate', true],
  ];
  for (const [key, value, description, isPublic] of configs) {
    await prisma.appConfig.upsert({
      where: { key },
      create: { key, value, description, isPublic },
      update: { description, isPublic },
    });
  }
  await prisma.errorAlertConfig.upsert({
    where: { name: 'default' },
    create: {
      name: 'default',
      maxOccurrences: 10,
      windowMinutes: 60,
      isEnabled: true,
    },
    update: { maxOccurrences: 10, windowMinutes: 60 },
  });
  const insights = [
    { mood: 'POSITIVE', title: 'Great momentum', subtitle: 'You are finishing most of your blocks.', icon: '🎉' },
    { mood: 'NEUTRAL', title: 'Steady progress', subtitle: 'Small improvements add up—keep planning.', icon: '⚖️' },
    { mood: 'WARNING', title: 'Gentle reset', subtitle: 'Try one short block to rebuild rhythm.', icon: '🛡️' },
  ];
  for (const it of insights) {
    await prisma.aiInsightTemplate.upsert({
      where: { mood: it.mood },
      create: it,
      update: { title: it.title, subtitle: it.subtitle, icon: it.icon },
    });
  }
  console.log('admin defaults: feature flags, app config, error alert, AI insights (upserted).');
}

function utcDayBounds(on) {
  const start = new Date(`${on}T00:00:00.000Z`);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);
  return { start, end };
}

async function main() {
  await seedAdminDefaults().catch((e) => {
    console.warn('admin defaults seed skipped:', e?.message ?? e);
  });
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
