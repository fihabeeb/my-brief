# Supabase setup (My Brief)

This is the backend runbook: database migrations, auth, the Google OAuth app,
Edge Function secrets, and the scheduled Gmail sync.

This build supports **Gmail only**. Outlook / Microsoft Entra support is
intentionally removed for now, so there are no Microsoft credentials to
provide. `0006_google_only.sql` deletes any Outlook accounts created while
testing, removes their Vault secrets, and narrows the provider constraint.

The Flutter app only needs `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The Google
client secret and Gmail refresh tokens stay on the server.

---

## 1. Create a project

1. Go to <https://supabase.com> → **New project** (the free tier is enough).
2. Pick a region close to you and save the database password.
3. Wait for provisioning to finish.

## 2. Enable email (OTP) sign-in

**Authentication → Providers → Email:**

- Enable it.
- Turn **Confirm email** off. The app uses a 6-digit one-time code, not a
  magic link or confirmation email.

## 3. Apply the schema

With the Supabase CLI (recommended):

```powershell
npm i -g supabase
supabase login
supabase link --project-ref <PROJECT_REF>
supabase db push
```

Or open **SQL Editor** and run these files in order:

1. [`migrations/0001_init.sql`](migrations/0001_init.sql)
2. [`migrations/0002_tasks_reminders.sql`](migrations/0002_tasks_reminders.sql)
3. [`migrations/0003_email.sql`](migrations/0003_email.sql)
4. [`migrations/0004_email_oauth.sql`](migrations/0004_email_oauth.sql)
5. [`migrations/0005_email_cron.sql`](migrations/0005_email_cron.sql)
6. [`migrations/0006_google_only.sql`](migrations/0006_google_only.sql)

`0004` creates the OAuth state table, Vault RPCs, account RLS, and the
retention RPC. `0005` creates `pg_cron`/`pg_net` and the five-minute sync job.
`0006` removes the Outlook path and enforces `provider = 'gmail'`.

If you already applied `0004` and `0005`, run **only `0006`** now. It is
destructive for Outlook rows by design: their emails cascade, and their Vault
secrets are deleted.

If you applied the earlier files through the **SQL Editor**, run `0006` there
too instead of `supabase db push`. The CLI may not know that `0004` and `0005`
were already applied, and `db push` would try to replay them. If the CLI owns
the migration history, `supabase db push` is fine and applies just `0006`.

### Extensions

The migrations enable `pg_cron` and `pg_net`. Supabase Vault is enabled by
default; if it is not, enable **Vault** under **Database → Extensions** before
applying `0004`. If `0005` cannot create the extensions, enable **pg_cron** and
**pg_net** in the dashboard and run `0005` again.

## 4. Client credentials

From **Project Settings → API**:

- **Project URL** → `SUPABASE_URL`
- **anon / public key** → `SUPABASE_ANON_KEY`

Create the local, git-ignored client file:

```powershell
copy config\dev.example.json config\dev.json
```

Fill in the two values, then run:

```powershell
flutter run --dart-define-from-file=config\dev.json
```

The anon key is not a secret. It ships in every client build and is protected
by Row Level Security.

## 5. Realtime for app-owned data

**Database → Replication** (or **Realtime → Publications**): enable replication
for `public.tasks` and `public.reminders`. These are the tables the client
subscribes to for live updates. Email uses a periodic pull instead; a realtime
feed on the mail mirror would be pure cost.

## 6. Google OAuth app

1. Create/select a project in [Google Cloud Console](https://console.cloud.google.com/).
2. Enable the **Gmail API**.
3. Configure the **OAuth consent screen**:
   - User type: **External**
   - Scopes: `openid`, `email`, `profile`,
     `https://www.googleapis.com/auth/gmail.readonly`
   - Add your account as a test user while testing.
   - Publish the app to **production** before relying on it. In **Testing**
     mode Google expires refresh tokens after 7 days. An unverified production
     app works with the “Google hasn’t verified this app” warning.
4. Create an OAuth client ID of type **Web application**.
5. Add this **Authorized redirect URI** exactly:

   ```text
   https://<PROJECT_REF>.supabase.co/functions/v1/oauth-callback
   ```

6. Copy the client ID and client secret into the function secrets below.

No Azure / Entra app registration is needed.

## 7. Function secrets

Create `supabase/.env` from the example. It is git-ignored.

```powershell
copy supabase\.env.example supabase\.env
```

Fill in:

```dotenv
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
OAUTH_REDIRECT_URL=https://<PROJECT_REF>.supabase.co/functions/v1/oauth-callback
EMAIL_SYNC_SECRET=<random-32-bytes-base64url>
```

`OAUTH_REDIRECT_URL` must match the redirect URI registered in Google Cloud
character for character. `EMAIL_SYNC_SECRET` must be the same value you store
in Vault below.

If you previously set Microsoft secrets, remove them so they cannot be used by
accident (optional; the functions no longer read them):

```powershell
npx supabase secrets unset MICROSOFT_CLIENT_ID MICROSOFT_CLIENT_SECRET MICROSOFT_TENANT
```

Push the secrets:

```powershell
npx supabase secrets set --env-file supabase\.env
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
provided by the Edge Function runtime. Do not put them in `supabase/.env`.

Generate a sync secret if you need one:

```powershell
# PowerShell
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
[Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
```

## 8. Vault entries for the cron job

The cron migration reads its URL and shared secret from Vault, so no
project-specific values live in SQL. Run this in the SQL Editor:

```sql
select vault.create_secret(
  'https://<PROJECT_REF>.supabase.co/functions/v1/email-sync',
  'email_sync_url'
);

select vault.create_secret(
  '<same value as EMAIL_SYNC_SECRET>',
  'email_sync_secret'
);
```

If the secrets already exist, update them by id instead:

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'email_sync_url'),
  'https://<PROJECT_REF>.supabase.co/functions/v1/email-sync',
  'email_sync_url'
);

select vault.update_secret(
  (select id from vault.secrets where name = 'email_sync_secret'),
  '<same value as EMAIL_SYNC_SECRET>',
  'email_sync_secret'
);
```

## 9. Deploy the Edge Functions

Deploy all four functions after the secrets are set. If Docker is unavailable,
add `--use-api` so the CLI bundles remotely:

```powershell
npx supabase functions deploy oauth-start oauth-callback email-disconnect email-sync --use-api
```

`supabase/config.toml` sets the JWT requirements:

- `oauth-start` and `email-disconnect` require a signed-in user JWT.
- `oauth-callback` is a browser redirect and cannot carry a JWT.
- `email-sync` is called by `pg_cron` and authenticates with
  `x-cron-secret`.

Do **not** deploy all functions with `--no-verify-jwt`; only the two functions
marked `verify_jwt = false` in `config.toml` should skip JWT verification.

## 10. Verify and test Gmail only

SQL:

```sql
select id, provider, email_address, status, last_synced_at, sync_cursor
from public.email_accounts;

select provider, count(*) as accounts
from public.email_accounts
group by provider;

select count(*) as messages, max(received_at) as newest
from public.emails;

select jobid, jobname, schedule, active
from cron.job
where jobname = 'mybrief-email-sync';

select id, status_code, content, created
from net._http_response
order by created desc
limit 5;
```

Invoke a sync manually (useful before the first cron tick):

```powershell
Invoke-RestMethod -Method Post `
  -Uri https://<PROJECT_REF>.supabase.co/functions/v1/email-sync `
  -Headers @{ 'x-cron-secret' = '<EMAIL_SYNC_SECRET>' } `
  -ContentType 'application/json' `
  -Body '{}'
```

Manual flow:

1. Sign in on Windows with the rebuilt app. **Settings** should show one
   **Connect Gmail** button and no Outlook button.
2. Click **Connect Gmail** and approve the Google consent screen. The app asks
   only for read-only Gmail access.
3. Confirm the success page; check the `email_accounts` row and the Vault
   secret.
4. Run the manual sync above (or wait five minutes). The response should have
   `ok: true` and a `connected` result; `emails` should contain up to 200
   messages.
5. Return to the app. The inbox/dashboard should show mail within one client
   pull (every two minutes).
6. Mark a message read/important, archive it, and delete another at Gmail.
   Run another sync and confirm the server and app reflect each change. Archive
   detection relies on Gmail history, so this also checks the cursor path.
7. Disconnect in Settings. The account, Vault secret, server mail, and local
   mail should all disappear.
8. Reconnect once, then revoke the app under
   <https://myaccount.google.com/permissions>. The next sync should set
   `status = 'needs_reauth'`; Settings should say “Needs reconnecting”.

### Troubleshooting a 500

The function logs are the fastest way to see the real error. Open
**Supabase Dashboard → Edge Functions → oauth-start (or oauth-callback) →
Logs**. The CLI version used here does not expose a `functions logs`
subcommand.

- **`oauth-start` returns 500** — almost always a missing
  `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, or `OAUTH_REDIRECT_URL`, or the
  functions were deployed before the secrets were set. Set the secrets, then
  redeploy. A Gmail click should no longer depend on any Microsoft secret.
- **Callback shows “Could not connect the mailbox”** — the redirect URI in
  Google Cloud and `OAUTH_REDIRECT_URL` must match exactly, including
  `https://`, the project ref, and `/functions/v1/oauth-callback`. Also check
  that the OAuth client is a **Web application**, the client secret is the one
  for that client, the Gmail API is enabled, and the callback was not retried
  after the one-time code was already exchanged.
- **`email-sync` returns 401** — `EMAIL_SYNC_SECRET` and the Vault secret
  `email_sync_secret` differ. Update Vault with the same value and retry.
- **`email-sync` reports `Quota exceeded` / `Total Query Cost`** — Gmail's
  per-user limit is 6,000 quota units per minute. Wait about a minute and run
  the manual sync again; the five-minute cron will also retry. The sync uses
  `format=metadata` (20 units per message) and caps incremental batches so a
  200-message initial sync stays under the limit. If it keeps happening, check
  for overlapping manual and cron runs.
- **`email-sync` succeeds but no mail appears** — check that
  `email_sync_url` points at `/functions/v1/email-sync`, and inspect
  `net._http_response` for the cron response.
- **Old Outlook button still visible** — that is an old client build. Rebuild
  or reinstall the app. The new server also rejects `provider: "outlook"` with
  `400`, not `500`.

## 11. Local checks

```powershell
flutter analyze
flutter test

node --experimental-strip-types --test "supabase/functions/_shared/*.test.ts"

npx deno check --no-lock --config supabase/functions/deno.json `
  supabase/functions/oauth-start/index.ts `
  supabase/functions/oauth-callback/index.ts `
  supabase/functions/email-disconnect/index.ts `
  supabase/functions/email-sync/index.ts
```

## 12. Security notes

- OAuth uses PKCE (S256). The code verifier never leaves the server.
- `oauth_states` rows are random, single-use, expire after 10 minutes, and are
  consumed atomically before the code exchange.
- Refresh tokens are stored only in Supabase Vault. `email_accounts.secret_ref`
  is just a name.
- The Vault RPCs are security-definer functions executable only by
  `service_role`.
- `email_accounts` and `emails` are select-only for the signed-in user. Edge
  Functions are the only writers.
- `email-sync` requires the cron secret; that secret is never shipped in the
  Flutter app.
- Provider error text is sanitized and escaped before it is rendered or logged.

## Free-tier note

A five-minute email-sync cron keeps a free Supabase project active while email
is connected. If you disable email sync, add a separate keep-alive before
relying on the project staying unpaused.
