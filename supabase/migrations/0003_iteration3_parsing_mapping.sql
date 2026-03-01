-- CoffeeOps Executive BI
-- Iteration 3: CSV parsing + mapping UI + row-level validations
--
-- Run this in Supabase Dashboard → SQL Editor AFTER running 0001 and 0002.
--
-- This migration focuses on:
-- - Fixing Postgres privileges for authenticated role (required for PostgREST access)
-- - Adding missing RLS policies for staging inserts/deletes (import_job_rows)
-- - Adding helper RPCs for safe org listing + job row listing
--
-- NOTE:
-- Supabase uses PostgREST. Even with RLS policies, the authenticated role still needs
-- explicit GRANT privileges on tables/sequences.

begin;

-- =============================
-- Privileges (authenticated)
-- =============================

-- Schema usage
grant usage on schema public to authenticated;

-- Table privileges (RLS still enforces row access)
grant select, insert, update, delete on table
  public.profiles,
  public.orgs,
  public.org_members,
  public.branches,
  public.cost_centers,
  public.import_jobs,
  public.import_job_rows
to authenticated;

-- Sequence privileges (bigserial on import_job_rows)
grant usage, select on all sequences in schema public to authenticated;

-- Ensure future tables/sequences created by postgres in schema public remain accessible
alter default privileges in schema public
grant select, insert, update, delete on tables to authenticated;

alter default privileges in schema public
grant usage, select on sequences to authenticated;

-- =============================
-- RLS: import_job_rows write policies (required for Edge Function parsing)
-- =============================

-- Insert staged rows
drop policy if exists import_job_rows_insert_member on public.import_job_rows;
create policy import_job_rows_insert_member
on public.import_job_rows
for insert
to authenticated
with check (
  exists (
    select 1
    from public.import_jobs j
    where j.id = import_job_rows.job_id
      and public.is_org_member(j.org_id)
  )
);

-- Delete staged rows (re-run parse)
drop policy if exists import_job_rows_delete_member on public.import_job_rows;
create policy import_job_rows_delete_member
on public.import_job_rows
for delete
to authenticated
using (
  exists (
    select 1
    from public.import_jobs j
    where j.id = import_job_rows.job_id
      and public.is_org_member(j.org_id)
  )
);

-- =============================
-- RPC: list_my_orgs (avoid direct orgs/org_members reads in the UI)
-- =============================

create or replace function public.list_my_orgs()
returns table(
  id uuid,
  name text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select o.id, o.name, o.created_at
  from public.orgs o
  join public.org_members m on m.org_id = o.id
  where m.user_id = auth.uid()
  order by o.created_at asc;
$$;

grant execute on function public.list_my_orgs() to authenticated;

-- =============================
-- RPC: list_import_job_rows (preview)
-- =============================

create or replace function public.list_import_job_rows(
  p_job_id uuid,
  p_limit int default 200
)
returns setof public.import_job_rows
language sql
stable
set search_path = public
as $$
  select *
  from public.import_job_rows
  where job_id = p_job_id
  order by row_number asc
  limit greatest(1, least(p_limit, 1000));
$$;

grant execute on function public.list_import_job_rows(uuid, int) to authenticated;

-- =============================
-- RPC: save_import_job_mapping (store mapping inside metadata->mapping)
-- =============================

create or replace function public.save_import_job_mapping(
  p_job_id uuid,
  p_mapping jsonb
)
returns public.import_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_org_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select org_id into v_org_id
  from public.import_jobs
  where id = p_job_id;

  if v_org_id is null then
    raise exception 'not_found';
  end if;

  if not public.is_org_member(v_org_id) then
    raise exception 'not_authorized';
  end if;

  update public.import_jobs
  set metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{mapping}', coalesce(p_mapping, '{}'::jsonb), true),
      updated_at = now()
  where id = p_job_id
  returning * into v_job;

  return v_job;
end;
$$;

grant execute on function public.save_import_job_mapping(uuid, jsonb) to authenticated;

commit;
