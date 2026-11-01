-- My Brief — scheduled email sync (Phase 4)
-- Run after 0004_email_oauth.sql.
--
-- The URL and shared secret are read from Vault, so this migration contains
-- no project-specific values. Create the two secrets first (see
-- supabase/README.md), then apply this migration.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.invoke_email_sync()
returns bigint
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'email_sync_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'email_sync_secret';

  if v_url is null or v_secret is null then
    raise warning 'email sync Vault secrets are missing';
    return null;
  end if;

  return net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.invoke_email_sync()
  from public, anon, authenticated;
-- pg_cron runs the job as the role that created it, normally postgres. Keep
-- that explicit so a function owner change cannot silently break the schedule.
grant execute on function public.invoke_email_sync() to postgres;

-- Make the migration idempotent when re-run in the SQL editor.
do $$
begin
  perform cron.unschedule('mybrief-email-sync');
exception when others then
  null;
end;
$$;

select cron.schedule(
  'mybrief-email-sync',
  '*/5 * * * *',
  $$select public.invoke_email_sync();$$
);
