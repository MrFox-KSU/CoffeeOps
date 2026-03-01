begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists analytics;

-- Canonical expenses table (aligned to template headers)
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  branch_id uuid null references public.branches(id) on delete set null,

  expense_date date not null,
  reference_number text null,
  vendor text null,
  cost_center_code text null,
  category text not null,

  amount numeric not null,
  vat_rate numeric null,
  tax_amount numeric null,
  total_amount numeric null,

  payment_method text null,
  notes text null,
  currency text null,

  source_import_job_id uuid null references public.import_jobs(id) on delete set null,
  source_hash text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Dedupe: (org_id, reference_number) when reference_number exists
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.expenses'::regclass and contype='u'
      and conname = 'expenses_org_reference_number_key'
  ) then
    execute 'alter table public.expenses add constraint expenses_org_reference_number_key unique (org_id, reference_number)';
  end if;
end $$;

-- Always-dedupe fallback: (org_id, source_hash)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.expenses'::regclass and contype='u'
      and conname = 'expenses_org_source_hash_key'
  ) then
    execute 'alter table public.expenses add constraint expenses_org_source_hash_key unique (org_id, source_hash)';
  end if;
end $$;

create index if not exists expenses_org_date_idx on public.expenses(org_id, expense_date desc);

-- updated_at trigger
create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_expenses_set_updated_at on public.expenses;
create trigger trg_expenses_set_updated_at
before update on public.expenses
for each row execute function public.update_updated_at_column();

-- RLS read
alter table public.expenses enable row level security;

drop policy if exists expenses_select_member on public.expenses;
create policy expenses_select_member
on public.expenses
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = expenses.org_id and m.user_id = auth.uid()));

-- Helper: stable hash from parsed json for dedupe fallback
create or replace function public.expense_source_hash(p jsonb)
returns text
language sql
immutable
set search_path = extensions, public
as $$
  select encode(digest(convert_to(coalesce(p::text,''), 'utf8'), 'sha256'), 'hex');
$$;
revoke all on function public.expense_source_hash(jsonb) from public;
grant execute on function public.expense_source_hash(jsonb) to authenticated, service_role;

-- Importer from staging -> canonical
create or replace function public.import_expenses_from_staging(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_org uuid;
  v_bad int;
  v_rows int;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;
  if v_job.entity_type <> 'expenses' then raise exception 'Only expenses supported'; end if;
  if v_job.status <> 'validated' then raise exception 'Job must be validated'; end if;

  v_org := v_job.org_id;

  if not public.is_org_member(v_org) then
    raise exception 'Forbidden';
  end if;

  select count(*) into v_bad from public.import_job_rows where job_id=p_job_id and is_valid=false;
  if v_bad > 0 then raise exception 'Cannot import: % invalid rows', v_bad; end if;

  -- Ensure branch exists for branch_code, if provided
  insert into public.branches(org_id, name, code)
  select distinct
    v_org,
    upper(trim(b.branch_code)) as name,
    upper(trim(b.branch_code)) as code
  from (
    select distinct nullif(trim(r.parsed->>'branch_code'), '') as branch_code
    from public.import_job_rows r
    where r.job_id=p_job_id and r.is_valid=true
  ) b
  where b.branch_code is not null
  on conflict (org_id, code) do update set name = excluded.name;

  with src as (
    select
      v_org as org_id,
      (r.parsed->>'expense_date')::date as expense_date,
      nullif(trim(r.parsed->>'reference_number'), '') as reference_number,
      nullif(trim(r.parsed->>'vendor'), '') as vendor,
      upper(nullif(trim(r.parsed->>'branch_code'), '')) as branch_code,
      nullif(trim(r.parsed->>'cost_center_code'), '') as cost_center_code,
      nullif(trim(r.parsed->>'category'), '') as category,
      (r.parsed->>'amount')::numeric as amount,
      nullif(trim(r.parsed->>'vat_rate'), '')::numeric as vat_rate,
      nullif(trim(r.parsed->>'tax_amount'), '')::numeric as tax_amount,
      nullif(trim(r.parsed->>'total_amount'), '')::numeric as total_amount,
      nullif(trim(r.parsed->>'payment_method'), '') as payment_method,
      nullif(trim(r.parsed->>'notes'), '') as notes,
      upper(nullif(trim(r.parsed->>'currency'), '')) as currency,
      r.parsed as parsed,
      p_job_id as source_import_job_id
    from public.import_job_rows r
    where r.job_id=p_job_id and r.is_valid=true
  ),
  src2 as (
    select
      s.*,
      b.id as branch_id,
      public.expense_source_hash(s.parsed) as source_hash
    from src s
    left join public.branches b
      on b.org_id=s.org_id and b.code=s.branch_code
  )
  insert into public.expenses(
    org_id, branch_id, expense_date, reference_number, vendor, cost_center_code, category,
    amount, vat_rate, tax_amount, total_amount, payment_method, notes, currency,
    source_import_job_id, source_hash
  )
  select
    org_id, branch_id, expense_date, reference_number, vendor, cost_center_code, category,
    amount, vat_rate, tax_amount, total_amount, payment_method, notes, currency,
    source_import_job_id, source_hash
  from src2
  on conflict (org_id, source_hash) do update set
    branch_id = excluded.branch_id,
    expense_date = excluded.expense_date,
    reference_number = excluded.reference_number,
    vendor = excluded.vendor,
    cost_center_code = excluded.cost_center_code,
    category = excluded.category,
    amount = excluded.amount,
    vat_rate = excluded.vat_rate,
    tax_amount = excluded.tax_amount,
    total_amount = excluded.total_amount,
    payment_method = excluded.payment_method,
    notes = excluded.notes,
    currency = excluded.currency,
    source_import_job_id = excluded.source_import_job_id,
    updated_at = now();

  get diagnostics v_rows = row_count;

  update public.import_jobs
  set status='imported',
      summary = jsonb_set(coalesce(summary,'{}'::jsonb), '{imported_rows}', to_jsonb(v_rows), true),
      updated_at = now()
  where id=p_job_id;

  return jsonb_build_object('ok', true, 'imported_rows', v_rows);
end $$;

revoke all on function public.import_expenses_from_staging(uuid) from public;
grant execute on function public.import_expenses_from_staging(uuid) to authenticated;

-- Update dispatcher
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_job public.import_jobs;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;

  if v_job.entity_type='products' then
    return public.import_products_from_staging(p_job_id);
  elsif v_job.entity_type='sales' then
    return public.import_sales_from_staging(p_job_id);
  elsif v_job.entity_type='expenses' then
    return public.import_expenses_from_staging(p_job_id);
  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end $$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

-- Analytics views
create or replace view analytics.v_expenses_enriched as
select
  e.org_id,
  e.expense_date as day,
  e.reference_number,
  e.vendor,
  e.branch_id,
  e.cost_center_code,
  e.category,
  e.amount,
  coalesce(e.tax_amount, 0) as tax_amount,
  coalesce(e.total_amount, (e.amount + coalesce(e.tax_amount,0))) as total_amount,
  e.payment_method,
  e.currency
from public.expenses e;

create or replace view analytics.v_expenses_daily as
select
  org_id,
  day,
  sum(amount) as amount,
  sum(tax_amount) as tax_amount,
  sum(total_amount) as total_amount,
  count(*) as expense_rows
from analytics.v_expenses_enriched
group by org_id, day;

grant usage on schema analytics to authenticated;
grant select on all tables in schema analytics to authenticated;

select pg_notify('pgrst','reload schema');

commit;
