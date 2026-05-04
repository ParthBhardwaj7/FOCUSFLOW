/**
 * Smoke-test Nest admin routes (same paths the Next admin panel uses).
 *
 * From backend/ (server should be running on API_ORIGIN, default http://localhost:3000):
 *   node scripts/verify-admin-endpoints.mjs
 *
 * Env:
 *   API_ORIGIN=http://localhost:3000
 *   DEV_ADMIN_EMAIL=dev-admin@focusflow.local
 *   DEV_ADMIN_PASSWORD=FocusFlow_Dev1!
 *
 * Covers GET routes used by the Next admin panel. Mutations (POST/PATCH/PUT) are not
 * exercised here; test those manually or extend this script with disposable fixtures.
 */
const origin = (process.env.API_ORIGIN ?? 'http://localhost:3000').replace(/\/+$/, '');
const email = (process.env.DEV_ADMIN_EMAIL ?? 'dev-admin@focusflow.local').trim().toLowerCase();
const password = process.env.DEV_ADMIN_PASSWORD ?? 'FocusFlow_Dev1!';

async function login() {
  const res = await fetch(`${origin}/admin/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Login ${res.status}: ${t.slice(0, 200)}`);
  }
  const data = await res.json();
  return data.accessToken;
}

async function get(token, path, init = {}) {
  const res = await fetch(`${origin}${path}`, {
    ...init,
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${token}`,
      ...init.headers,
    },
  });
  return { ok: res.ok, status: res.status, path };
}

async function main() {
  let token;
  try {
    token = await login();
  } catch (e) {
    console.error(String(e));
    console.error('\nTip: run `npm run db:dev-admin` then start the API (`npm run start:dev`).');
    process.exit(1);
  }

  const checks = [
    ['GET', '/admin/dashboard/stats'],
    ['GET', '/admin/dashboard/charts?range=30d'],
    ['GET', '/admin/dashboard/alerts'],
    ['GET', '/admin/dashboard/live-feed/poll'],
    ['GET', '/admin/users?page=1&limit=5'],
    ['GET', '/admin/users/export'],
    ['GET', '/admin/errors?limit=5'],
    ['GET', '/admin/errors/grouped'],
    ['GET', '/admin/errors/alert-config'],
    ['GET', '/admin/flags'],
    ['GET', '/admin/tasks/analytics'],
    ['GET', '/admin/tasks/heatmap'],
    ['GET', '/admin/tasks/insights'],
    ['GET', '/admin/tasks?limit=5'],
    ['GET', '/admin/categories'],
    ['GET', '/admin/sounds'],
    ['GET', '/admin/ai-suggestions'],
    ['GET', '/admin/ai-insights'],
    ['GET', '/admin/notifications/history'],
    ['GET', '/admin/config'],
    ['GET', '/admin/audit?limit=10'],
    ['GET', '/admin/settings/integrations'],
  ];

  const rows = [];
  for (const [, path] of checks) {
    const r = await get(token, path);
    rows.push({ path, ...r });
  }

  const firstUser = await fetch(`${origin}/admin/users?page=1&limit=1`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (firstUser.ok) {
    const body = await firstUser.json();
    const id = body?.items?.[0]?.id;
    if (id) {
      const detail = await get(token, `/admin/users/${id}`);
      rows.push({ path: `/admin/users/:id (${id})`, ...detail });
    }
  }

  let fail = 0;
  for (const r of rows) {
    const mark = r.ok ? 'OK ' : 'FAIL';
    if (!r.ok) fail++;
    console.log(`${mark} ${r.status}\t${r.path}`);
  }
  console.log('');
  if (fail) {
    console.error(`${fail} request(s) failed.`);
    process.exit(1);
  }
  console.log(`All ${rows.length} checks passed.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
