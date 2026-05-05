# FocusFlow master spec

Canonical **product + technical** overview for contributors. The repo README remains the onboarding entrypoint; use this document for detailed scope and decisions.

See also repository [`README.md`](README.md): client layout [`mobile/README.md`](mobile/README.md), API [`backend/README.md`](backend/README.md), operations [`admin-panel/README.md`](admin-panel/README.md).

---

## Out of scope (current phase)

Treat these as **separate initiatives** unless explicitly pulled into a milestone:

- **Apple / iOS / iPad / Watch** — not part of the current Android-first MVP in this repo.
- **End-user web or desktop clients** — only the **admin** Next.js panel is in scope.
- **Deep audio / foreground-service policy** — focus audio stack and Play policy for long media sessions are handled on a dedicated pass (not blocking other release items).

---

## Product thesis

FocusFlow is **execution-first productivity**: reduce planning friction and help the user start the **next meaningful action** quickly. The primary loop is **capture → place on the day timeline → focus session → lightweight reflection/coach**.

---

## Monorepo map

| Path | Purpose |
|---|---|
| [`mobile`](mobile/) | Flutter client (**Android MVP**): Riverpod, go_router, local-first timeline + Nest API. |
| [`backend`](backend/) | NestJS 11 API, Prisma + PostgreSQL, `/v1` JSON API. |
| [`admin-panel`](admin-panel/) | Next.js: users, flags, app config, push, errors, audit, content (sounds/categories). |

---

## Client behavior (Flutter)

### Shell and routes

Authenticated shell tabs: **Inbox**, **Now** (timeline), **AI**, **Settings**; plus **Day 0** onboarding, **Add task**, **Focus** / **Deep focus**, inbox note editor, recordings, nested settings (**Focus profile**, **Coach context**). Implementation: [`mobile/lib/router.dart`](mobile/lib/router.dart).

### Offline-first planner

Timeline data lives in **on-device SQLite** and syncs with the backend via **`PlannerDaySnapshot`** (debounced upload + range pull). Coordinator: [`mobile/lib/core/planner_cloud_sync.dart`](mobile/lib/core/planner_cloud_sync.dart).

### Auth and session

Tokens in **secure storage**; cold start does **not** clear tokens on network errors; logout on **401/403** after refresh failure. See [`mobile/README.md`](mobile/README.md).

### Capture

Inbox (notes + voice capture paths), upload to `/v1/notes` and `/v1/recordings/upload` as implemented in [`mobile/lib/core/session/focusflow_client.dart`](mobile/lib/core/session/focusflow_client.dart).

### Focus

Focus sessions via `/v1/focus-sessions`; deep-focus UI and local audio handler exist (audio/FGS release hardening is out of scope for the phase above).

### AI

Chat and memory ingest: `/v1/ai/chat`, `/v1/ai/memory/ingest`. Runtime **public config** and **feature flags** sync when online: [`mobile/lib/core/runtime_remote_sync.dart`](mobile/lib/core/runtime_remote_sync.dart).

### Notifications (Android)

**Gentle nudges** schedule local notifications from the SQLite timeline. **POST_NOTIFICATIONS** is declared in the manifest; the app requests OS permission when gentle nudges are enabled and on cold start if that preference is on. Release builds use **no cleartext HTTP** by default; **debug** builds allow cleartext for local API development. Details: [`mobile/docs/PLAY_INTERNAL_CHECKLIST.md`](mobile/docs/PLAY_INTERNAL_CHECKLIST.md).

### Calendar day and time zones

- The **week strip** and **selected day** use **`YYYY-MM-DD` in the device’s local calendar**.
- The mobile app **syncs the device IANA time zone** to `User.timeZone` on the server (`PATCH /v1/me`) so server-side day queries can match the user’s wall calendar when applicable.
- **`GET /v1/timeline?on=YYYY-MM-DD`**: if `User.timeZone` is set and valid, `on` is interpreted as a **local calendar day in that zone**; otherwise the server uses **UTC calendar day** (legacy). Prefer **planner snapshots** for the shipped client’s source of truth; `listTimeline` remains for tools and compatibility.
- **Tasks** (`GET /v1/tasks?on=`) still use **UTC calendar-day** semantics for `scheduledOn` in the current API — see backend README; alignment with user TZ is a possible follow-up.

---

## Backend domain (summary)

Prisma models include `User`, `Task`, `TimelineSlot`, `PlannerDaySnapshot`, `FocusSession`, `Note`, `UserMemory`, push and AI logging, admin tables, `UserPlan` / subscription fields, etc. Source: [`backend/prisma/schema.prisma`](backend/prisma/schema.prisma).

Versioned API under **`/v1`**. Auth: register, login, refresh, logout; Google path as implemented in [`backend/src/modules/auth`](backend/src/modules/auth).

---

## Roadmap — next milestone (prioritized)

**Pick these two first** — highest leverage without new platforms:

1. **Recurring slots / templates** — Map onto existing **timeline rows + planner JSON** so repeat planning does not multiply manual work (habit-style recurrence can start as simple “repeat weekly” on slot metadata or a thin recurrence table later).
2. **Global search** — One entry point querying **local** timeline titles + inbox notes (matches offline-first stance; extend to server notes when indexing is justified).

Next wave (after or in parallel):

- Lightweight **calendar read-only overlay** (busy blocks) before full sync.
- **Portable export / backup** (JSON or ICS subset) for trust and portability.
- **Monetization**: wire **`User.plan`** and subscription fields to real billing + feature flags (admin already supports configuration).

---

## Store, privacy, and QA

Before broader Play testing:

- Complete items in **[`mobile/docs/PLAY_INTERNAL_CHECKLIST.md`](mobile/docs/PLAY_INTERNAL_CHECKLIST.md)** (smoke path, listings, privacy policy URL).
- Use **[`mobile/docs/PRIVACY_POLICY_TEMPLATE.md`](mobile/docs/PRIVACY_POLICY_TEMPLATE.md)** only as a **draft** until legal review; publish the final URL in the store listing.

---

## Architectural principles

From the repo README:

- Predictable behavior and resilience **offline-first** for planner data.
- User-facing errors should be human-readable.

---

## References

HTML mock parity when applicable:

- Internal checklist references `focusflow-complete.html`; compare UX when iterating on inbox ↔ timeline gestures.
