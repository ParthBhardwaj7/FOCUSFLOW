/**
 * Jest e2e runs before the app module loads; ensure validated env exists
 * so `ConfigModule` + `validateEnv` succeed without a local `.env` file.
 */
process.env.NODE_ENV ??= 'test';
process.env.PORT ??= '3000';
process.env.LOG_LEVEL ??= 'silent';
process.env.DATABASE_URL ??=
  'postgresql://postgres:postgres@127.0.0.1:5432/focusflow?schema=public';
process.env.JWT_ACCESS_SECRET ??= 'x'.repeat(32);
process.env.JWT_REFRESH_SECRET ??= 'y'.repeat(32);
process.env.JWT_ACCESS_EXPIRES_IN ??= '15m';
process.env.JWT_REFRESH_EXPIRES_IN ??= '7d';
process.env.CORS_ORIGINS ??= 'http://localhost:3000';
process.env.COOKIE_DOMAIN ??= '';
process.env.COOKIE_SECURE ??= 'false';
process.env.THROTTLE_TTL ??= '60';
process.env.THROTTLE_LIMIT ??= '100';
