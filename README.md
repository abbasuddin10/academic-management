# academy_management

A Flutter application for managing academies, teachers, students, attendance,
finance and exams.

## Getting Started

```sh
flutter pub get
flutter run
```

## Configuration

Backend identifiers are read at build time from `--dart-define` values. The
values currently committed in `lib/config/app_config.dart` are the public
Supabase publishable key / Firebase web config and are only fallbacks. Supply
real values for any deployment:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx \
  --dart-define=FIREBASE_API_KEY=xxx \
  --dart-define=FIREBASE_AUTH_DOMAIN=xxx \
  --dart-define=FIREBASE_PROJECT_ID=xxx \
  --dart-define=FIREBASE_STORAGE_BUCKET=xxx \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxx \
  --dart-define=FIREBASE_APP_ID=xxx \
  --dart-define=FIREBASE_MEASUREMENT_ID=xxx \
  --dart-define=GEMINI_API_KEY=xxx
```

`GEMINI_API_KEY` is a secret and has an empty default — never commit it.

## Backend setup (required)

1. Apply the security migration:
   ```sh
   supabase db push
   ```
   or paste `supabase/migrations/0001_rls_and_schema_hardening.sql` into the
   Supabase SQL editor. It installs tenant-scoped RLS policies on every table
   with an `academy_id`, indexes, login helper RPCs and an atomic
   `register_academy` function.

2. In **Supabase Auth → Providers**, enable **Allow anonymous sign-ins**.
   Teacher and student logins open an anonymous Supabase session and register
   their tenant via `upsert_app_session`; all subsequent queries are then
   authenticated and correctly scoped by RLS. Without this setting the app
   cannot establish a tenant-scoped session.

3. Existing databases that stored plaintext passwords in `users.password` or
   `students.custom_password` are supported: successful logins transparently
   upgrade those records to salted PBKDF2 hashes. New records are hashed from
   the start.

## Testing

```sh
flutter test
```
