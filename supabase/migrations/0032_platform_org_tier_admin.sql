begin;

-- List orgs for platform admin management (tier + branch count)
create or replace function public.platform_list_orgs(p_limit int default 200)
returns table(
  org_id uuid,
  name text,
  subscription_tier_code text,
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

-- Set org tier (platform admin only)
create or replace function public.platform_set_org_tier(p_org_id uuid, p_tier_code text)
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
  set subscription_tier_code = p_tier_code
  where id = p_org_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_set_org_tier(uuid,text) from public;
grant execute on function public.platform_set_org_tier(uuid,text) to authenticated;

select pg_notify('pgrst','reload schema');
commit;