begin;

-- Ensure row_number exists (if row_index exists, rename it back)
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public' and table_name='import_job_rows' and column_name='row_number'
  ) then
    if exists (
      select 1
      from information_schema.columns
      where table_schema='public' and table_name='import_job_rows' and column_name='row_index'
    ) then
      execute 'alter table public.import_job_rows rename column row_index to row_number';
    else
      execute 'alter table public.import_job_rows add column row_number integer';
    end if;
  end if;
end $$;

-- Recompute row_number deterministically for ALL existing staging rows
with ranked as (
  select
    ctid,
    row_number() over (partition by job_id order by ctid) as rn
  from public.import_job_rows
)
update public.import_job_rows r
set row_number = ranked.rn
from ranked
where r.ctid = ranked.ctid;

-- Enforce invariants
alter table public.import_job_rows
  alter column row_number set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'import_job_rows_row_number_check'
  ) then
    execute 'alter table public.import_job_rows add constraint import_job_rows_row_number_check check (row_number >= 1)';
  end if;
end $$;

-- Ensure a stable unique index exists (idempotent)
do $$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname='public'
      and tablename='import_job_rows'
      and indexname='import_job_rows_job_id_row_number_uidx'
  ) then
    execute 'create unique index import_job_rows_job_id_row_number_uidx on public.import_job_rows(job_id, row_number)';
  end if;
end $$;

-- Force PostgREST schema cache reload
select pg_notify('pgrst', 'reload schema');

commit;
