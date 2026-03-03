begin;

-- -------------------------------------------------------------------
-- A) Ensure canonical labor table exists (safe if already created)
-- -------------------------------------------------------------------
create table if not exists public.labor_entries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  work_date date not null,
  employee_id text not null,
  employee_name text,
  role text not null,
  hours numeric not null check (hours > 0),
  hourly_rate numeric not null check (hourly_rate >= 0),
  cost numeric not null check (cost >= 0),
  currency text,
  source_import_job_id uuid references public.import_jobs(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_labor_entries_set_updated_at on public.labor_entries;
create trigger trg_labor_entries_set_updated_at
before update on public.labor_entries
for each row execute function public.update_updated_at_column();

do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='labor_entries_org_branch_day_emp_uidx'
  ) then
    create unique index labor_entries_org_branch_day_emp_uidx
      on public.labor_entries(org_id, branch_id, work_date, employee_id);
  end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='labor_entries_org_branch_day_idx'
  ) then
    create index labor_entries_org_branch_day_idx
      on public.labor_entries(org_id, branch_id, work_date);
  end if;
end $$;

alter table public.labor_entries enable row level security;

drop policy if exists labor_entries_select_member on public.labor_entries;
create policy labor_entries_select_member
on public.labor_entries
for select to authenticated
using (public.is_org_member(org_id));

-- -------------------------------------------------------------------
-- B) Labor importer: staging -> labor_entries (idempotent)
-- -------------------------------------------------------------------
create or replace function public.import_labor_from_staging(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_org_id uuid;
  v_valid_rows int;
  v_upserted int;
begin
  select * into v_job
  from public.import_jobs
  where id = p_job_id;

  if not found then
    raise exception 'import job % not found', p_job_id;
  end if;

  if v_job.entity_type <> 'labor' then
    raise exception 'import_labor_from_staging only supports entity_type=labor (got %)', v_job.entity_type;
  end if;

  v_org_id := v_job.org_id;

  if not public.is_org_member(v_org_id) then
    raise exception 'not authorized for org %', v_org_id;
  end if;

  select count(*) into v_valid_rows
  from public.import_job_rows
  where job_id = p_job_id and is_valid = true;

  if v_valid_rows = 0 then
    return jsonb_build_object(
      'ok', true,
      'job_id', p_job_id,
      'org_id', v_org_id,
      'message', 'No valid staged rows to import.'
    );
  end if;

  -- Ensure branch codes exist (best-effort)
  insert into public.branches(org_id, name, code)
  select
    v_org_id,
    upper(trim(b.branch_code)) as name,
    upper(trim(b.branch_code)) as code
  from (
    select distinct nullif(trim(r.parsed->>'branch_code'), '') as branch_code
    from public.import_job_rows r
    where r.job_id = p_job_id and r.is_valid = true
  ) b
  where b.branch_code is not null
  on conflict (org_id, code) do update
    set name = excluded.name;

  with default_branch as (
    select id
    from public.branches
    where org_id = v_org_id and is_default = true
    limit 1
  ),
  src as (
    select
      v_org_id as org_id,
      coalesce(
        b.id,
        (select id from default_branch)
      ) as branch_id,
      nullif(trim(r.parsed->>'work_date'), '')::date as work_date,
      nullif(trim(r.parsed->>'employee_id'), '') as employee_id,
      nullif(trim(r.parsed->>'employee_name'), '') as employee_name,
      public.norm_dim(r.parsed->>'role') as role,
      coalesce(nullif(trim(r.parsed->>'hours'), ''), '0')::numeric as hours,
      coalesce(nullif(trim(r.parsed->>'hourly_rate'), ''), '0')::numeric as hourly_rate,
      nullif(trim(r.parsed->>'cost'), '')::numeric as cost_in,
      upper(nullif(trim(r.parsed->>'currency'), '')) as currency
    from public.import_job_rows r
    left join public.branches b
      on b.org_id = v_org_id
     and b.code = upper(nullif(trim(r.parsed->>'branch_code'), ''))
    where r.job_id = p_job_id and r.is_valid = true
  ),
  upsert as (
    insert into public.labor_entries(
      org_id, branch_id, work_date,
      employee_id, employee_name, role,
      hours, hourly_rate, cost, currency,
      source_import_job_id
    )
    select
      org_id,
      branch_id,
      work_date,
      employee_id,
      employee_name,
      role,
      hours,
      hourly_rate,
      coalesce(cost_in, round(hours * hourly_rate, 4)) as cost,
      currency,
      p_job_id
    from src
    where branch_id is not null and work_date is not null and employee_id is not null
    on conflict (org_id, branch_id, work_date, employee_id) do update set
      employee_name = excluded.employee_name,
      role = excluded.role,
      hours = excluded.hours,
      hourly_rate = excluded.hourly_rate,
      cost = excluded.cost,
      currency = excluded.currency,
      source_import_job_id = excluded.source_import_job_id,
      updated_at = now()
    returning 1
  )
  select count(*) into v_upserted from upsert;

  -- Mark job imported (same pattern as expenses/products)
  update public.import_jobs
  set
    status = 'imported',
    summary = jsonb_set(coalesce(summary,'{}'::jsonb), '{imported_rows}', to_jsonb(v_upserted), true),
    updated_at = now()
  where id = p_job_id;

  return jsonb_build_object(
    'ok', true,
    'job_id', p_job_id,
    'org_id', v_org_id,
    'valid_rows', v_valid_rows,
    'labor_rows_upserted', v_upserted
  );
end;
$$;

revoke all on function public.import_labor_from_staging(uuid) from public;
grant execute on function public.import_labor_from_staging(uuid) to authenticated;

-- -------------------------------------------------------------------
-- C) Wire labor into start_import_job (no guesswork: explicit branch)
-- -------------------------------------------------------------------
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_res jsonb;
  w int := 30;
  v_cost jsonb;
begin
  select * into v_job from public.import_jobs where id = p_job_id;
  if not found then
    raise exception 'Import job % not found', p_job_id;
  end if;

  if v_job.entity_type = 'products' then
    v_res := public.import_products_from_staging(p_job_id);
    return v_res;

  elsif v_job.entity_type = 'sales' then
    v_res := public.import_sales_from_staging(p_job_id);

    select coalesce(s.wac_days,30) into w
    from public.org_cost_engine_settings s
    where s.org_id = v_job.org_id;

    v_cost := public.apply_unit_economics_to_sales_job(p_job_id, w);
    return v_res || jsonb_build_object('unit_economics', v_cost);

  elsif v_job.entity_type = 'expenses' then
    v_res := public.import_expenses_from_staging(p_job_id);
    perform public.auto_allocate_expenses_for_job(p_job_id);
    return v_res;

  elsif v_job.entity_type = 'labor' then
    v_res := public.import_labor_from_staging(p_job_id);
    return v_res;

  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end;
$$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;