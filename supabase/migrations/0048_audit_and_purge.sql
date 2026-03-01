begin;

-- =========================================================
-- A) Audit table (not directly selectable by authenticated)
-- =========================================================
create table if not exists public.platform_audit_log (
  id bigserial primary key,
  occurred_at timestamptz not null default now(),
  actor_user_id uuid,
  actor_email text,
  action text not null,
  entity text not null,
  entity_id text,
  org_id uuid,
  meta jsonb not null default '{}'::jsonb
);

create index if not exists platform_audit_log_occurred_idx on public.platform_audit_log(occurred_at desc);
create index if not exists platform_audit_log_org_idx on public.platform_audit_log(org_id, occurred_at desc);

revoke all on table public.platform_audit_log from public;
revoke all on table public.platform_audit_log from anon;
revoke all on table public.platform_audit_log from authenticated;

-- insert helper (called by triggers / security definer RPCs)
create or replace function public.platform_audit_insert(
  p_action text,
  p_entity text,
  p_entity_id text,
  p_org_id uuid default null,
  p_meta jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_actor uuid := auth.uid();
  v_email text;
begin
  select u.email into v_email from auth.users u where u.id = v_actor;

  insert into public.platform_audit_log(actor_user_id, actor_email, action, entity, entity_id, org_id, meta)
  values (v_actor, v_email, left(coalesce(p_action,''),80), left(coalesce(p_entity,''),80), left(coalesce(p_entity_id,''),120), p_org_id, coalesce(p_meta,'{}'::jsonb));
end $$;

revoke all on function public.platform_audit_insert(text,text,text,uuid,jsonb) from public;
revoke all on function public.platform_audit_insert(text,text,text,uuid,jsonb) from authenticated;

-- =========================================================
-- B) Audit triggers (membership requests + approvals + role changes + org changes)
-- =========================================================
create or replace function public.trg_audit_org_members()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.platform_audit_insert(
      'org_member_insert',
      'org_members',
      new.user_id::text,
      new.org_id,
      jsonb_build_object('status', new.status, 'role', new.role::text)
    );
    return new;
  elsif tg_op = 'UPDATE' then
    if (new.status is distinct from old.status) or (new.role is distinct from old.role) then
      perform public.platform_audit_insert(
        'org_member_update',
        'org_members',
        new.user_id::text,
        new.org_id,
        jsonb_build_object(
          'status_old', old.status, 'status_new', new.status,
          'role_old', old.role::text, 'role_new', new.role::text
        )
      );
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    perform public.platform_audit_insert(
      'org_member_delete',
      'org_members',
      old.user_id::text,
      old.org_id,
      jsonb_build_object('status', old.status, 'role', old.role::text)
    );
    return old;
  end if;

  return null;
end $$;

drop trigger if exists trg_audit_org_members on public.org_members;
create trigger trg_audit_org_members
after insert or update or delete on public.org_members
for each row execute function public.trg_audit_org_members();

create or replace function public.trg_audit_orgs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.platform_audit_insert(
      'org_insert',
      'orgs',
      new.id::text,
      new.id,
      jsonb_build_object('name', new.name, 'tier', new.subscription_tier_code, 'listed', new.is_listed)
    );
    return new;
  elsif tg_op = 'UPDATE' then
    if (new.subscription_tier_code is distinct from old.subscription_tier_code)
       or (new.is_listed is distinct from old.is_listed) then
      perform public.platform_audit_insert(
        'org_update',
        'orgs',
        new.id::text,
        new.id,
        jsonb_build_object(
          'tier_old', old.subscription_tier_code, 'tier_new', new.subscription_tier_code,
          'listed_old', old.is_listed, 'listed_new', new.is_listed
        )
      );
    end if;
    return new;
  end if;

  return new;
end $$;

drop trigger if exists trg_audit_orgs on public.orgs;
create trigger trg_audit_orgs
after insert or update on public.orgs
for each row execute function public.trg_audit_orgs();

-- =========================================================
-- C) Platform admin RPC: list audit logs
-- =========================================================
create or replace function public.platform_list_audit(p_days int default 30, p_limit int default 200)
returns table(
  occurred_at timestamptz,
  actor_email text,
  action text,
  entity text,
  entity_id text,
  org_id uuid,
  meta jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.occurred_at,
    a.actor_email,
    a.action,
    a.entity,
    a.entity_id,
    a.org_id,
    a.meta
  from public.platform_audit_log a
  where public.is_platform_admin()
    and a.occurred_at >= now() - (greatest(1, least(p_days, 365)) || ' days')::interval
  order by a.occurred_at desc
  limit greatest(1, least(p_limit, 1000));
$$;

revoke all on function public.platform_list_audit(int,int) from public;
grant execute on function public.platform_list_audit(int,int) to authenticated;

-- =========================================================
-- D) Sessions RPC: list sessions for a user
-- =========================================================
create or replace function public.platform_list_user_sessions(p_user_id uuid, p_limit int default 50)
returns table(
  org_id uuid,
  org_name text,
  started_at timestamptz,
  last_seen_at timestamptz,
  ended_at timestamptz,
  end_reason text,
  user_agent text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.org_id,
    o.name as org_name,
    s.started_at,
    s.last_seen_at,
    s.ended_at,
    s.end_reason,
    s.user_agent
  from public.user_sessions s
  join public.orgs o on o.id = s.org_id
  where public.is_platform_admin()
    and s.user_id = p_user_id
  order by s.started_at desc
  limit greatest(1, least(p_limit, 200));
$$;

revoke all on function public.platform_list_user_sessions(uuid,int) from public;
grant execute on function public.platform_list_user_sessions(uuid,int) to authenticated;

-- =========================================================
-- E) Improve platform_list_users last_seen/is_online (no return type change)
-- last_seen_at = max across all sessions
-- is_online = max(last_seen_at) among open sessions within 2 minutes
-- =========================================================
create or replace function public.platform_list_users(p_limit int default 200)
returns table(
  user_id uuid,
  email text,
  created_at timestamptz,
  last_seen_at timestamptz,
  is_online boolean,
  orgs jsonb
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with u as (
    select id, email, created_at
    from auth.users
    order by created_at desc
    limit greatest(1, least(p_limit, 1000))
  ),
  ls_all as (
    select user_id, max(last_seen_at) as last_seen_at
    from public.user_sessions
    group by user_id
  ),
  ls_open as (
    select user_id, max(last_seen_at) as open_last_seen
    from public.user_sessions
    where ended_at is null
    group by user_id
  ),
  mem as (
    select
      m.user_id,
      jsonb_agg(
        jsonb_build_object(
          'org_id', o.id,
          'org_name', o.name,
          'status', m.status,
          'role', m.role::text
        )
        order by o.name
      ) as orgs
    from public.org_members m
    join public.orgs o on o.id = m.org_id
    group by m.user_id
  )
  select
    u.id as user_id,
    u.email,
    u.created_at,
    ls_all.last_seen_at,
    (ls_open.open_last_seen is not null and now() - ls_open.open_last_seen <= interval '2 minutes') as is_online,
    coalesce(mem.orgs, '[]'::jsonb) as orgs
  from u
  left join ls_all on ls_all.user_id = u.id
  left join ls_open on ls_open.user_id = u.id
  left join mem on mem.user_id = u.id
  where public.is_platform_admin()
  order by u.created_at desc;
$$;

-- =========================================================
-- F) Purge/retention RPC (platform admin only)
-- =========================================================
create or replace function public.platform_close_stale_sessions()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v int;
begin
  if not public.is_platform_admin() then raise exception 'Forbidden'; end if;

  update public.user_sessions
  set ended_at = (last_seen_at + interval '15 minutes'),
      end_reason = 'timeout'
  where ended_at is null
    and now() - last_seen_at > interval '15 minutes';

  get diagnostics v = row_count;
  return v;
end $$;

revoke all on function public.platform_close_stale_sessions() from public;
grant execute on function public.platform_close_stale_sessions() to authenticated;

create or replace function public.platform_purge_activity(
  p_keep_sessions_days int default 90,
  p_keep_daily_days int default 180,
  p_keep_audit_days int default 365
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_closed int := 0;
  v_sess int := 0;
  v_du int := 0;
  v_pv int := 0;
  v_a int := 0;
begin
  if not public.is_platform_admin() then raise exception 'Forbidden'; end if;

  v_closed := public.platform_close_stale_sessions();

  delete from public.user_sessions
  where ended_at is not null
    and ended_at < now() - (greatest(1, least(p_keep_sessions_days, 3650)) || ' days')::interval;
  get diagnostics v_sess = row_count;

  delete from public.user_daily_usage
  where day < current_date - (greatest(1, least(p_keep_daily_days, 3650)) - 1);
  get diagnostics v_du = row_count;

  delete from public.user_page_views_daily
  where day < current_date - (greatest(1, least(p_keep_daily_days, 3650)) - 1);
  get diagnostics v_pv = row_count;

  delete from public.platform_audit_log
  where occurred_at < now() - (greatest(1, least(p_keep_audit_days, 3650)) || ' days')::interval;
  get diagnostics v_a = row_count;

  return jsonb_build_object(
    'ok', true,
    'closed_stale_sessions', v_closed,
    'sessions_deleted', v_sess,
    'daily_usage_deleted', v_du,
    'page_views_deleted', v_pv,
    'audit_deleted', v_a
  );
end $$;

revoke all on function public.platform_purge_activity(int,int,int) from public;
grant execute on function public.platform_purge_activity(int,int,int) to authenticated;

select pg_notify('pgrst','reload schema');
commit;