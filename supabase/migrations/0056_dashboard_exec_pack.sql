begin;

-- =========================================================
-- A) Labor table (so labor imports + dashboard labor works)
-- =========================================================
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

-- =========================================================
-- B) Exec daily KPI series (org + optional branch)
-- =========================================================
create or replace function public.get_exec_daily(
  p_org_id uuid,
  p_branch_id uuid default null,
  p_days int default 90
)
returns table(
  day date,
  net_sales numeric,
  cogs_total numeric,
  gross_profit numeric,
  expenses_total numeric,
  labor_total numeric,
  net_profit numeric,
  invoices int,
  gross_margin numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with lim as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(7, least(p_days, 3650))::int as d
  ),
  w as (
    select (a - (d-1))::date as start_day, a::date as end_day from lim
  ),
  days as (
    select generate_series((select start_day from w), (select end_day from w), interval '1 day')::date as day
  ),
  s as (
    select
      inv.invoice_date as day,
      sum(si.net_sales) as net_sales,
      sum(si.cogs_total) as cogs_total,
      count(distinct inv.external_invoice_number)::int as invoices
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    cross join w
    where inv.org_id = p_org_id
      and inv.invoice_date between w.start_day and w.end_day
      and (p_branch_id is null or inv.branch_id = p_branch_id)
    group by inv.invoice_date
  ),
  e as (
    select
      ex.expense_date as day,
      sum(coalesce(ex.total_amount, ex.amount + coalesce(ex.tax_amount,0))) as expenses_total
    from public.expenses ex
    cross join w
    where ex.org_id = p_org_id
      and ex.expense_date between w.start_day and w.end_day
      and (p_branch_id is null or ex.branch_id = p_branch_id)
    group by ex.expense_date
  ),
  l as (
    select
      le.work_date as day,
      sum(le.cost) as labor_total
    from public.labor_entries le
    cross join w
    where le.org_id = p_org_id
      and le.work_date between w.start_day and w.end_day
      and (p_branch_id is null or le.branch_id = p_branch_id)
    group by le.work_date
  )
  select
    d.day,
    coalesce(s.net_sales,0) as net_sales,
    coalesce(s.cogs_total,0) as cogs_total,
    (coalesce(s.net_sales,0) - coalesce(s.cogs_total,0)) as gross_profit,
    coalesce(e.expenses_total,0) as expenses_total,
    coalesce(l.labor_total,0) as labor_total,
    (coalesce(s.net_sales,0) - coalesce(s.cogs_total,0) - coalesce(e.expenses_total,0) - coalesce(l.labor_total,0)) as net_profit,
    coalesce(s.invoices,0) as invoices,
    case when coalesce(s.net_sales,0)=0 then null else ((coalesce(s.net_sales,0) - coalesce(s.cogs_total,0))/coalesce(s.net_sales,0)) end as gross_margin
  from days d
  left join s on s.day = d.day
  left join e on e.day = d.day
  left join l on l.day = d.day
  where public.is_org_member(p_org_id)
  order by d.day asc;
$$;

revoke all on function public.get_exec_daily(uuid,uuid,int) from public;
grant execute on function public.get_exec_daily(uuid,uuid,int) to authenticated;

-- =========================================================
-- C) Expense mix (category) (org + optional branch)
-- =========================================================
create or replace function public.get_expense_category_mix(
  p_org_id uuid,
  p_branch_id uuid default null,
  p_days int default 30,
  p_limit int default 10
)
returns table(
  category text,
  amount numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with lim as (
    select public.org_anchor_date(p_org_id) as a,
           greatest(7, least(p_days, 3650))::int as d,
           greatest(1, least(p_limit, 50))::int as lim
  ),
  w as (
    select (a - (d-1))::date as start_day, a::date as end_day, lim from lim
  )
  select
    ex.category,
    sum(coalesce(ex.total_amount, ex.amount + coalesce(ex.tax_amount,0))) as amount
  from public.expenses ex
  cross join w
  where ex.org_id = p_org_id
    and ex.expense_date between w.start_day and w.end_day
    and (p_branch_id is null or ex.branch_id = p_branch_id)
    and public.is_org_member(p_org_id)
  group by ex.category
  order by amount desc nulls last
  limit (select lim from w);
$$;

revoke all on function public.get_expense_category_mix(uuid,uuid,int,int) from public;
grant execute on function public.get_expense_category_mix(uuid,uuid,int,int) to authenticated;

-- =========================================================
-- D) Unit economics by SKU (branch-aware)
-- =========================================================
create or replace function public.get_unit_economics_by_sku_branch(
  p_org_id uuid,
  p_branch_id uuid default null,
  p_days int default 30
)
returns table(
  sku text,
  product_name text,
  units_sold numeric,
  net_sales numeric,
  cogs_material numeric,
  cogs_packaging numeric,
  cogs_labor numeric,
  cogs_overhead numeric,
  cogs_total numeric,
  gross_profit numeric,
  gross_margin numeric,
  cogs_per_unit numeric,
  avg_price numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select public.org_anchor_date(p_org_id) as a, greatest(1, least(p_days, 3650)) as d
  ),
  w as (
    select (a - (d-1))::date as start_day, a as end_day from params
  ),
  lines as (
    select
      si.sku,
      max(coalesce(si.product_name, p.product_name, si.sku)) as product_name,
      sum(si.quantity) as units_sold,
      sum(si.net_sales) as net_sales,
      sum(si.cogs_material) as cogs_material,
      sum(si.cogs_packaging) as cogs_packaging,
      sum(si.cogs_labor) as cogs_labor,
      sum(si.cogs_overhead) as cogs_overhead,
      sum(si.cogs_total) as cogs_total
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    left join public.products p on p.org_id = inv.org_id and p.sku = si.sku
    cross join w
    where inv.org_id = p_org_id
      and inv.invoice_date between w.start_day and w.end_day
      and (p_branch_id is null or inv.branch_id = p_branch_id)
      and si.sku is not null
      and public.is_org_member(p_org_id)
    group by si.sku
  )
  select
    sku,
    product_name,
    units_sold,
    net_sales,
    cogs_material,
    cogs_packaging,
    cogs_labor,
    cogs_overhead,
    cogs_total,
    (net_sales - cogs_total) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs_total)/net_sales) end as gross_margin,
    case when units_sold=0 then null else (cogs_total/units_sold) end as cogs_per_unit,
    case when units_sold=0 then null else (net_sales/units_sold) end as avg_price
  from lines
  order by gross_profit desc nulls last;
$$;

revoke all on function public.get_unit_economics_by_sku_branch(uuid,uuid,int) from public;
grant execute on function public.get_unit_economics_by_sku_branch(uuid,uuid,int) to authenticated;

select pg_notify('pgrst','reload schema');
commit;