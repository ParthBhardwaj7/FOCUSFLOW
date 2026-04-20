/**
 * Mint an access JWT identical in shape to POST /v1/auth/login (for Postman / curl).
 *
 * Usage (from backend/):
 *   node scripts/sign-access-token.cjs <userSub> <email>
 *
 * Example — use the `user.id` from register/login JSON:
 *   node scripts/sign-access-token.cjs clxxxxxxxxxxxxxxxxxx you@example.com
 */
const fs = require('fs');
const path = require('path');
const jwt = require('jsonwebtoken');

function loadEnv(filePath) {
  const out = {};
  const raw = fs.readFileSync(filePath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq < 1) continue;
    const key = t.slice(0, eq).trim();
    let val = t.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return out;
}

const sub = process.argv[2];
const email = process.argv[3];
if (!sub || !email) {
  console.error('Usage: node scripts/sign-access-token.cjs <userId_sub> <email>');
  process.exit(1);
}

const envPath = path.resolve(__dirname, '..', '.env');
const env = loadEnv(envPath);
const secret = env.JWT_ACCESS_SECRET;
const expiresIn = env.JWT_ACCESS_EXPIRES_IN || '365d';
if (!secret || secret.length < 32) {
  console.error('JWT_ACCESS_SECRET missing or < 32 chars in .env');
  process.exit(1);
}

const token = jwt.sign({ sub, email }, secret, { expiresIn });
console.log(token);
