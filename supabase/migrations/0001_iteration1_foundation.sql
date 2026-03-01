-- CoffeeOps Executive BI
-- Iteration 1: Supabase Cloud foundation (Auth + Org model + RLS + bootstrap defaults + analytics schema)
--
-- Run this in Supabase Dashboard → SQL Editor.
--
-- Notes:
-- - This migration is intentionally safe to run on hosted Supabase (no local Supabase required).
-- - RLS is enabled and the app relies on org membership checks.

begin;

-- Extensions
create extension if not exists pgcrypto;

-- =============================
-- Enums
-- =============================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'org_role' and typnamespace = 'public'::regnamespace) then
    create type public.org_role as enum ('super_admin', 'admin', 'analyst', 'viewer');
  end if;
end $$;

-- =============================
-- Tables
-- =============================

-- User profile (1:1 with auth.users)
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'App-level user profile. Populated by trigger on auth.users.';

-- Orgs
create table if not exists public.orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

comment on table public.orgs is 'Organizations. All operational data is scoped to an org.';

-- Org membership
create table if not exists public.org_members (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.org_role not null default 'viewer',
  created_at timestamptz not null default now(),
  unique(org_id, user_id)
);

create index if not exists org_members_org_id_idx on public.org_members(org_id);
create index if not exists org_members_user_id_idx on public.org_members(user_id);

comment on table public.org_members is 'Users who can access an org (drives RLS).';

-- Branches
create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique(org_id, name)
);

create index if not exists branches_org_id_idx on public.branches(org_id);
create unique index if not exists branches_one_default_per_org on public.branches(org_id) where is_default;

comment on table public.branches is 'Physical branches/locations of the org.';

-- Cost centers
create table if not exists public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  code text not null check (char_length(code) between 1 and 64),
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  unique(org_id, code)
);

create index if not exists cost_centers_org_id_idx on public.cost_centers(org_id);

comment on table public.cost_centers is 'Cost centers used for overhead allocation.';

-- =============================
-- Timestamps
-- =============================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_set_updated_at on public.profiles;
create trigger trg_profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

-- =============================
-- Auth → profiles trigger
-- =============================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(user_id, email, full_name)
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data->>'full_name','')), '')
  )
  on conflict (user_id) do update
    set email = excluded.email,
        full_name = excluded.full_name,
        updated_at = now();

  return new;
end;
$$;

-- Recreate trigger idempotently
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'on_auth_user_created'
  ) THEN
    DROP TRIGGER on_auth_user_created ON auth.users;
  END IF;
END $$;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

-- =============================
-- Org bootstrap defaults
-- =============================

create or replace function public.org_bootstrap_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Default branch
  insert into public.branches(org_id, name, is_default)
  values (new.id, 'Main', true)
  on conflict do nothing;

  -- System cost centers
  insert into public.cost_centers(org_id, name, code, is_system)
  values
    (new.id, 'General Overhead', 'GENERAL_OVERHEAD', true),
    (new.id, 'Unassigned', 'UNASSIGNED', true)
  on conflict (org_id, code) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_org_bootstrap_defaults on public.orgs;
create trigger trg_org_bootstrap_defaults
after insert on public.orgs
for each row
execute function public.org_bootstrap_defaults();

-- =============================
-- First org member becomes super_admin (safety net)
-- =============================

create or replace function public.ensure_first_org_member_super_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  member_count int;
begin
  select count(*) into member_count
  from public.org_members
  where org_id = new.org_id;

  if member_count = 0 then
    new.role := 'super_admin';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_first_member_super_admin on public.org_members;
create trigger trg_first_member_super_admin
before insert on public.org_members
for each row
execute function public.ensure_first_org_member_super_admin();

-- =============================
-- Helper functions for RLS
-- =============================

create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.org_members m
    where m.org_id = p_org_id
      and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_org_super_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.org_members m
    where m.org_id = p_org_id
      and m.user_id = auth.uid()
      and m.role = 'super_admin'
  );
$$;

-- =============================
-- RPC: create_org
-- =============================

create or replace function public.create_org(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  v_name := trim(coalesce(p_name, ''));
  if char_length(v_name) < 2 then
    raise exception 'invalid_org_name';
  end if;

  insert into public.orgs(name, created_by)
  values (v_name, auth.uid())
  returning id into v_org_id;

  insert into public.org_members(org_id, user_id, role)
  values (v_org_id, auth.uid(), 'super_admin');

  return v_org_id;
end;
$$;

grant execute on function public.create_org(text) to authenticated;

-- =============================
-- RLS
-- =============================

alter table public.profiles enable row level security;
alter table public.orgs enable row level security;
alter table public.org_members enable row level security;
alter table public.branches enable row level security;
alter table public.cost_centers enable row level security;

-- Profiles
drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self
on public.profiles
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
on public.profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Orgs
drop policy if exists orgs_select_member on public.orgs;
create policy orgs_select_member
on public.orgs
for select
to authenticated
using (public.is_org_member(id));

drop policy if exists orgs_update_super_admin on public.orgs;
create policy orgs_update_super_admin
on public.orgs
for update
to authenticated
using (public.is_org_super_admin(id))
with check (public.is_org_super_admin(id));

-- Org members
drop policy if exists org_members_select_member on public.org_members;
create policy org_members_select_member
on public.org_members
for select
to authenticated
using (public.is_org_member(org_id));

-- Branches
drop policy if exists branches_select_member on public.branches;
create policy branches_select_member
on public.branches
for select
to authenticated
using (public.is_org_member(org_id));

-- Cost centers
drop policy if exists cost_centers_select_member on public.cost_centers;
create policy cost_centers_select_member
on public.cost_centers
for select
to authenticated
using (public.is_org_member(org_id));

-- =============================
-- Analytics schema (placeholder contracts)
-- =============================

create schema if not exists analytics;

-- This is a placeholder view to establish a stable contract early.
-- Later iterations will replace it with real KPI logic.
create or replace view analytics.v_kpi_daily as
select
  null::uuid as org_id,
  null::date as day,
  0::numeric as net_sales,
  0::numeric as gross_profit,
  0::numeric as expenses,
  0::numeric as operating_profit
where false;

-- Minimal privileges for authenticated users to read analytics views
grant usage on schema analytics to authenticated;
grant select on all tables in schema analytics to authenticated;

commit;
