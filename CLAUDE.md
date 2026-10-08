# CLAUDE.md

Smart Climate Station (`temperature_app`): an Arduino UNO R4 WiFi publishes temperature/humidity/soil moisture to Firebase Realtime Database; this Flutter app shows live values, stores history in SQLite, backs it up to Firestore and charts statistics. See `README.md`.

## Layout
- `lib/main.dart` — Firebase init, `MaterialApp`.
- `lib/pages/home.dart` — the three tabs (real time, history, statistics) and all charts (`fl_chart`). Large file: put new widgets in their own files.
- `lib/data/database_helper.dart` — SQLite singleton (`measurements` table) and hourly/daily/weekly/monthly aggregation queries.
- `lib/data/sync_service.dart` — Firestore `measurements` backup (every 23 h) and restore when SQLite is empty.
- `arduino_code/temp/temp.ino` — sketch; secrets in `secrets.h` (never commit credentials).
- `functions/index.js` — Cloud Function: FCM alert when `sensors/humidity` > 60 %.
- RTDB paths: `sensors/` (latest reading), `history/{epochSeconds}` (queue drained by the app), `commands/trigger_measurement`.

## Commands
- `flutter pub get`, `flutter analyze`, `flutter run`
- Functions: `cd functions && npm install && firebase deploy --only functions`
- Versions: see `pubspec.yaml` and `flutter --version`.

## Conventions
- UI strings are in Spanish.
- Timestamps in SQLite/Firestore are milliseconds; Arduino history keys are epoch seconds.
- `sqflite` does not run on web without `sqflite_common_ffi_web`; the app targets mobile.

## Modularity and reuse
- Search for an existing widget/helper (e.g. `_buildSensorCard`, chart helpers) before adding a new one.
- Extract anything used twice into a shared widget or helper file instead of growing `home.dart`.
- Keep files focused; keep data access in `lib/data/`, not in widgets.
