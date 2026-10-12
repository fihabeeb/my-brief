# Supabase setup (My Brief)

The app reads two values at build time — they are **not** stored in the repo.

## 1. Create a project
1. Go to https://supabase.com → New project (free tier is enough).
2. Pick a region close to you, set a database password, and save it.
3. Wait for provisioning to finish.

## 2. Apply the schema
Open **SQL Editor** and run the contents of [`migrations/0001_init.sql`](migrations/0001_init.sql).
(Or, with the Supabase CLI: `supabase link --project-ref <ref>` then `supabase db push`.)

This creates the `profiles` table with Row Level Security so each user only
sees their own row. Later phases add tasks, reminders, email and devices.

## 3. Enable email (OTP) sign-in
**Authentication → Providers → Email:**
- Enable it.
- Turn **Confirm email** OFF (we use a 6-digit one-time code, so no magic link /
  confirmation is needed).

## 4. Grab your credentials
From **Project Settings → API**:
- **Project URL** → `SUPABASE_URL`
- **anon / public key** → `SUPABASE_ANON_KEY`

Create a local file (git-ignored) from the example:

```
copy config\dev.example.json config\dev.json
```

Fill in the two values, then run:

```
flutter run --dart-define-from-file=config/dev.json
```

`config/dev.json` is git-ignored so the anon key stays out of version control.

## 5. Realtime (used from Phase 1)
**Database → Replication:** enable replication on the `profiles` table now, and
on each table as later phases add them. The sync engine subscribes to
`postgres_changes` on these tables.

## Note on the free tier
Supabase pauses free projects after ~7 days of inactivity. Phase 6 adds a daily
keep-alive ping; until then, visiting the dashboard or reopening the project in
the Supabase console keeps it warm.
