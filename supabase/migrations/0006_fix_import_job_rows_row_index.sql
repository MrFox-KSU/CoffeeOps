begin;

-- Ensure row_index exists
alter table public.import_job_rows
  add column if not exists row_index integer;

-- Backfill any existing rows where row_index is NULL
with ranked as (
  select
    ctid,
    row_number() over (partition by job_id order by ctid) as rn
  from public.import_job_rows
  where row_index is null
)
update public.import_job_rows r
set row_index = ranked.rn
from ranked
where r.ctid = ranked.ctid;

-- Enforce not-null + sanity constraint
alter table public.import_job_rows
  alter column row_index set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'import_job_rows_row_index_positive'
  ) then
    execute 'alter table public.import_job_rows add constraint import_job_rows_row_index_positive check (row_index > 0)';
  end if;
end $$;

-- Force PostgREST schema cache reload
select pg_notify('pgrst', 'reload schema');

commit;
