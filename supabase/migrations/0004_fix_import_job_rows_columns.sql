begin;

-- 1) If an older column name exists, normalize it to `parsed`
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'import_job_rows'
      and column_name = 'parsed_row'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'import_job_rows'
      and column_name = 'parsed'
  ) then
    execute 'alter table public.import_job_rows rename column parsed_row to parsed';
  end if;
end $$;

-- 2) Ensure the staging contract columns exist (idempotent)
alter table public.import_job_rows
  add column if not exists raw     jsonb  not null default '{}'::jsonb,
  add column if not exists parsed  jsonb  not null default '{}'::jsonb,
  add column if not exists is_valid boolean not null default true,
  add column if not exists errors  text[] not null default '{}'::text[];

-- 3) Force PostgREST to reload schema cache (delivered on COMMIT)
select pg_notify('pgrst', 'reload schema');

commit;
