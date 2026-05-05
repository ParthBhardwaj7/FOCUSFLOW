# FocusFlow

FocusFlow is an execution-first productivity app built around one idea: reduce planning friction and help users start the next meaningful action quickly.

This repository is a monorepo with:
- a Flutter mobile app (`mobile`)
- a NestJS backend API (`backend`)
- a Next.js admin panel (`admin-panel`)

---

## What FocusFlow Includes

- Timeline-first planning with offline local storage
- Inbox capture (notes + voice)
- Focus and deep-focus sessions
- AI coach surface in the mobile app
- Local + scheduled notifications
- Admin notifications and configuration panel

---

## Repository Structure

```text
FOCUSFLOW/
├─ mobile/        # Flutter app (Riverpod, local-first UX)
├─ backend/       # NestJS API + Prisma
├─ admin-panel/   # Next.js admin console
└─ README.md
```

For module-level details, see:
- `FOCUSFLOW_MASTER.md` — product + technical spec (scope, TZ rules, roadmap)
- `mobile/README.md`
- `backend/README.md`
- `admin-panel/README.md`

---

## Prerequisites

- Node.js 20+
- npm 10+
- Flutter 3.24+ (Dart 3.5+)
- Android Studio / Xcode (for mobile builds)
- PostgreSQL (for backend)

---

## Quick Start (Local Development)

### 1) Backend

```bash
cd backend
npm install
```

Create `backend/.env` from `backend/.env.example`, then:

```bash
npm run start:dev
```

By default, backend runs at `http://localhost:3000`.

### 2) Mobile App

```bash
cd mobile
flutter pub get
```

Create `mobile/.env` from `mobile/.env.example`.

Minimum required values:
- `API_BASE_URL`
- `GOOGLE_WEB_CLIENT_ID` (if testing Google Sign-In)

Then run:

```bash
flutter run
```

### 3) Admin Panel

```bash
cd admin-panel
npm install
npm run dev
```

---

## Environment Notes

- `mobile/.env` is required for real-device testing.
- `backend/.env` must include DB + auth secrets before API startup.
- Push delivery requires backend FCM key configuration.

---

## Common Dev Commands

### Mobile

```bash
flutter analyze
flutter test
```

### Backend

```bash
npm run lint
npm run build
npm run test
```

### Admin Panel

```bash
npm run lint
npm run build
```

---

## Development Principles

- Keep user-facing behavior predictable and resilient offline.
- Prefer clear user-facing errors over technical/internal messages.
- Follow existing Riverpod and feature-module boundaries.
- Avoid mixing unrelated fixes in a single change.

---

## Status

FocusFlow is under active development.  
If you are onboarding, start with the backend and mobile READMEs first, then return here for full-repo context.
