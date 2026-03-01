begin;

-- A) Make orgs optionally discoverable (privacy-safe)
alter table public.orgs
  add column if not exists is_listed boolean not null default false;

-- B) List ONLY discoverable orgs for request-access dropdown
create or replace function public.list_listed_orgs(p_limit int default 50)
returns table(
  org_id uuid,
  name text,
  support_email text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.id,
    o.name,
    coalesce(o.support_email, (select support_email from public.platform_settings where id=1)) as support_email
  from public.orgs o
  where o.is_listed = true
  order by o.name asc
  limit greatest(1, least(p_limit, 500));
$$;

revoke all on function public.list_listed_orgs(int) from public;
grant execute on function public.list_listed_orgs(int) to authenticated;

-- C) Platform admin: list orgs (now includes is_listed)
drop function if exists public.platform_list_orgs(int);

create function public.platform_list_orgs(p_limit int default 200)
returns table(
  org_id uuid,
  name text,
  subscription_tier_code text,
  is_listed boolean,
  branch_count int,
  support_email text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.id,
    o.name,
    o.subscription_tier_code,
    o.is_listed,
    (select count(*) from public.branches b where b.org_id = o.id)::int as branch_count,
    coalesce(o.support_email, (select support_email from public.platform_settings where id=1)) as support_email,
    o.created_at
  from public.orgs o
  where public.is_platform_admin()
  order by o.created_at desc
  limit greatest(1, least(p_limit, 2000));
$$;

revoke all on function public.platform_list_orgs(int) from public;
grant execute on function public.platform_list_orgs(int) to authenticated;

-- D) Platform admin: update org (tier + listing) in ONE call
create or replace function public.platform_update_org(
  p_org_id uuid,
  p_tier_code text,
  p_is_listed boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  update public.orgs
  set
    subscription_tier_code = p_tier_code,
    is_listed = p_is_listed
  where id = p_org_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_update_org(uuid,text,boolean) from public;
grant execute on function public.platform_update_org(uuid,text,boolean) to authenticated;

-- E) Request access (creates a pending membership to approve)
create or replace function public.request_org_access(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.org_members(org_id, user_id, role, status)
  values (p_org_id, v_user, 'member', 'pending')
  on conflict (org_id, user_id) do update
    set status = 'pending';

  return jsonb_build_object('ok', true, 'org_id', p_org_id);
end $$;

revoke all on function public.request_org_access(uuid) from public;
grant execute on function public.request_org_access(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;