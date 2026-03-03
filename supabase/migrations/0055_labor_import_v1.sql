begin;

-- ======================================================
-- 1) Canonical labor table
-- ======================================================
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
  updated_at timestamptz not null default now(),

  constraint labor_entries_employee_id_len check (char_length(employee_id) between 1 and 128),
  constraint labor_entries_role_len check (char_length(role) between 1 and 128)
);

-- updated_at trigger (your project already uses update_updated_at_column())
drop trigger if exists trg_labor_entries_set_updated_at on public.labor_entries;
create trigger trg_labor_entries_set_updated_at
before update on public.labor_entries
for each row execute function public.update_updated_at_column();

-- Dedupe: one row per employee per day per branch
do $$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname='public'
      and indexname='labor_entries_org_branch_day_emp_uidx'
  ) then
    create unique index labor_entries_org_branch_day_emp_uidx
      on public.labor_entries(org_id, branch_id, work_date, employee_id);
  end if;
end $$;

-- RLS: members can read; writes happen via importer
alter table public.labor_entries enable row level security;

drop policy if exists labor_entries_select_member on public.labor_entries;
create policy labor_entries_select_member
on public.labor_entries
for select to authenticated
using (public.is_org_member(org_id));

-- ======================================================
-- 2) Importer: labor_from_staging
-- ======================================================
create or replace function public.import_labor_from_staging(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_org uuid;
  v_valid int;
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

  v_org := v_job.org_id;

  if not public.is_org_member(v_org) then
    raise exception 'not authorized for org %', v_org;
  end if;

  select count(*) into v_valid
  from public.import_job_rows
  where job_id = p_job_id and is_valid = true;

  if v_valid = 0 then
    update public.import_jobs
    set status='imported'
    where id=p_job_id;

    return jsonb_build_object('ok', true, 'job_id', p_job_id, 'org_id', v_org, 'message', 'No valid staged rows to import.');
  end if;

  -- Ensure branch codes exist (best-effort, same pattern as sales import)
  insert into public.branches(org_id, name, code)
  select
    v_org,
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

  with src as (
    select
      v_org as org_id,
      coalesce(
        b.id,
        (select id from public.branches where org_id = v_org and is_default = true limit 1)
      ) as branch_id,
      nullif(trim(r.parsed->>'work_date'), '')::date as work_date,
      nullif(trim(r.parsed->>'employee_id'), '') as employee_id,
      nullif(trim(r.parsed->>'employee_name'), '') as employee_name,
      coalesce(nullif(trim(r.parsed->>'role'), ''), 'Unknown') as role,
      nullif(trim(r.parsed->>'hours'), '')::numeric as hours,
      nullif(trim(r.parsed->>'hourly_rate'), '')::numeric as hourly_rate,
      nullif(trim(r.parsed->>'cost'), '')::numeric as cost_raw,
      upper(nullif(trim(r.parsed->>'currency'), '')) as currency
    from public.import_job_rows r
    left join public.branches b
      on b.org_id = v_org
     and b.code = upper(nullif(trim(r.parsed->>'branch_code'), ''))
    where r.job_id = p_job_id and r.is_valid = true
  ), upserted as (
    insert into public.labor_entries(
      org_id, branch_id, work_date, employee_id, employee_name, role,
      hours, hourly_rate, cost, currency, source_import_job_id
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
      coalesce(cost_raw, hours * hourly_rate) as cost,
      currency,
      p_job_id
    from src
    where work_date is not null
      and employee_id is not null
      and branch_id is not null
      and hours is not null
      and hourly_rate is not null
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
  select count(*) into v_upserted from upserted;

  update public.import_jobs
  set
    status = 'imported',
    summary = jsonb_set(
      jsonb_set(coalesce(summary,'{}'::jsonb), '{valid_rows}', to_jsonb(v_valid), true),
      '{imported_rows}', to_jsonb(v_upserted), true
    )
  where id = p_job_id;

  return jsonb_build_object(
    'ok', true,
    'job_id', p_job_id,
    'org_id', v_org,
    'valid_rows', v_valid,
    'labor_rows_upserted', v_upserted
  );
end $$;

revoke all on function public.import_labor_from_staging(uuid) from public;
grant execute on function public.import_labor_from_staging(uuid) to authenticated;

-- ======================================================
-- 3) Wire labor into start_import_job()
-- ======================================================
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_res jsonb;
  v_cost jsonb;
  w int;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;

  if v_job.entity_type='products' then
    return public.import_products_from_staging(p_job_id);
  elsif v_job.entity_type='sales' then
    v_res := public.import_sales_from_staging(p_job_id);

    select coalesce(s.wac_days,30) into w
    from public.org_cost_engine_settings s
    where s.org_id = v_job.org_id;

    v_cost := public.apply_unit_economics_to_sales_job(p_job_id, w);
    return v_res || jsonb_build_object('unit_economics', v_cost);
  elsif v_job.entity_type='expenses' then
    v_res := public.import_expenses_from_staging(p_job_id);
    perform public.auto_allocate_expenses_for_job(p_job_id);
    return v_res;
  elsif v_job.entity_type='labor' then
    return public.import_labor_from_staging(p_job_id);
  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end $$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;