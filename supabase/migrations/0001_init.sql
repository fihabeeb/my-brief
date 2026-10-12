-- My Brief — initial schema (Phase 0)
-- Run this in the Supabase SQL editor, or via `supabase db push` with the CLI.
-- Later phases add tasks, reminders, email_accounts, emails, devices and
-- notification_rules. Each table is owned by its user via RLS.

create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  display_name    text,
  timezone        text        default 'UTC',
  day_reset_hour  int         default 6,          -- "daily reset" boundary (local)
  quiet_hours     jsonb,                          -- e.g. {"start":"22:00","end":"07:00"}
  settings_json   jsonb       default '{}'::jsonb,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- Row Level Security: each user only ever sees their own profile.
alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Keep updated_at fresh on every update.
create or replace function public.touch_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();
