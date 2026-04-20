# FocusFlow API (backend)

Production-oriented **NestJS 11** API with **PostgreSQL**, **Prisma 6** (ORM + migrations), validated configuration, structured logging (**Pino**), and consistent JSON errors for client UX.

## Prerequisites

- **Node.js** 20+ (LTS recommended)
- **npm** (or swap commands for pnpm/yarn)
- **PostgreSQL 16** locally — easiest via Docker: `docker compose up -d` from this folder (requires Docker Desktop / engine running)

## Quick start

```bash
cd backend
cp .env.example .env
# Edit .env — at minimum DATABASE_URL and JWT secrets (32+ chars each)

# Install
npm install

# Generate Prisma Client
npm run db:generate

# Start Postgres (optional if you use a hosted DB)
docker compose up -d

# Apply migrations (creates tables)
npm run db:migrate
# Production / CI: npm run db:deploy

# Dev server (http://localhost:3000 by default)
npm run start:dev
```

**If the Flutter app says it cannot reach the server:** confirm this process is running and `Invoke-WebRequest http://localhost:3000/v1/health` returns `200` (PowerShell). Without Postgres, `start:dev` will crash on boot — run `docker compose up -d` first.

**Register smoke test (PowerShell, with server up):**

```powershell
Invoke-RestMethod -Uri http://localhost:3000/v1/auth/register -Method Post -ContentType "application/json" -Body '{"email":"smoke@example.com","password":"password123"}'
```

Expect JSON with `accessToken`, `refreshToken`, and `user`. `409` means the email already exists.

### Dev: mint a valid access JWT (Postman)

Tokens must match **`JWT_ACCESS_SECRET`** and payload **`{ sub, email }`** (same as login).

1. Copy **`user.id`** from register/login response (the `sub` claim).
2. From `backend/`:

```bash
npm run token:dev -- <userId> <email>
```

Example:

```bash
npm run token:dev -- clxxxxxxxxxxxxxxxxxxxxxx you@example.com
```

It prints one line: paste as `Authorization: Bearer <token>` for `/v1/me` etc.

### Health checks (versioned API)

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/v1/health` | Liveness — process up |
| `GET` | `/v1/ready` | Readiness — database `SELECT 1` |

Every response includes an **`x-request-id`** header (echoed if the client sends `x-request-id`).

### API v1 (MVP)

Unless noted, routes require header `Authorization: Bearer <accessToken>`. Auth routes are public.

| Method | Path | Body / query | Notes |
|--------|------|----------------|--------|
| `POST` | `/v1/auth/register` | `{ "email", "password" }` | Returns `accessToken`, `refreshToken`, `expiresIn`, `user` |
| `POST` | `/v1/auth/login` | `{ "email", "password" }` | Same shape as register |
| `POST` | `/v1/auth/refresh` | `{ "refreshToken" }` | Rotates refresh token |
| `POST` | `/v1/auth/logout` | `{ "refreshToken" }` | Revokes refresh token |
| `GET` | `/v1/me` | — | Current user (no `passwordHash`) |
| `PATCH` | `/v1/me` | `{ "onboardingCompletedAt"?, "timeZone"? }` | ISO date-time string for onboarding |
| `GET` | `/v1/tasks` | `?on=YYYY-MM-DD` | Tasks for calendar day (UTC midnight MVP) |
| `POST` | `/v1/tasks` | `{ "title", "notes"?, "scheduledOn", "sortOrder"?, "isMit"? }` | `scheduledOn` must match `YYYY-MM-DD` |
| `PATCH` | `/v1/tasks/:id` | partial fields | Owner-only |
| `DELETE` | `/v1/tasks/:id` | — | Owner-only |
| `POST` | `/v1/focus-sessions` | `{ "taskId"?, "plannedDurationSec", "subtasksSnapshot"? }` | Starts `PENDING` session |
| `PATCH` | `/v1/focus-sessions/:id` | `{ "outcome": "COMPLETED" \| "SKIPPED" }` | Sets `endedAt` |
| `GET` | `/v1/timeline` | `?on=YYYY-MM-DD` | Timeline slots for that **UTC** calendar day (`startsAt` in `[onT00:00Z, nextDay)`), ordered by time |
| `POST` | `/v1/timeline` | `{ "startsAt", "endsAt", "title", "iconKey"?, "tag"?, "soundLabel"?, "status"?, "linkedTaskId"?, "sortOrder"? }` | ISO 8601 for `startsAt` / `endsAt`; `status` ∈ `UPCOMING` \| `ACTIVE` \| `DONE` \| `MISSED` \| `SKIPPED` |
| `PATCH` | `/v1/timeline/:id` | partial same fields | Owner-only |
| `DELETE` | `/v1/timeline/:id` | — | Owner-only |

**Migrations:** apply [`prisma/migrations/20260419180000_mvp_domain`](./prisma/migrations/20260419180000_mvp_domain/migration.sql) after the initial `User` table migration. It clears legacy `User` rows (dev-oriented); do not run against production data without a tailored migration. Then apply [`prisma/migrations/20260420120000_timeline_slots`](./prisma/migrations/20260420120000_timeline_slots/migration.sql) for `TimelineSlot`.

### Optional demo timeline seed

After at least one user exists, from `backend/`:

```bash
npx prisma db seed
```

Uses **today’s UTC date** by default, or set `TIMELINE_SEED_ON=2026-04-18`. Skips if that user already has slots that day.

## Scripts

| Script | Description |
|--------|-------------|
| `npm run start:dev` | Watch mode |
| `npm run build` | Compile to `dist/` |
| `npm run start:prod` | Run compiled app |
| `npm run lint` | ESLint |
| `npm run test` | Unit tests (passes with no tests yet) |
| `npm run test:e2e` | E2e smoke (uses mocked Prisma; no DB required) |
| `npm run db:generate` | `prisma generate` |
| `npm run db:migrate` | `prisma migrate dev` |
| `npm run db:deploy` | `prisma migrate deploy` |
| `npm run db:studio` | Prisma Studio |
| `npm run db:validate` | Validate `schema.prisma` |
| `npx prisma db seed` | Optional demo `TimelineSlot` rows (see above) |

## Environment variables

Copy [`.env.example`](./.env.example) to `.env`. Never commit `.env`.

| Variable | Required | Description |
|----------|----------|-------------|
| `NODE_ENV` | No | `development` (default), `production`, or `test` |
| `PORT` | No | HTTP port (default `3000`) |
| `LOG_LEVEL` | No | Pino level: `fatal` … `trace` / `silent` (default `info`) |
| `DATABASE_URL` | Yes | Prisma PostgreSQL URL |
| `SHADOW_DATABASE_URL` | No | Only if your host requires a shadow DB for migrations |
| `JWT_ACCESS_SECRET` | Yes | Min **32** characters; access token signing |
| `JWT_REFRESH_SECRET` | Yes | Min **32** characters; refresh token signing |
| `JWT_ACCESS_EXPIRES_IN` | No | Default `15m` |
| `JWT_REFRESH_EXPIRES_IN` | No | Default `7d` |
| `CORS_ORIGINS` | Yes | Comma-separated allowed origins (no spaces) |
| `COOKIE_DOMAIN` | No | Cookie domain when refresh cookies are added |
| `COOKIE_SECURE` | No | `true` / `false` — use `true` in production with HTTPS |
| `THROTTLE_TTL` | No | Rate-limit window in **seconds** (default `60`) |
| `THROTTLE_LIMIT` | No | Max requests per window per IP (default `100`) |
| `SENTRY_DSN` | No | Optional error reporting |

Validation runs at boot via **Zod** in [`src/config/env.validation.ts`](./src/config/env.validation.ts); invalid env fails fast with a clear console error.

## Project layout

```text
src/
  main.ts                 # Bootstrap + fatal error exit
  bootstrap.ts            # Helmet, CORS, compression, cookie-parser, URI versioning
  app.module.ts           # Config, Pino, Throttler, Prisma, global pipe/filter/guard
  config/                 # Zod env validation
  common/                 # Exception filter, request-id interceptor
  prisma/                 # PrismaService + global PrismaModule
  modules/                # health, auth, users (me), tasks, focus-sessions
prisma/
  schema.prisma
  migrations/
```

## API UX conventions (server-side)

- **Validation:** global `ValidationPipe` — `whitelist`, `forbidNonWhitelisted`, `transform`; failed DTO validation returns **422** with a stable error shape from the global filter.
- **Errors:** JSON body includes `statusCode`, `message`, `code`, `path`, `requestId`, optional `details`.
- **Versioning:** URI version prefix **`/v1`** (add `v2` later without breaking clients).
- **Security:** **Helmet**, global **throttling** (health/ready routes use `@SkipThrottle()`).

## Prisma version

This repo pins **Prisma 6.x** (`prisma` / `@prisma/client`) because **Prisma 7** changes how datasource URLs are configured. Upgrade deliberately using Prisma’s migration guide when you are ready.

## Docker Compose (local Postgres)

[`docker-compose.yml`](./docker-compose.yml) runs `postgres:16-alpine` with user **`postgres`**, password **`mypassword123`** (same as `.env.example`), db **`focusflow`**, port **5432**. If you change the password in compose, update `DATABASE_URL` and recreate the volume: `docker compose down -v && docker compose up -d`.

## Testing notes

- **E2e** ([`test/app.e2e-spec.ts`](./test/app.e2e-spec.ts)) overrides `PrismaService` so CI does not need a database. For a **true** readiness check, hit `/v1/ready` against a running API with real Postgres after `npm run db:migrate`.
- **Unit:** add `*.spec.ts` next to services as features grow; `npm test` uses `--passWithNoTests` until then.

## Related repo docs

Product scope and client tracks: [`../FOCUSFLOW_MASTER.md`](../FOCUSFLOW_MASTER.md).
