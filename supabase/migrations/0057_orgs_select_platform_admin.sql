begin;

alter table public.orgs enable row level security;

drop policy if exists orgs_select_platform_admin on public.orgs;
create policy orgs_select_platform_admin
on public.orgs
for select to authenticated
using (public.is_platform_admin());

select pg_notify('pgrst','reload schema');
commit;