begin;

create or replace function public.platform_create_org(
  p_name text,
  p_tier_code text default 'free',
  p_is_listed boolean default false,
  p_owner_email text default null,
  p_owner_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_org uuid;
  v_owner uuid;
  v_creator uuid;
  v_created_by uuid;
  v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_name is null or length(trim(p_name))=0 then
    raise exception 'Org name required';
  end if;

  v_creator := auth.uid(); -- platform admin caller (JWT)
  v_owner := p_owner_user_id;

  if v_owner is null and p_owner_email is not null and length(trim(p_owner_email))>0 then
    v_owner := public.platform_find_user_id(p_owner_email);
  end if;

  v_created_by := coalesce(v_owner, v_creator);
  if v_created_by is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.orgs(name, subscription_tier_code, is_listed, created_by)
  values (
    trim(p_name),
    coalesce(nullif(p_tier_code,''),'free'),
    coalesce(p_is_listed,false),
    v_created_by
  )
  returning id into v_org;

  -- Assign owner membership if provided (approved)
  if v_owner is not null then
    v_role := coalesce(
      public.safe_org_role('super_admin'),
      public.safe_org_role('admin'),
      public.default_org_member_role()
    );

    insert into public.org_members(org_id, user_id, role, status, approved_at, approved_by)
    values (v_org, v_owner, v_role, 'approved', now(), v_creator)
    on conflict (org_id, user_id) do update
      set status='approved',
          role=excluded.role,
          approved_at=now(),
          approved_by=v_creator;
  end if;

  return jsonb_build_object('ok', true, 'org_id', v_org, 'owner_user_id', v_owner);
end $$;

revoke all on function public.platform_create_org(text,text,boolean,text,uuid) from public;
grant execute on function public.platform_create_org(text,text,boolean,text,uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;