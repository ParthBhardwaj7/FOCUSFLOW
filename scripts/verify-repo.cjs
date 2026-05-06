#!/usr/bin/env node
/**
 * Run automated checks across backend, admin-panel, and mobile (no live API).
 *
 * Usage (from repo root):
 *   node scripts/verify-repo.cjs
 *
 * For API + admin GET smoke tests (requires running Postgres + API):
 *   cd backend && npm run verify:admin-api
 */
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..');

function run(label, command, args, cwd) {
  console.log(`\n======== ${label} ========\n`);
  const r = spawnSync(command, args, {
    cwd,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  if (r.status !== 0) {
    console.error(`\nFAILED: ${label} (exit ${r.status ?? 'unknown'})\n`);
    process.exit(r.status ?? 1);
  }
}

run('Backend verify:ci', 'npm', ['run', 'verify:ci'], path.join(root, 'backend'));
run('Admin panel lint', 'npm', ['run', 'lint'], path.join(root, 'admin-panel'));
run('Admin panel build', 'npm', ['run', 'build'], path.join(root, 'admin-panel'));
run('Flutter analyze', 'flutter', ['analyze'], path.join(root, 'mobile'));
run('Flutter test', 'flutter', ['test'], path.join(root, 'mobile'));

console.log('\n======== All verify-repo steps passed ========\n');
console.log(
  'Next (optional): start API + DB, then: cd backend && npm run verify:admin-api\n',
);
