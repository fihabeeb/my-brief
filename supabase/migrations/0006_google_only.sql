-- My Brief — Google-only email for v1
-- Run after 0005_email_cron.sql.
--
-- Outlook / Microsoft Entra support is intentionally removed for now. This
-- migration deletes any Outlook accounts created while testing, removes their
-- Vault secrets, and narrows the provider constraint so a stray Outlook row
-- cannot be created later. Emails cascade with their account.

do $$
declare
  r record;
begin
  for r in
    select id, secret_ref
    from public.email_accounts
    where provider <> 'gmail'
  loop
    perform public.email_secret_delete(r.secret_ref);
    delete from public.email_accounts where id = r.id;
  end loop;
end;
$$;

delete from public.oauth_states where provider <> 'gmail';

alter table public.oauth_states
  drop constraint if exists oauth_states_provider_check;

alter table public.oauth_states
  add constraint oauth_states_provider_check check (provider = 'gmail');

alter table public.email_accounts
  drop constraint if exists email_accounts_provider_check;

alter table public.email_accounts
  add constraint email_accounts_provider_check check (provider = 'gmail');
