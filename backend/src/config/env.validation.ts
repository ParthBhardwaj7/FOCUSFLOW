import { z } from 'zod';

/**
 * Validates process.env at boot. ConfigModule passes the env record here.
 * Keep keys in sync with `.env.example`.
 */
const envSchema = z.object({
  NODE_ENV: z
    .enum(['development', 'production', 'test'])
    .default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  LOG_LEVEL: z
    .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
    .default('info'),

  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  SHADOW_DATABASE_URL: z.string().min(1).optional(),

  JWT_ACCESS_SECRET: z
    .string()
    .min(32, 'JWT_ACCESS_SECRET must be at least 32 characters'),
  JWT_REFRESH_SECRET: z
    .string()
    .min(32, 'JWT_REFRESH_SECRET must be at least 32 characters'),
  /** Parsed by `jsonwebtoken` / `expiryToMs` (suffix: ms|s|m|h|d). */
  JWT_ACCESS_EXPIRES_IN: z.string().default('365d'),
  JWT_REFRESH_EXPIRES_IN: z.string().default('36500d'),

  CORS_ORIGINS: z
    .string()
    .min(1, 'CORS_ORIGINS is required (comma-separated list)'),

  COOKIE_DOMAIN: z.string().optional(),
  COOKIE_SECURE: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),

  THROTTLE_TTL: z.coerce.number().int().positive().default(60),
  THROTTLE_LIMIT: z.coerce.number().int().positive().default(100),

  SENTRY_DSN: z.string().optional(),

  /** When unset, AI chat returns a clear “not configured” error. */
  LLM_PROVIDER: z.enum(['openrouter', 'groq', 'gemini']).optional(),
  LLM_API_KEY: z.string().min(1).optional(),
  LLM_MODEL: z.string().min(1).optional(),
  LLM_BASE_URL: z.string().url().optional(),
});

export type EnvVars = z.infer<typeof envSchema>;

function stripEmptyOptionalKeys(input: Record<string, unknown>): Record<string, unknown> {
  const out = { ...input };
  /** `.env` often has `KEY=` — Zod optional still receives `""` and fails `.min(1)` / `.url()`. */
  for (const key of [
    'LLM_PROVIDER',
    'LLM_API_KEY',
    'LLM_MODEL',
    'LLM_BASE_URL',
    'SHADOW_DATABASE_URL',
    'SENTRY_DSN',
    'COOKIE_DOMAIN',
  ]) {
    const v = out[key];
    if (typeof v === 'string' && v.trim() === '') {
      delete out[key];
    }
  }
  return out;
}

export function validateEnv(config: Record<string, unknown>): EnvVars {
  const parsed = envSchema.safeParse(stripEmptyOptionalKeys(config));
  if (!parsed.success) {
    console.error('Invalid environment variables:', parsed.error.issues);
    throw new Error('Invalid environment configuration');
  }
  const data = parsed.data;
  const sentry = data.SENTRY_DSN?.trim();
  if (!sentry) {
    return { ...data, SENTRY_DSN: undefined };
  }
  return { ...data, SENTRY_DSN: sentry };
}
