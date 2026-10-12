-- My Brief — tasks + reminders (Phase 1)
-- Run in the Supabase SQL editor after 0001_init.sql.

create table if not exists public.tasks (
  id              uuid primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  title           text not null,
  notes           text,
  due_date        timestamptz not null,
  priority        int  default 1,
  status          text default 'pending',
  recurrence_rule text,
  completed_at    timestamptz,
  created_at      timestamptz default now(),
  updated_at      timestamptz not null,
  deleted_at      timestamptz
);

create index if not exists tasks_user_updated_idx on public.tasks (user_id, updated_at desc);

alter table public.tasks enable row level security;
create policy "tasks_all_own" on public.tasks for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table if not exists public.reminders (
  id              uuid primary key,
  user_id         uuid not null references auth.users (id) on delete cascade,
  title           text not null,
  notes           text,
  remind_at       timestamptz not null,
  recurrence_rule text,
  status          text default 'upcoming',
  snoozed_until   timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz default now(),
  updated_at      timestamptz not null,
  deleted_at      timestamptz
);

create index if not exists reminders_user_updated_idx on public.reminders (user_id, updated_at desc);

alter table public.reminders enable row level security;
create policy "reminders_all_own" on public.reminders for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
