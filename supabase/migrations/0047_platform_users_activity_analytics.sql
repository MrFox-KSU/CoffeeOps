begin;

create extension if not exists pgcrypto;

-- =========================================================
-- A) Activity tables (daily aggregates, not raw events)
-- =========================================================

create table if not exists public.user_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  org_id uuid not null references public.orgs(id) on delete cascade,
  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  ended_at timestamptz,
  end_reason text,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists user_sessions_user_last_seen_idx on public.user_sessions(user_id, last_seen_at desc);
create index if not exists user_sessions_org_last_seen_idx on public.user_sessions(org_id, last_seen_at desc);
create index if not exists user_sessions_open_idx on public.user_sessions(user_id) where ended_at is null;

create table if not exists public.user_daily_usage (
  user_id uuid not null,
  org_id uuid not null references public.orgs(id) on delete cascade,
  day date not null,
  active_seconds int not null default 0 check (active_seconds >= 0),
  sessions int not null default 0 check (sessions >= 0),
  last_at timestamptz not null default now(),
  primary key (user_id, org_id, day)
);

create table if not exists public.user_page_views_daily (
  user_id uuid not null,
  org_id uuid not null references public.orgs(id) on delete cascade,
  day date not null,
  path text not null,
  views int not null default 0 check (views >= 0),
  last_at timestamptz not null default now(),
  primary key (user_id, org_id, day, path)
);

-- RLS: platform admin can read; no direct client writes (RPCs are security definer)
alter table public.user_sessions enable row level security;
alter table public.user_daily_usage enable row level security;
alter table public.user_page_views_daily enable row level security;

drop policy if exists user_sessions_select_platform on public.user_sessions;
create policy user_sessions_select_platform on public.user_sessions
for select to authenticated
using (public.is_platform_admin());

drop policy if exists user_daily_usage_select_platform on public.user_daily_usage;
create policy user_daily_usage_select_platform on public.user_daily_usage
for select to authenticated
using (public.is_platform_admin());

drop policy if exists user_page_views_daily_select_platform on public.user_page_views_daily;
create policy user_page_views_daily_select_platform on public.user_page_views_daily
for select to authenticated
using (public.is_platform_admin());

-- =========================================================
-- B) Tracking RPCs (dashboard-only)
-- Online threshold = 2 minutes
-- Session timeout = 15 minutes
-- =========================================================

create or replace function public.track_user_session_start(p_org_id uuid, p_user_agent text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  -- close stale open sessions for this user/org (timeout 15 min)
  update public.user_sessions
  set ended_at = (last_seen_at + interval '15 minutes'),
      end_reason = 'timeout'
  where user_id = v_user
    and org_id = p_org_id
    and ended_at is null
    and now() - last_seen_at > interval '15 minutes';

  insert into public.user_sessions(user_id, org_id, user_agent)
  values (v_user, p_org_id, left(coalesce(p_user_agent,''), 400))
  returning id into v_id;

  insert into public.user_daily_usage(user_id, org_id, day, sessions, active_seconds, last_at)
  values (v_user, p_org_id, current_date, 1, 0, now())
  on conflict (user_id, org_id, day) do update
    set sessions = public.user_daily_usage.sessions + 1,
        last_at = now();

  return v_id;
end $$;

revoke all on function public.track_user_session_start(uuid,text) from public;
grant execute on function public.track_user_session_start(uuid,text) to authenticated;

create or replace function public.track_user_session_heartbeat(
  p_session_id uuid,
  p_org_id uuid,
  p_delta_seconds int default 60
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  d int := greatest(0, least(coalesce(p_delta_seconds,0), 120));
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  update public.user_sessions
  set last_seen_at = now()
  where id = p_session_id and user_id = v_user and org_id = p_org_id and ended_at is null;

  if d > 0 then
    insert into public.user_daily_usage(user_id, org_id, day, active_seconds, sessions, last_at)
    values (v_user, p_org_id, current_date, d, 0, now())
    on conflict (user_id, org_id, day) do update
      set active_seconds = public.user_daily_usage.active_seconds + d,
          last_at = now();
  end if;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.track_user_session_heartbeat(uuid,uuid,int) from public;
grant execute on function public.track_user_session_heartbeat(uuid,uuid,int) to authenticated;

create or replace function public.track_user_session_end(p_session_id uuid, p_reason text default 'logout')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  update public.user_sessions
  set ended_at = now(),
      end_reason = left(coalesce(p_reason,'logout'), 50),
      last_seen_at = now()
  where id = p_session_id and user_id = v_user and ended_at is null;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.track_user_session_end(uuid,text) from public;
grant execute on function public.track_user_session_end(uuid,text) to authenticated;

create or replace function public.track_user_page_view(p_org_id uuid, p_path text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_path text := coalesce(p_path,'');
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  -- Dashboard-only analytics (your choice 3A)
  if left(v_path, 10) <> '/dashboard' then
    return jsonb_build_object('ok', true, 'skipped', true);
  end if;

  insert into public.user_page_views_daily(user_id, org_id, day, path, views, last_at)
  values (v_user, p_org_id, current_date, v_path, 1, now())
  on conflict (user_id, org_id, day, path) do update
    set views = public.user_page_views_daily.views + 1,
        last_at = now();

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.track_user_page_view(uuid,text) from public;
grant execute on function public.track_user_page_view(uuid,text) to authenticated;

-- =========================================================
-- C) Role mapping to avoid enum guessing
-- =========================================================
create table if not exists public.platform_role_mappings (
  kind text primary key check (kind in ('admin','member')),
  role_label text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

alter table public.platform_role_mappings enable row level security;

drop policy if exists platform_role_mappings_select on public.platform_role_mappings;
create policy platform_role_mappings_select
on public.platform_role_mappings for select to authenticated
using (public.is_platform_admin());

drop policy if exists platform_role_mappings_write on public.platform_role_mappings;
create policy platform_role_mappings_write
on public.platform_role_mappings for all to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin());

create or replace function public.platform_list_org_role_labels()
returns table(role_label text)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select e.enumlabel::text
  from pg_type t
  join pg_enum e on e.enumtypid = t.oid
  where t.typname = 'org_role'
  order by e.enumsortorder;
$$;

revoke all on function public.platform_list_org_role_labels() from public;
grant execute on function public.platform_list_org_role_labels() to authenticated;

create or replace function public.platform_get_role_mappings()
returns table(kind text, role_label text)
language sql
stable
security definer
set search_path = public
as $$
  select m.kind, m.role_label
  from public.platform_role_mappings m
  where public.is_platform_admin()
  order by m.kind;
$$;

revoke all on function public.platform_get_role_mappings() from public;
grant execute on function public.platform_get_role_mappings() to authenticated;

create or replace function public.platform_set_role_mapping(p_kind text, p_role_label text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v public.org_role;
begin
  if not public.is_platform_admin() then raise exception 'Forbidden'; end if;
  if p_kind not in ('admin','member') then raise exception 'Invalid kind'; end if;

  v := public.safe_org_role(p_role_label);
  if v is null then
    raise exception 'Invalid org_role label: %', p_role_label;
  end if;

  insert into public.platform_role_mappings(kind, role_label, updated_at, updated_by)
  values (p_kind, p_role_label, now(), auth.uid())
  on conflict (kind) do update
    set role_label = excluded.role_label,
        updated_at = now(),
        updated_by = auth.uid();

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_set_role_mapping(text,text) from public;
grant execute on function public.platform_set_role_mapping(text,text) to authenticated;

-- Seed mappings deterministically
insert into public.platform_role_mappings(kind, role_label)
values
  ('member', (public.default_org_member_role())::text),
  ('admin',  coalesce('admin', (public.default_org_member_role())::text))
on conflict (kind) do nothing;

-- =========================================================
-- D) Platform user directory RPCs
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
  ls as (
    select user_id, max(last_seen_at) as last_seen_at
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
    ls.last_seen_at,
    (ls.last_seen_at is not null and now() - ls.last_seen_at <= interval '2 minutes') as is_online,
    coalesce(mem.orgs, '[]'::jsonb) as orgs
  from u
  left join ls on ls.user_id = u.id
  left join mem on mem.user_id = u.id
  where public.is_platform_admin()
  order by u.created_at desc;
$$;

revoke all on function public.platform_list_users(int) from public;
grant execute on function public.platform_list_users(int) to authenticated;

create or replace function public.platform_get_user_daily(p_user_id uuid, p_days int default 14)
returns table(day date, active_seconds int, sessions int, page_views int)
language sql
stable
security definer
set search_path = public
as $$
  with d as (
    select generate_series(current_date - (greatest(1, least(p_days, 180)) - 1), current_date, interval '1 day')::date as day
  ),
  u as (
    select day, sum(active_seconds)::int as active_seconds, sum(sessions)::int as sessions
    from public.user_daily_usage
    where user_id = p_user_id and day >= (current_date - (greatest(1, least(p_days, 180)) - 1))
    group by day
  ),
  pv as (
    select day, sum(views)::int as page_views
    from public.user_page_views_daily
    where user_id = p_user_id and day >= (current_date - (greatest(1, least(p_days, 180)) - 1))
    group by day
  )
  select
    d.day,
    coalesce(u.active_seconds,0),
    coalesce(u.sessions,0),
    coalesce(pv.page_views,0)
  from d
  left join u on u.day = d.day
  left join pv on pv.day = d.day
  where public.is_platform_admin()
  order by d.day desc;
$$;

revoke all on function public.platform_get_user_daily(uuid,int) from public;
grant execute on function public.platform_get_user_daily(uuid,int) to authenticated;

create or replace function public.platform_get_user_pageviews(p_user_id uuid, p_days int default 7)
returns table(day date, path text, views int)
language sql
stable
security definer
set search_path = public
as $$
  select
    day,
    path,
    sum(views)::int as views
  from public.user_page_views_daily
  where user_id = p_user_id
    and day >= (current_date - (greatest(1, least(p_days, 180)) - 1))
    and public.is_platform_admin()
  group by day, path
  order by day desc, views desc, path asc;
$$;

revoke all on function public.platform_get_user_pageviews(uuid,int) from public;
grant execute on function public.platform_get_user_pageviews(uuid,int) to authenticated;

create or replace function public.platform_set_member_role_kind(p_org_id uuid, p_user_id uuid, p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label text;
  v_role public.org_role;
begin
  if not public.is_platform_admin() then raise exception 'Forbidden'; end if;
  if p_kind not in ('admin','member') then raise exception 'Invalid kind'; end if;

  select role_label into v_label
  from public.platform_role_mappings
  where kind = p_kind;

  if v_label is null then
    raise exception 'Role mapping missing for kind=%', p_kind;
  end if;

  v_role := public.safe_org_role(v_label);
  if v_role is null then
    raise exception 'Invalid mapped role label=%', v_label;
  end if;

  update public.org_members
  set role = v_role
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true, 'role', v_role::text);
end $$;

revoke all on function public.platform_set_member_role_kind(uuid,uuid,text) from public;
grant execute on function public.platform_set_member_role_kind(uuid,uuid,text) to authenticated;

select pg_notify('pgrst','reload schema');
commit;