begin;

-- Ensure expenses has branch_id (safe/idempotent)
alter table public.expenses
  add column if not exists branch_id uuid;

do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public'
      and table_name='expenses'
      and constraint_name='expenses_branch_id_fkey'
  ) then
    alter table public.expenses
      add constraint expenses_branch_id_fkey
      foreign key (branch_id) references public.branches(id);
  end if;
end $$;

create index if not exists expenses_org_branch_date_idx on public.expenses(org_id, branch_id, expense_date);

-- EXPENSES DAILY (scoped)
create or replace function public.get_expenses_daily(
  p_org_id uuid,
  p_limit int default 60,
  p_branch_id uuid default null
)
returns table(day date, amount numeric, tax_amount numeric, total_amount numeric, expense_rows int)
language sql
stable
security definer
set search_path = public
as $$
  with a as (select public.org_anchor_date(p_org_id) as anchor),
  w as (
    select (anchor - (greatest(1, least(p_limit, 3650)) - 1))::date as start_day, anchor as end_day
    from a
  )
  select
    e.expense_date as day,
    sum(e.amount) as amount,
    sum(coalesce(e.tax_amount,0)) as tax_amount,
    sum(coalesce(e.total_amount, (e.amount + coalesce(e.tax_amount,0)))) as total_amount,
    count(*)::int as expense_rows
  from public.expenses e
  cross join w
  where e.org_id = p_org_id
    and e.expense_date between w.start_day and w.end_day
    and (p_branch_id is null or e.branch_id = p_branch_id)
  group by e.expense_date
  order by e.expense_date desc;
$$;

revoke all on function public.get_expenses_daily(uuid,int,uuid) from public;
grant execute on function public.get_expenses_daily(uuid,int,uuid) to authenticated;

-- EXPENSES LIST FOR ALLOCATION (scoped)
create or replace function public.list_expenses_for_allocation(
  p_org_id uuid,
  p_limit int default 200,
  p_branch_id uuid default null
)
returns table(
  expense_id uuid,
  expense_date date,
  vendor text,
  category text,
  amount numeric,
  allocated_amount numeric,
  unallocated_amount numeric,
  allocation_status text
)
language sql
stable
security definer
set search_path = public
as $$
  with base as (
    select
      e.id as expense_id,
      e.expense_date,
      e.vendor,
      e.category,
      e.amount
    from public.expenses e
    where e.org_id = p_org_id
      and (p_branch_id is null or e.branch_id = p_branch_id)
    order by e.expense_date desc, e.created_at desc
    limit greatest(1, least(p_limit, 2000))
  ),
  alloc as (
    select a.expense_id, coalesce(sum(a.amount),0) as allocated_amount
    from public.expense_allocations a
    join base b on b.expense_id = a.expense_id
    group by a.expense_id
  )
  select
    b.expense_id,
    b.expense_date,
    b.vendor,
    b.category,
    b.amount,
    coalesce(al.allocated_amount,0) as allocated_amount,
    (b.amount - coalesce(al.allocated_amount,0)) as unallocated_amount,
    case
      when coalesce(al.allocated_amount,0) = 0 then 'unallocated'
      when (b.amount - coalesce(al.allocated_amount,0)) = 0 then 'allocated'
      else 'partial'
    end as allocation_status
  from base b
  left join alloc al on al.expense_id = b.expense_id;
$$;

revoke all on function public.list_expenses_for_allocation(uuid,int,uuid) from public;
grant execute on function public.list_expenses_for_allocation(uuid,int,uuid) to authenticated;

-- FORECAST: add branch_id to forecast_runs (if table exists)
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='forecast_runs'
  ) then
    execute 'alter table public.forecast_runs add column if not exists branch_id uuid';
    execute 'create index if not exists forecast_runs_org_branch_created_idx on public.forecast_runs(org_id, branch_id, created_at desc)';
  end if;
end $$;

-- FORECAST runs list (scoped)
create or replace function public.list_forecast_runs(
  p_org_id uuid,
  p_limit int default 20,
  p_branch_id uuid default null
)
returns table(
  id uuid,
  created_at timestamptz,
  status text,
  horizon_days int,
  history_days int,
  anchor_date date,
  model text,
  message text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    fr.id,
    fr.created_at,
    fr.status,
    fr.horizon_days,
    fr.history_days,
    fr.anchor_date,
    fr.model,
    fr.message
  from public.forecast_runs fr
  where fr.org_id = p_org_id
    and (
      (p_branch_id is null and fr.branch_id is null)
      or (p_branch_id is not null and fr.branch_id = p_branch_id)
    )
  order by fr.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

revoke all on function public.list_forecast_runs(uuid,int,uuid) from public;
grant execute on function public.list_forecast_runs(uuid,int,uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;