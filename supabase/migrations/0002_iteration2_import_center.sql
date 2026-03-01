-- CoffeeOps Executive BI
-- Iteration 2: Import Center v1 (file-centric pipeline shell)
--
-- Run this in Supabase Dashboard → SQL Editor AFTER running 0001.
--
-- What this migration does:
-- - Creates Import Center tables: import_jobs + import_job_rows (staging)
-- - Creates a private Storage bucket: imports
-- - Adds Storage RLS policies so org members can upload/read files under: <org_id>/<job_id>/...
-- - Adds RPC helpers for the UI shell: create_import_job, list_import_jobs, get_import_job
--
-- Notes:
-- - This is intentionally “shell-first” (no parsing/import logic yet).
-- - Edge Functions (Iteration 3+) can use the Service Role key and will bypass RLS.

begin;

-- =============================
-- Enums
-- =============================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'import_entity' and typnamespace = 'public'::regnamespace) then
    create type public.import_entity as enum (
      'sales',
      'expenses',
      'products',
      'labor',
      'unknown'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'import_job_status' and typnamespace = 'public'::regnamespace) then
    create type public.import_job_status as enum (
      'uploaded',
      'parsed',
      'validated',
      'imported',
      'failed'
    );
  end if;
end $$;

-- =============================
-- Tables
-- =============================

create table if not exists public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  entity_type public.import_entity not null,
  status public.import_job_status not null default 'uploaded',
  original_filename text not null check (char_length(original_filename) between 1 and 512),
  storage_bucket text not null default 'imports' check (storage_bucket = 'imports'),
  storage_path text not null check (char_length(storage_path) between 3 and 1024),
  file_size bigint,
  content_type text,
  metadata jsonb not null default '{}'::jsonb,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(org_id, storage_path)
);

create index if not exists import_jobs_org_id_created_at_idx on public.import_jobs(org_id, created_at desc);
create index if not exists import_jobs_org_id_status_idx on public.import_jobs(org_id, status);

comment on table public.import_jobs is 'One row per uploaded file. Drives the Import Center workflow.';

-- Staging rows (Iteration 3+ will populate this via Edge Functions)
create table if not exists public.import_job_rows (
  id bigserial primary key,
  job_id uuid not null references public.import_jobs(id) on delete cascade,
  row_number integer not null check (row_number >= 1),
  raw jsonb not null,
  is_valid boolean not null default true,
  errors jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique(job_id, row_number)
);

create index if not exists import_job_rows_job_id_idx on public.import_job_rows(job_id);

comment on table public.import_job_rows is 'Staged rows + row-level validation results for a specific import job.';

-- =============================
-- Timestamps
-- =============================

drop trigger if exists trg_import_jobs_set_updated_at on public.import_jobs;
create trigger trg_import_jobs_set_updated_at
before update on public.import_jobs
for each row
execute function public.set_updated_at();

-- =============================
-- Storage: bucket + RLS policies
-- =============================

-- Create bucket (idempotent)
insert into storage.buckets (id, name, public)
values ('imports', 'imports', false)
on conflict (id) do update
  set public = excluded.public;

-- Allow org members to access objects in the imports bucket that are stored under:
--   <org_id>/<job_id>/<filename>
-- Rationale: storage.objects.name stores the path.

-- READ
drop policy if exists imports_bucket_read on storage.objects;
create policy imports_bucket_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'imports'
  and exists (
    select 1
    from public.org_members m
    where m.user_id = auth.uid()
      and m.org_id::text = split_part(name, '/', 1)
  )
);

-- INSERT (upload)
drop policy if exists imports_bucket_insert on storage.objects;
create policy imports_bucket_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'imports'
  and exists (
    select 1
    from public.org_members m
    where m.user_id = auth.uid()
      and m.org_id::text = split_part(name, '/', 1)
  )
);

-- UPDATE
drop policy if exists imports_bucket_update on storage.objects;
create policy imports_bucket_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'imports'
  and exists (
    select 1
    from public.org_members m
    where m.user_id = auth.uid()
      and m.org_id::text = split_part(name, '/', 1)
  )
)
with check (
  bucket_id = 'imports'
  and exists (
    select 1
    from public.org_members m
    where m.user_id = auth.uid()
      and m.org_id::text = split_part(name, '/', 1)
  )
);

-- DELETE
drop policy if exists imports_bucket_delete on storage.objects;
create policy imports_bucket_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'imports'
  and exists (
    select 1
    from public.org_members m
    where m.user_id = auth.uid()
      and m.org_id::text = split_part(name, '/', 1)
  )
);

-- =============================
-- RLS: Import Center tables
-- =============================

alter table public.import_jobs enable row level security;
alter table public.import_job_rows enable row level security;

-- import_jobs: org members can read
drop policy if exists import_jobs_select_member on public.import_jobs;
create policy import_jobs_select_member
on public.import_jobs
for select
to authenticated
using (public.is_org_member(org_id));

-- import_jobs: org members can insert their own jobs
drop policy if exists import_jobs_insert_member on public.import_jobs;
create policy import_jobs_insert_member
on public.import_jobs
for insert
to authenticated
with check (
  public.is_org_member(org_id)
  and created_by = auth.uid()
);

-- import_jobs: org members can update jobs (status changes, metadata) within their org
drop policy if exists import_jobs_update_member on public.import_jobs;
create policy import_jobs_update_member
on public.import_jobs
for update
to authenticated
using (public.is_org_member(org_id))
with check (public.is_org_member(org_id));

-- import_job_rows: org members can read staged rows for jobs in their org
drop policy if exists import_job_rows_select_member on public.import_job_rows;
create policy import_job_rows_select_member
on public.import_job_rows
for select
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
-- RPC helpers
-- =============================

-- Create a job row after the file is uploaded to Storage.
create or replace function public.create_import_job(
  p_job_id uuid,
  p_org_id uuid,
  p_entity_type public.import_entity,
  p_original_filename text,
  p_storage_path text,
  p_file_size bigint,
  p_content_type text,
  p_metadata jsonb
)
returns public.import_jobs
language plpgsql
set search_path = public
as $$
declare
  v_row public.import_jobs;
  v_expected_prefix text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  v_expected_prefix := p_org_id::text || '/';
  if position(v_expected_prefix in p_storage_path) <> 1 then
    raise exception 'storage_path_must_start_with_org_id';
  end if;

  insert into public.import_jobs(
    id,
    org_id,
    created_by,
    entity_type,
    status,
    original_filename,
    storage_bucket,
    storage_path,
    file_size,
    content_type,
    metadata
  )
  values (
    p_job_id,
    p_org_id,
    auth.uid(),
    p_entity_type,
    'uploaded',
    p_original_filename,
    'imports',
    p_storage_path,
    p_file_size,
    p_content_type,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_import_job(uuid, uuid, public.import_entity, text, text, bigint, text, jsonb) to authenticated;

create or replace function public.list_import_jobs(
  p_org_id uuid,
  p_limit int default 50
)
returns setof public.import_jobs
language sql
stable
set search_path = public
as $$
  select *
  from public.import_jobs
  where org_id = p_org_id
  order by created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function public.list_import_jobs(uuid, int) to authenticated;

create or replace function public.get_import_job(
  p_job_id uuid
)
returns public.import_jobs
language sql
stable
set search_path = public
as $$
  select *
  from public.import_jobs
  where id = p_job_id
  limit 1;
$$;

grant execute on function public.get_import_job(uuid) to authenticated;

commit;
