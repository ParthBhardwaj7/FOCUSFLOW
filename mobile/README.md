# FocusFlow mobile (Flutter / Android)

Canonical **Flutter** client for FocusFlow MVP: **Day 0**, main shell (**Inbox**, **Timeline / Now**, **AI**, **Settings**), **Focus**, **Add task**, and **Reset day** UI wired to the Nest API under `/v1`.

## Prerequisites

- Flutter SDK (stable), Android SDK / device or emulator
- Backend running — see [`../backend/README.md`](../backend/README.md)

## Configuration

1. Copy [`.env.example`](./.env.example) to **`.env`** in this folder (gitignored).
2. Set `API_BASE_URL`:
   - **Android emulator → host machine API:** `http://10.0.2.2:3000`
   - **Physical device (same Wi‑Fi as PC):** use your PC’s LAN IP, e.g. `http://192.168.1.10:3000`, and add that origin to backend `CORS_ORIGINS`.
   - **Physical device over USB** (API on PC `localhost:3000`): run once per cable session  
     `adb reverse tcp:3000 tcp:3000`  
     then set `API_BASE_URL=http://127.0.0.1:3000` (or the same port your Nest process uses).

`flutter_dotenv` loads `.env` at startup when the file exists (`main.dart`).

### Offline-first session

The timeline / planner is **local** on device. **Account, notes, AI, and sync** need the API when online.

- **Staying signed in:** Tokens live in **flutter_secure_storage**. If the server is unreachable on cold start, the app **does not wipe tokens** on network errors; it restores the last **cached profile** (or decodes `sub` / `email` from the stored access JWT as a fallback) so you are not logged out every launch.
- **Actual logout** only happens when the server returns **401/403** on refresh (revoked or invalid refresh token) or when you tap **Sign out**.

Set **`API_BASE_URL`** correctly for your device so online features work when the network is available.

### Register / login errors (“Create account” / Dio)

1. **Backend must be running** — from `../backend`: `docker compose up -d`, `npm run db:migrate`, `npm run start:dev`. Check `http://localhost:3000/v1/health` in a browser or PowerShell.
2. **`API_BASE_URL`** in `mobile/.env` must point at your machine from the **device** (emulator: `http://10.0.2.2:3000`; USB phone: `adb reverse tcp:3000 tcp:3000` + `http://127.0.0.1:3000`, or your PC LAN IP).
3. Snackbars now show a **short Dio message** (connection vs HTTP body). If you see **connection error**, it is almost always “API not reachable”, not bad password.

### Timeline day: local `on=` vs server UTC bucket

The app’s week strip and “selected day” use **`YYYY-MM-DD` in the device’s local calendar**. The backend `GET /v1/timeline?on=` interprets `on` as a **UTC calendar day** (`onT00:00:00.000Z` … next midnight UTC). Near time-zone boundaries or late evening, a local date can map to a different set of slots than you expect. Creating slots uses **local date + local time → converted to UTC** in the client so wall times match what you pick in the UI.

## Run

```bash
cd mobile
flutter pub get
flutter run
```

## Stack

- **Riverpod** — session + DI
- **go_router** — `/splash`, `/auth/*`, `/day0`, shell tabs `/inbox`, `/now`, `/ai`, `/settings`, plus `/add-task`, `/focus`
- **dio** — REST + refresh-on-401
- **flutter_secure_storage** — refresh/access tokens
- **just_audio** + **audio_service** — initialized in `main` for future background focus audio (handler stub in [`lib/services/focus_audio_handler.dart`](lib/services/focus_audio_handler.dart))
- **flutter_local_notifications** — initialized in [`lib/services/notification_bootstrap.dart`](lib/services/notification_bootstrap.dart)

## Product mapping

Aligned with [`../FOCUSFLOW_MASTER.md`](../FOCUSFLOW_MASTER.md) and the HTML mockups [`../focusflow-v2.html`](../focusflow-v2.html), [`../focusflow-complete.html`](../focusflow-complete.html).

## Play internal testing

See [`docs/PLAY_INTERNAL_CHECKLIST.md`](docs/PLAY_INTERNAL_CHECKLIST.md).
