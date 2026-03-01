begin;

-- ---------------------------------------------------------
-- Platform helper: find user_id by email (auth.users)
-- ---------------------------------------------------------
create or replace function public.platform_find_user_id(p_email text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare v uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_email is null or length(trim(p_email))=0 then
    return null;
  end if;

  select u.id into v
  from auth.users u
  where lower(u.email) = lower(trim(p_email))
  order by u.created_at asc
  limit 1;

  if v is null then
    raise exception 'User not found for email=%', p_email;
  end if;

  return v;
end $$;

revoke all on function public.platform_find_user_id(text) from public;
grant execute on function public.platform_find_user_id(text) to authenticated;

-- ---------------------------------------------------------
-- Platform: create org (optionally assign owner by email/user_id)
-- ---------------------------------------------------------
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
  v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_name is null or length(trim(p_name))=0 then
    raise exception 'Org name required';
  end if;

  v_owner := p_owner_user_id;
  if v_owner is null and p_owner_email is not null and length(trim(p_owner_email))>0 then
    v_owner := public.platform_find_user_id(p_owner_email);
  end if;

  insert into public.orgs(name, subscription_tier_code, is_listed)
  values (trim(p_name), coalesce(nullif(p_tier_code,''),'free'), coalesce(p_is_listed,false))
  returning id into v_org;

  -- Assign owner membership if provided (approved)
  if v_owner is not null then
    v_role := coalesce(
      public.safe_org_role('super_admin'),
      public.safe_org_role('admin'),
      public.default_org_member_role()
    );

    insert into public.org_members(org_id, user_id, role, status, approved_at, approved_by)
    values (v_org, v_owner, v_role, 'approved', now(), auth.uid())
    on conflict (org_id, user_id) do update
      set status='approved',
          role=excluded.role,
          approved_at=now(),
          approved_by=auth.uid();
  end if;

  return jsonb_build_object('ok', true, 'org_id', v_org, 'owner_user_id', v_owner);
end $$;

revoke all on function public.platform_create_org(text,text,boolean,text,uuid) from public;
grant execute on function public.platform_create_org(text,text,boolean,text,uuid) to authenticated;

-- ---------------------------------------------------------
-- Platform: list members in an org (email resolved)
-- ---------------------------------------------------------
create or replace function public.platform_list_org_members(p_org_id uuid)
returns table(
  user_id uuid,
  email text,
  role text,
  status text,
  requested_at timestamptz,
  approved_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    m.user_id,
    coalesce(p.email, u.email) as email,
    m.role::text as role,
    m.status,
    m.created_at as requested_at,
    m.approved_at
  from public.org_members m
  left join public.profiles p on p.user_id = m.user_id
  left join auth.users u on u.id = m.user_id
  where public.is_platform_admin()
    and m.org_id = p_org_id
  order by m.created_at asc;
$$;

revoke all on function public.platform_list_org_members(uuid) from public;
grant execute on function public.platform_list_org_members(uuid) to authenticated;

-- ---------------------------------------------------------
-- Platform: add member to org (by email or id)
-- p_is_admin controls admin/normal deterministically
-- ---------------------------------------------------------
create or replace function public.platform_add_member(
  p_org_id uuid,
  p_user_email text default null,
  p_user_id uuid default null,
  p_is_admin boolean default false,
  p_status text default 'pending'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid;
  v_role public.org_role;
  v_status text := coalesce(nullif(p_status,''),'pending');
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if v_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Invalid status %', v_status;
  end if;

  v_user := p_user_id;
  if v_user is null then
    v_user := public.platform_find_user_id(p_user_email);
  end if;

  if p_is_admin then
    v_role := public.safe_org_role('admin');
    if v_role is null then
      raise exception 'org_role enum has no label "admin"';
    end if;
  else
    v_role := public.default_org_member_role();
  end if;

  insert into public.org_members(org_id, user_id, role, status, approved_at, approved_by)
  values (
    p_org_id,
    v_user,
    v_role,
    v_status,
    case when v_status='approved' then now() else null end,
    case when v_status='approved' then auth.uid() else null end
  )
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        status = excluded.status,
        approved_at = excluded.approved_at,
        approved_by = excluded.approved_by;

  return jsonb_build_object('ok', true, 'org_id', p_org_id, 'user_id', v_user, 'status', v_status, 'role', v_role::text);
end $$;

revoke all on function public.platform_add_member(uuid,text,uuid,boolean,text) from public;
grant execute on function public.platform_add_member(uuid,text,uuid,boolean,text) to authenticated;

-- ---------------------------------------------------------
-- Platform: promote/demote admin toggle (admin vs normal)
-- ---------------------------------------------------------
create or replace function public.platform_set_member_admin(
  p_org_id uuid,
  p_user_id uuid,
  p_is_admin boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_is_admin then
    v_role := public.safe_org_role('admin');
    if v_role is null then
      raise exception 'org_role enum has no label "admin"';
    end if;
  else
    v_role := public.default_org_member_role();
  end if;

  update public.org_members
  set role = v_role
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true, 'role', v_role::text);
end $$;

revoke all on function public.platform_set_member_admin(uuid,uuid,boolean) from public;
grant execute on function public.platform_set_member_admin(uuid,uuid,boolean) to authenticated;

-- ---------------------------------------------------------
-- Platform: remove member
-- ---------------------------------------------------------
create or replace function public.platform_remove_member(p_org_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  delete from public.org_members
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_remove_member(uuid,uuid) from public;
grant execute on function public.platform_remove_member(uuid,uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;