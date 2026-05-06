# FocusFlow manual QA runbook

Use this after releases or risky changes. Automated checks: `node scripts/verify-repo.cjs` (repo root) and `cd backend && npm run verify:admin-api` (API must be running).

## Prerequisites

- Postgres running; `backend/.env` configured; `npm run db:migrate` / `db:deploy` as needed.
- Dev admin: `cd backend && npm run db:dev-admin` (default login: `dev-admin@focusflow.local` / `FocusFlow_Dev1!` — see script output if different).
- API: `cd backend && npm run start:dev` (or `node dist/main` after `npm run build`).
- Admin panel: `cd admin-panel && npm run dev` (default port **3001**). Copy `admin-panel/.env.example` → `.env.local`; use `NEXT_PUBLIC_API_URL=http://localhost:3000` and `API_URL_INTERNAL=http://localhost:3000` (see example comments for `/admin` suffix).

---

## A. Automated (run every time)

| Step | Command |
|------|---------|
| Full repo (no live server) | `node scripts/verify-repo.cjs` |
| Backend only CI | `cd backend && npm run verify:ci` |
| Live API smoke (public + admin GETs) | `cd backend && npm run verify:admin-api` |

`verify:admin-api` hits: `/health`, `/v1/health`, `/v1/ready`, `/v1/config/public`, then all major **GET** `/admin/*` routes the dashboard uses. It does **not** test POST/PUT/DELETE or the Next.js UI.

---

## B. Admin panel — page-by-page (browser)

Log in with your admin credentials. For each page: confirm load without error, main table/form visible, and one safe read-only action (sort, pagination) where applicable.

| Route | What to verify |
|-------|----------------|
| `/` (dashboard) | Stats, charts range control, alerts, live feed poll |
| `/users` | List loads; open one user detail; export CSV downloads (if offered) |
| `/tasks` | Analytics / heatmap / insights sections render |
| `/errors` | List, grouped view, alert config readable |
| `/flags` | Flag list loads |
| `/notifications` | History loads; **sending** push: only in staging with test device |
| `/content/categories` | List; create/edit/delete a **test** category in non-prod |
| `/content/sounds` | List; upload is optional (use tiny test file in dev only) |
| `/config` | Key/value editor loads |
| `/settings` | Integrations; admin invite / Slack / maintenance — use non-prod only |
| `/audit` | Recent events list |
| `/health` | System health / summary |
| `/login` | Logout and log back in |

---

## C. Backend — high-value manual checks

- **Auth**: Register/login (or Google) from mobile against `/v1/auth/*` if you changed auth.
- **Planner**: `PUT/GET` planner snapshots for a day; confirm mobile still syncs.
- **Notes / inbox**: Create note, list, optional voice path in dev.
- **AI coach**: `POST /v1/ai/chat` with LLM env set; expect 503-style handling when LLM off.
- **Admin mutations**: Ban/unban, resolve error, update flag — in **staging only** with disposable users.

---

## D. Mobile app (device or emulator)

- Cold start → login → timeline loads.
- Add task, reorder, complete; gentle nudges + **Android “Alarms & reminders”** if testing notifications.
- Inbox capture offline → comes back online → sync.
- Settings toggles (gentle nudges, appearance) persist after restart.

---

## E. Sign-off

- [ ] `node scripts/verify-repo.cjs` green  
- [ ] `npm run verify:admin-api` green against target API  
- [ ] Admin panel spot-check (section B) on staging  
- [ ] Mobile smoke (section D) on one Android + one iOS if shipping both  

Record build/version and tester name in your release notes.
