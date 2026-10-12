# My Brief

A single-user personal dashboard for **Android** and **Windows** (one Flutter
codebase). It brings together:

- **Email** — Gmail and Outlook / Microsoft 365 (read-only in v1)
- **Reminders** — app-owned, with optional repeat
- **Daily tasks** — app-owned, with optional recurrence

Native notifications on both platforms, and near real-time sync of all
app-owned data (reminders, tasks, settings) between your devices via a cloud
backend.

**Package:** `com.fihabeeb.mybrief` · **minSdk:** 24 · **Windows:** 11+

---

## Status

Built phase-by-phase. See the build plan for the full roadmap.

| Phase | Feature | Status |
|------|---------|--------|
| 0 | Foundations — project, theming, navigation, Supabase auth | ✅ done |
| 1 | Tasks + reminders (local Drift DB + Supabase sync) | ✅ done |
| 2 | Notifications (reminders/tasks, tray + auto-start) | ⬜ |
| 3 | Dashboard | ⬜ |
| 4 | Email integration (Gmail, then Microsoft) | ⬜ |
| 5 | Email notifications (FCM + Windows toasts) | ⬜ |
| 6 | Polish, installers, export/backup | ⬜ |

---

## Prerequisites

- Flutter stable 3.47+ (Dart 3.13+)
- **Windows:** Visual Studio 2022 with the *Desktop development with C++*
  workload + Windows SDK.
- **Android:** Android SDK + JDK 17.
- A Supabase project (optional for Phase 0 — the app runs without it).

## Run it

Phase 0 runs **without any backend** — you'll see a setup screen. To enable
sign-in/sync, add Supabase credentials (see [`supabase/README.md`](supabase/README.md)):

```powershell
# one-time
copy config\dev.example.json config\dev.json   # then fill in your values

# Android (connected device or emulator)
flutter run --dart-define-from-file=config/dev.json -d android

# Windows
flutter run --dart-define-from-file=config/dev.json -d windows
```

Without credentials, simply `flutter run -d android` / `-d windows`.

## Build release artifacts

```powershell
flutter build apk           # Android APK
flutter build appbundle     # Android AAB (Play-ready, later)
flutter build windows       # Windows (unpacked exe in build\windows\x64\runner\Release)
```

## Project layout

```
lib/
  main.dart
  app/                 # MaterialApp, router, responsive shell
  core/                # config, theme, supabase, auth, logging, db, sync
    auth/  profile/  providers/  supabase/  theme/  utils/
  features/            # feature-first screens
    auth/  dashboard/  settings/
supabase/
  migrations/          # SQL schema + RLS
config/
  dev.example.json     # copy to dev.json (git-ignored) and fill in
```

## Secrets

`config/dev.json` is **git-ignored**. Never commit the Supabase anon key,
OAuth client secrets, or Firebase service-account JSON. Backend-only secrets
(Gmail/Microsoft OAuth refresh tokens, FCM service account) live server-side in
Supabase, never in the app.

## Tests

```powershell
flutter test
flutter analyze
```
