begin;

-- ---------------------------------------------------------
-- A) Choose a safe default org role from the enum (no guesswork)
--    Preference order: viewer -> read_only -> analyst -> user -> member
--    Then fallback: first non-admin/super_admin/owner by enumsortorder
-- ---------------------------------------------------------
create or replace function public.default_org_member_role()
returns public.org_role
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  with ev as (
    select e.enumlabel, e.enumsortorder
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'org_role'
  )
  select
    coalesce(
      (
        select enumlabel::public.org_role
        from ev
        order by
          case enumlabel
            when 'viewer' then 1
            when 'read_only' then 2
            when 'analyst' then 3
            when 'user' then 4
            when 'member' then 5
            else 100
          end,
          enumsortorder
        limit 1
      ),
      (
        select enumlabel::public.org_role
        from ev
        where enumlabel not in ('super_admin','admin','owner')
        order by enumsortorder
        limit 1
      ),
      (
        select enumlabel::public.org_role
        from ev
        order by enumsortorder
        limit 1
      )
    );
$$;

revoke all on function public.default_org_member_role() from public;
grant execute on function public.default_org_member_role() to authenticated;

-- ---------------------------------------------------------
-- B) Safe "try cast" from text -> org_role (returns NULL if invalid)
-- ---------------------------------------------------------
create or replace function public.safe_org_role(p text)
returns public.org_role
language plpgsql
immutable
security definer
set search_path = public, pg_catalog
as $$
declare v public.org_role;
begin
  if p is null or length(trim(p)) = 0 then
    return null;
  end if;

  if exists (
    select 1
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'org_role'
      and e.enumlabel = p
  ) then
    execute format('select %L::public.org_role', p) into v;
    return v;
  end if;

  return null;
end $$;

revoke all on function public.safe_org_role(text) from public;
grant execute on function public.safe_org_role(text) to authenticated;

-- ---------------------------------------------------------
-- C) Fix request_org_access: never use hardcoded "member"
-- ---------------------------------------------------------
create or replace function public.request_org_access(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role public.org_role;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  v_role := public.default_org_member_role();

  insert into public.org_members(org_id, user_id, role, status)
  values (p_org_id, v_user, v_role, 'pending')
  on conflict (org_id, user_id) do update
    set status = 'pending',
        role = excluded.role;

  return jsonb_build_object('ok', true, 'org_id', p_org_id);
end $$;

revoke all on function public.request_org_access(uuid) from public;
grant execute on function public.request_org_access(uuid) to authenticated;

-- ---------------------------------------------------------
-- D) Fix platform_set_member_status:
--    - if approving and role missing/invalid -> use default role
--    - if role invalid -> ignore instead of crashing
-- ---------------------------------------------------------
create or replace function public.platform_set_member_status(
  p_org_id uuid,
  p_user_id uuid,
  p_status text,
  p_role text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Invalid status: %', p_status;
  end if;

  if p_status = 'approved' then
    v_role := coalesce(public.safe_org_role(p_role), public.default_org_member_role());
  else
    v_role := public.safe_org_role(p_role);
  end if;

  update public.org_members
  set
    status = p_status,
    role = coalesce(v_role, role)
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_set_member_status(uuid,uuid,text,text) from public;
grant execute on function public.platform_set_member_status(uuid,uuid,text,text) to authenticated;

select pg_notify('pgrst','reload schema');
commit;