-- My Brief — email accounts + inbox (Phase 4)
-- Run in the Supabase SQL editor after 0002_tasks_reminders.sql.
--
-- Design note: unlike tasks and reminders, emails are **not** authored on the
-- client. The Edge Functions are the only writers, so the app's local Drift
-- copy is a read cache and carries no sync outbox. That is why these tables
-- have no `needs_sync` column and `emails` is not added to realtime
-- replication — a per-client change feed on a mail mirror would be pure cost.

create table if not exists public.email_accounts (
  id              uuid primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  provider        text not null check (provider in ('gmail', 'outlook')),
  email_address   text not null,
  display_name    text,
  -- 'connected' | 'needs_reauth' | 'error'. A refresh token can be revoked by
  -- the user at either end, so this has to be able to degrade rather than
  -- leave the account looking healthy while silently failing to sync.
  status          text not null default 'connected',
  last_error      text,
  -- Provider-specific sync position: Gmail's historyId, or Graph's delta
  -- token. Opaque to the client; only the Edge Function reads it.
  sync_cursor     text,
  last_synced_at  timestamptz,
  -- Name of the Supabase Vault secret holding this account's tokens. The
  -- tokens themselves never touch this table, and never leave the server.
  secret_ref      text not null,
  created_at      timestamptz not null default now()
);

-- One account per address per user: connecting the same mailbox twice would
-- otherwise duplicate every message in the inbox.
create unique index if not exists email_accounts_user_address_idx
  on public.email_accounts (user_id, email_address);

alter table public.email_accounts enable row level security;
create policy "email_accounts_all_own" on public.email_accounts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table if not exists public.emails (
  id                 uuid primary key,
  user_id            uuid not null references auth.users (id) on delete cascade,
  account_id         uuid not null references public.email_accounts (id) on delete cascade,
  -- Gmail's message id / Graph's message id. Unique per account, which is what
  -- makes an incremental sync idempotent — re-importing the same window
  -- upserts rather than duplicates.
  provider_message_id text not null,
  thread_id          text,
  from_name          text,
  from_email         text,
  subject            text not null default '',
  -- Short preview only. Deliberately no message body: a mail mirror that
  -- stores full MIME grows fastest of anything in this schema, and the
  -- dashboard wants highlights rather than a full reader. `web_link` opens
  -- the real message in the browser.
  snippet            text,
  received_at        timestamptz not null,
  is_read            boolean not null default false,
  -- The provider's own importance flag. Client-side notification rules layer
  -- on top of this (Phase 5), they do not replace it.
  is_important       boolean not null default false,
  has_attachments    boolean not null default false,
  web_link           text,
  fetched_at         timestamptz not null default now()
);

create unique index if not exists emails_account_message_idx
  on public.emails (account_id, provider_message_id);

create index if not exists emails_user_received_idx
  on public.emails (user_id, received_at desc);

alter table public.emails enable row level security;

-- Read-only for the owner: this table is an inbox, not a scratch pad, and
-- allowing client writes would let the app overwrite its own mail history.
create policy "emails_select_own" on public.emails
  for select using (auth.uid() = user_id);
