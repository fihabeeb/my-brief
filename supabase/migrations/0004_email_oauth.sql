-- My Brief — email OAuth state, Vault access, and mirror retention (Phase 4)
-- Run after 0003_email.sql.
--
-- The client never writes email rows. OAuth tokens live in Supabase Vault;
-- Edge Functions reach Vault through the security-definer wrappers below,
-- because PostgREST does not expose the vault schema.

-- ---------------------------------------------------------------------------
-- OAuth state
-- ---------------------------------------------------------------------------

-- A short-lived, single-use state row. The callback consumes it before the
-- code exchange, which is what prevents replay and CSRF. No RLS policies are
-- created: only the service role may touch this table.
create table if not exists public.oauth_states (
  state         text primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  provider      text not null check (provider in ('gmail', 'outlook')),
  code_verifier text not null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null
);

alter table public.oauth_states enable row level security;
revoke all on public.oauth_states from anon, authenticated;
grant all on public.oauth_states to service_role;

create index if not exists oauth_states_expires_idx
  on public.oauth_states (expires_at);

-- Deletes and returns the state in one statement. A second callback with the
-- same state gets no row, even if the two requests race.
create or replace function public.consume_oauth_state(p_state text)
returns table (user_id uuid, provider text, code_verifier text)
language sql
security definer
set search_path = public
as $$
  delete from public.oauth_states
  where state = p_state and expires_at > now()
  returning
    oauth_states.user_id,
    oauth_states.provider,
    oauth_states.code_verifier;
$$;

revoke all on function public.consume_oauth_state(text)
  from public, anon, authenticated;
grant execute on function public.consume_oauth_state(text) to service_role;

-- ---------------------------------------------------------------------------
-- Vault wrappers
-- ---------------------------------------------------------------------------

-- Upsert a secret by name. Tokens are stored as one JSON bundle per account.
create or replace function public.email_secret_put(p_name text, p_secret text)
returns void
language plpgsql
security definer
set search_path = vault, public
as $$
declare
  v_id uuid;
begin
  select id into v_id from vault.secrets where name = p_name;
  if v_id is null then
    perform vault.create_secret(p_secret, p_name);
  else
    perform vault.update_secret(v_id, p_secret, p_name);
  end if;
end;
$$;

create or replace function public.email_secret_get(p_name text)
returns text
language sql
security definer
set search_path = vault, public
as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_name;
$$;

create or replace function public.email_secret_delete(p_name text)
returns void
language plpgsql
security definer
set search_path = vault, public
as $$
declare
  v_id uuid;
begin
  select id into v_id from vault.secrets where name = p_name;
  if v_id is not null then
    perform vault.delete_secret(v_id);
  end if;
end;
$$;

revoke all on function public.email_secret_put(text, text)
  from public, anon, authenticated;
revoke all on function public.email_secret_get(text)
  from public, anon, authenticated;
revoke all on function public.email_secret_delete(text)
  from public, anon, authenticated;

grant execute on function public.email_secret_put(text, text) to service_role;
grant execute on function public.email_secret_get(text) to service_role;
grant execute on function public.email_secret_delete(text) to service_role;

-- ---------------------------------------------------------------------------
-- Upsert-friendly IDs
-- ---------------------------------------------------------------------------

-- The sync function omits id when upserting on (account_id,
-- provider_message_id). A default keeps that insert valid and, because id is
-- absent from the payload, an ON CONFLICT update never rewrites the primary
-- key.
alter table public.email_accounts alter column id set default gen_random_uuid();
alter table public.emails alter column id set default gen_random_uuid();

-- ---------------------------------------------------------------------------
-- Account RLS
-- ---------------------------------------------------------------------------

-- Accounts are written by the Edge Functions only. The client needs to read
-- them, and disconnects through email-disconnect rather than deleting rows.
drop policy if exists "email_accounts_all_own" on public.email_accounts;
drop policy if exists "email_accounts_select_own" on public.email_accounts;
create policy "email_accounts_select_own" on public.email_accounts
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------

-- Keep the newest N messages per account. The client pulls the same complete
-- window and can therefore reconcile deletions safely, rather than treating
-- an overlapping page as the whole mailbox.
create or replace function public.prune_emails(
  p_account_id uuid,
  p_keep int default 200
)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.emails e
  using (
    select id
    from public.emails
    where account_id = p_account_id
    order by received_at desc, id desc
    offset greatest(coalesce(p_keep, 200), 0)
  ) old
  where e.id = old.id;
$$;

revoke all on function public.prune_emails(uuid, int)
  from public, anon, authenticated;
grant execute on function public.prune_emails(uuid, int) to service_role;
