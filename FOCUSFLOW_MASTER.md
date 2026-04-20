# FocusFlow — Master product & technical specification

**Single source of truth.** Update this file when strategy changes.  
**Living mockup:** [focusflow-v2.html](focusflow-v2.html) — **4 screens only:** Day 0, Today (Now), Focus, New task (+ Add). **Now** is **command-first** (next block + **Do this now**); full-day timeline lives under **See full day** (`<details>`). **Removed from mockup:** Morning, Command center, Habits, Weekly review, More sheet, celebration overlay, analytics strips on Now/Focus. **Ship path:** see **§9** (Capacitor web-wrap, PWA+TWA, or Flutter).

---

## 1. North star

**Minimize seconds from “I feel stuck” to “timer is running.”**  
Compete on **action**, not planning. Shame-prone users must get a **one-tap forward path** after failure.

---

## 2. One-line positioning

**“Tell me what to do now” — timer, sound, and a gentle day-reset for people who already know what they should do but don’t.**

---

## 3. Target user (validated segment)

- Tired, inconsistent, distracted; has tried multiple productivity tools.
- Wants **relief and execution**, not another system to maintain.
- Will pay if **value appears before day 7**; will churn if setup feels like homework.

---

## 4. MVP scope (ship before anything else)

| In v1 (mockup matches this) | Cut / not in MVP build |
|------------------------------|-------------------------|
| Day 0 → first focus in one tap | Any required “briefing” before first timer |
| **Single primary CTA:** **Do this now** (= next block + timer + sound) | Multiple competing CTAs on home |
| Optional **See full day** timeline (scroll list, current row) — not the default surface | Identity strip, urgency dashboard, heatmaps, weekly stats |
| Focus: timer + ring + sound chips + subtasks + rescue strip + controls | Planned vs actual, Pomodoro pills, flow %, session notes |
| **Reset day** modal (compress / tomorrow / MIT-only) | Shame-first missed-task walls |
| **+ Add** (header) → New task (minimal form + advanced &lt;details&gt;) | Habits / goals / command center / weekly review **until post-PMF** |

**Rule:** If it does not serve **open → act → done**, it does not ship in v1.

---

## 5. Success metrics (instrument in real app)

| Event | Use |
|--------|-----|
| `app_open` | Frequency, cohort |
| `day0_complete` / `day0_skip` | First-run funnel |
| `focus_start` (auto vs manual) | Core adoption |
| `focus_complete` / `focus_skip` | Quality of match |
| `reset_day` (variant) | Failure UX effectiveness |
| Time to first `focus_start` from cold install | **Target: &lt; 90 s median** |

Retention: track D1, D3, D7, D30 against industry baselines (expect steep early drop; optimize the first session).

---

## 6. Behavioral principles (research-aligned)

1. **Cognitive load** — Few choices early; progressive disclosure for depth ([Flutter offline-first pattern](https://docs.flutter.dev/app-architecture/design-patterns/offline-first) applies to *data architecture*; same idea for *UI surface*).
2. **Shame avoidance** — After a miss, lead with **reset / next**, not walls of red “failed” state ([discussion pattern](https://www.reddit.com/r/ProductivityApps/) — users avoid apps that amplify guilt).
3. **Habit loop** — Variable reward + closure: small celebration after block, credible streak.
4. **Setup tax** — Smart defaults; every optional field needs “skip for now.”

---

## 7. User journeys (spec)

### Day 0 (first open)

- No tour. **Do this now (5 min demo)** sets `focusflow_onboarding_done` and opens focus at 5:00. **Skip** goes straight to Now with the same flag.
- **Replay first-run (dev)** clears `localStorage` and returns to Day 0.

### Day 1–3

- One home: **Now** — hero command (next block + **Do this now**) only; planner/timeline under **See full day**. Add tasks via **+ Add** only.

### After failure

- **Reset day** modal: compress / tomorrow / MIT-only — copy stays forward-looking, not moralizing.

---

## 8. Mockup ↔ implementation map

| Spec | HTML |
|------|------|
| Day 0 | `#screen-day0`, head script `__FF_ONBOARD_DONE` + inline boot after timeline |
| Now | `#screen-timeline`, `.command-cta` → `runAutoMode()` → `showFocus()`; `.details-day` holds week strip + timeline |
| Add task | `.header-add` → `#screen-new` |
| Reset | `.recovery-bar` → `#reset-day-modal`, `applyReset()` |
| Focus | `#screen-focus`, `showFocus()` / `focusDurationTotal`, `startTimer()` |

**LocalStorage key:** `focusflow_onboarding_done` — value `'1'` skips Day 0 on next load.

---

## 9. Full tech stack — development → deployment

This section is the **single stack map** for FocusFlow: what you use locally, how the web app becomes a store app, and how you ship.

### 9.1 “Extension” / web → app — what actually works

| What people say | Reality |
|-----------------|--------|
| “**Browser extension**” turns my site into a phone app | **No.** Extensions run inside Chrome/Edge; they are **not** installable as **Android/iOS** store apps. |
| “**One click** web → app” | **Partially yes:** (1) **PWA** install from browser, (2) **Capacitor** wraps your web build in a native shell for Play/App Store, (3) **Bubblewrap (TWA)** publishes a minimal Android app that opens your **PWA** in a trusted Chrome tab. |
| **Best fit for your current HTML mockup** | **Capacitor** (or **Cordova**) if you stay web-first; **PWA + TWA** if you want almost zero native code on Android only; **Flutter** if you want maximum control over background audio + timers and a fully native UI later. |

---

### 9.2 Recommended tracks (pick one primary)

| Track | You build UI in | Native shell | Android | iOS | Effort to ship MVP | Best when |
|-------|-------------------|--------------|---------|-----|---------------------|-----------|
| **A — Web + Capacitor** | HTML/CSS/JS or Vue/Svelte/React | `@capacitor/core` + platform packages | Yes | Yes | **Low** — wrap existing web | You want **one codebase** closest to `focusflow-v2.html`, fast store listing |
| **B — PWA + TWA (Bubblewrap)** | Web + PWA manifest + service worker | Google [Bubblewrap](https://github.com/GoogleChromeLabs/bubblewrap) | Yes (Play) | No (use PWA “Add to Home” only) | **Very low** for Android | Android-first, timer/audio constraints acceptable |
| **C — Flutter** | Dart + Flutter widgets | N/A (fully native) | Yes | Yes | **Higher** — rewrite UI | You outgrow WebView limits (background focus + audio reliability) |

**Practical advice:** start **Track A (Capacitor)** on top of a small Vite/Svelte or plain bundled app that embeds your screens; move to **Track C** only if plugins + foreground services still feel fragile.

---

### 9.3 Track A — end-to-end stack (Web + Capacitor) — *web app → store app*

| Layer | Technology | Role |
|-------|------------|------|
| **Language** | TypeScript (recommended) or JavaScript | Safer refactors as logic grows |
| **UI framework** (optional but wise) | **Svelte** or **Vue** or **React** + **Vite** | Componentize what is now one HTML file; keep same design tokens |
| **Styling** | CSS variables (as now) or **Tailwind CSS** | Rapid layout; dark theme |
| **Local data MVP** | `localforage` / **Dexie.js** (IndexedDB) or **SQLite** via `@capacitor-community/sqlite` | Tasks, sessions, settings offline |
| **Native bridge** | [**Capacitor 6+**](https://capacitorjs.com/) | Camera (if ever), filesystem, splash, **status bar**, **haptics** |
| **Background audio + keep-alive** | `@capacitor-community/keep-awake` + Web Audio or Capacitor **community audio** plugins; for strict Android behavior consider a small **custom plugin** (Kotlin) for foreground service | Focus sessions when screen off |
| **Notifications** | `@capacitor/local-notifications` | “Next block” nudges |
| **Auth / sync (later)** | **Supabase** or **Firebase Auth + Firestore** | Optional; MVP can be 100% local |
| **Analytics** | **PostHog** (self-host or cloud) or Firebase Analytics | Events from §5 |
| **Crash reporting** | **Sentry** | Release quality |
| **Repo** | **Git** + **GitHub** | Source control, Actions |
| **Package manager** | **pnpm** or **npm** | Lockfile, CI |
| **Code quality** | **ESLint** + **Prettier** | Consistency |
| **Tests** | **Vitest** (unit) + **Playwright** (e2e critical paths) | Timer flows, onboarding |
| **CI/CD** | **GitHub Actions** | Lint → test → build web → `cap sync` → build Android (Gradle) / iOS (fastlane optional) |
| **Signing Android** | Play App Signing + upload key | Play Console |
| **Signing iOS** | Apple Developer + Xcode automatic signing / fastlane | TestFlight |
| **Web hosting (PWA)** | **Cloudflare Pages** or **Vercel** or **Netlify** | Hosted URL inside Capacitor **or** bundled `www/` |
| **Distribution** | **Google Play Console** + **App Store Connect** | Production + internal testing |

**Capacitor project shape (typical):**

```text
focusflow/
  android/          # generated native project
  ios/
  src/              # your UI (from HTML migration)
  capacitor.config.ts
  vite.config.ts
  package.json
```

**Deploy flow (Track A):** push to `main` → CI runs tests → `vite build` → `npx cap copy` → Android Gradle bundle (`.aab`) → upload to **Play Internal testing** → same for iOS **TestFlight** when ready.

---

### 9.4 Track B — PWA + Trusted Web Activity (Android “wrapper app”)

| Layer | Technology | Role |
|-------|------------|------|
| **PWA** | `manifest.webmanifest`, **Service Worker** (Workbox optional) | Offline shell, install prompt |
| **Host** | HTTPS static host (Cloudflare Pages / Vercel) | Required for PWA |
| **Android wrapper** | [Bubblewrap](https://github.com/GoogleChromeLabs/bubblewrap) CLI | Generates tiny APK/AAB that opens your PWA in **full-screen Chrome Custom Tabs** |
| **Play listing** | Play Console | Same as any app |

**Limits:** iOS does not use TWA the same way; iOS users add to Home Screen from Safari. Background audio/timer rules are **stricter** than native — good for a **thin** MVP, risky for “always-on focus engine.”

---

### 9.5 Track C — Flutter (native) — stack recap

| Layer | Technology | Role |
|-------|------------|------|
| **Framework** | **Flutter** (Dart) | UI + logic single codebase |
| **State** | **Riverpod** or **Bloc** | Predictable session/timer state |
| **Persistence** | **Drift** (SQLite) | Offline-first per [Flutter offline-first](https://docs.flutter.dev/app-architecture/design-patterns/offline-first) |
| **Audio** | `just_audio` + `audio_service` | Background playback + Android foreground service |
| **Notifications** | `flutter_local_notifications` | Reminders |
| **CI** | GitHub Actions + **Melos** (if monorepo) | `flutter test` → `flutter build appbundle` / `ipa` |
| **Deploy** | Play Console + App Store Connect + **Codemagic** or GitHub Actions macOS runner (iOS) | iOS builds need macOS |

**Flutter module map:** `features/onboarding`, `features/timeline`, `features/focus`, `features/recovery`, `core/persistence`, `core/analytics`.

**Android realities (all native tracks):** foreground service for long focus + audio; exact alarm permission strategy; Play policy on service types; OEM battery settings called out in FAQ.

---

### 9.6 Shared — engineering & operations (all tracks)

| Concern | Choice |
|---------|--------|
| **IDE** | Cursor / VS Code (+ Android Studio for Android SDK/emulator + Xcode on Mac for iOS) |
| **Secrets** | Not in repo — **GitHub Environments** / Doppler / 1Password for API keys |
| **Feature flags** | **PostHog** or simple remote config later | Gradual rollout |
| **Legal** | Privacy policy URL + in-app link | Play / App Store requirement |
| **Domains** | One domain for marketing + app links (optional) | `focusflow.app` style |

---

### 9.7 Backend — MVP vs later

| Phase | Backend | Notes |
|-------|---------|------|
| **MVP** | **None** — local-only | Fastest validation; backup via export JSON (add later) |
| **v1.1** | **Supabase** (Postgres + Auth) or **Firebase** | Sync across devices, optional accounts |
| **Payments** | **RevenueCat** + Store subscriptions | Cross-store entitlements |

---

### 9.8 MVP technical checklist (product-critical)

- [ ] Offline CRUD for tasks + sessions  
- [ ] Restore active session after process death (persist end time + task id)  
- [ ] Reliable focus audio (foreground service on Android where needed)  
- [ ] Local notifications for next block (permission UX)  
- [ ] Analytics events from §5  
- [ ] Release signing + Play Internal testing + TestFlight  

---

## 10. Market realism (condensed)

- Most consumer apps lose the majority of early users quickly; productivity is **especially** sensitive to **friction and shame**.
- **Differentiation:** execution loop + compassionate reset + Auto — not “another list.”
- **Defensibility:** brand + habits + data from *your* users’ patterns — not the UI alone.

---

## 11. 30-day execution order

1. Ship **hero loop only** in a store-ready build (timeline + focus + auto + reset + Day 0).
2. Ten **moderated** usability tests — measure time-to-first-timer-start.
3. Wire **five analytics events** (§5); ship to internal track.
4. Cut anything that does not move those metrics.
5. Re-enable **one** advanced module behind usage or time gate.

---

## 12. Document history

| Date | Change |
|------|--------|
| 2026-04-18 | Consolidated product spec + Flutter/Android feasibility; linked Day 0 boot in `focusflow-v2.html`. |
| 2026-04-18 | **Ruthless MVP cut:** removed 4 advanced screens + More sheet from HTML; single primary CTA on Now; stripped analytics/urgency/identity from Now; slimmed Focus; updated this doc. |
| 2026-04-18 | **Command-first Now:** **Do this now** replaces neutral “Start my day”; timeline folded under **See full day**; Day 0 CTA aligned. |
| 2026-04-18 | **§9 expanded:** full dev→deploy stack; Web+Capacitor, PWA+TWA, Flutter tracks; clarified browser extension vs store app. |

---

## 13. References (external)

- Andrew Chen — mobile retention / “normal” early churn: [andrewchen.com](https://andrewchen.com/new-data-shows-why-losing-80-of-your-mobile-users-is-normal-and-that-the-best-apps-do-much-better/)
- **Capacitor** (web → native container): [capacitorjs.com](https://capacitorjs.com/)
- **Bubblewrap** (PWA → Android TWA): [GoogleChromeLabs/bubblewrap](https://github.com/GoogleChromeLabs/bubblewrap)
- Flutter — offline-first architecture: [docs.flutter.dev/app-architecture/design-patterns/offline-first](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- Flutter — Android integration overview: [docs.flutter.dev/flutter-for/android-devs](https://docs.flutter.dev/flutter-for/android-devs)

---

*End of master spec.*
