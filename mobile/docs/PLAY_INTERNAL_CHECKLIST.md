# Google Play internal testing — checklist

Use this before inviting testers or moving to closed production.

## Build and signing

- [ ] Create or reuse a **Play Console** application with package name matching `applicationId` in `android/app/build.gradle.kts`.
- [ ] Configure **Play App Signing** (recommended) and keep your **upload key** backed up offline.
- [ ] Bump `versionCode` / `versionName` in `pubspec.yaml` for each upload.
- [ ] Build release: `flutter build appbundle` and upload **AAB** to **Internal testing**.

## Policies and store listing

- [ ] Privacy policy URL (even for MVP) if you collect accounts, tasks, or analytics. Draft sections: [`PRIVACY_POLICY_TEMPLATE.md`](PRIVACY_POLICY_TEMPLATE.md).
- [ ] Short + full description, screenshots (phone), feature graphic.
- [ ] Content rating questionnaire completed.

## Android runtime (FocusFlow-specific)

- [ ] **INTERNET** — already in manifest; verify API reachable from device network.
- [x] **POST_NOTIFICATIONS** — runtime request via `NotificationBootstrap.requestOsNotificationPermission()` when **Gentle nudges** is turned on, on cold start if gentle nudges are enabled, and before rescheduling when notification toggles under **NOTIFICATIONS** change (see `settings_page.dart` / `notification_bootstrap.dart`).
- [ ] **Foreground service** — if you ship long focus sessions with audio, declare the correct `foregroundServiceType` (e.g. `mediaPlayback`) and match Play policy. *(Track separately in the audio / FGS pass.)*
- [x] **Cleartext traffic** — `src/main/AndroidManifest.xml` sets `usesCleartextTraffic="false"` for **release** builds; **debug** and **profile** manifests overlay `true` so local HTTP (`http://10.0.2.2:3000`, LAN IP, etc.) still works. Ship production APIs on **HTTPS** only.
- [x] **Battery / OEM** — Settings tab includes **REMINDERS HELP** with guidance on battery optimization and exact alarms when users miss nudges.

## Quality

- [ ] Smoke: register → Day 0 → Skip or Demo focus → Now → Add task → Do this now → complete/skip session.
- [ ] **UI parity (`focusflow-complete.html`):** Inbox quick capture + swipe schedule/delete → Timeline; AI insight card + one-taps; Focus ring + sound chips; Settings focus toggles.
- [ ] `flutter analyze` and `flutter test` (from `mobile/`) pass before upload.
- [ ] Verify **CORS** and **HTTPS** for any non-debug host.

## Backend

- [ ] Production `DATABASE_URL`, `JWT_*` secrets, and `CORS_ORIGINS` include your deployed web/API origins.
- [ ] Run `npm run db:deploy` against production before clients hit the API.
