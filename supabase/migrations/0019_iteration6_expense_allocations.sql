begin;

create schema if not exists analytics;

-- 1) Allocation table (cost_center_code-based; deterministic, no dependency on unknown cost_centers schema)
create table if not exists public.expense_allocations (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  org_id uuid not null references public.orgs(id) on delete cascade,
  cost_center_code text not null,
  amount numeric not null check (amount >= 0),
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (expense_id, cost_center_code)
);

create index if not exists expense_allocations_org_id_idx on public.expense_allocations(org_id);
create index if not exists expense_allocations_expense_id_idx on public.expense_allocations(expense_id);

-- updated_at trigger
create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_expense_allocations_set_updated_at on public.expense_allocations;
create trigger trg_expense_allocations_set_updated_at
before update on public.expense_allocations
for each row execute function public.update_updated_at_column();

-- 2) Audit trail
create table if not exists public.expense_allocation_audit (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id) on delete cascade,
  org_id uuid not null references public.orgs(id) on delete cascade,
  changed_by uuid null,
  previous_allocations jsonb not null default '[]'::jsonb,
  new_allocations jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists expense_allocation_audit_expense_id_idx on public.expense_allocation_audit(expense_id);

-- 3) RLS
alter table public.expense_allocations enable row level security;
alter table public.expense_allocation_audit enable row level security;

drop policy if exists expense_allocations_select_member on public.expense_allocations;
create policy expense_allocations_select_member
on public.expense_allocations
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = expense_allocations.org_id and m.user_id = auth.uid()));

drop policy if exists expense_allocations_write_member on public.expense_allocations;
create policy expense_allocations_write_member
on public.expense_allocations
for all to authenticated
using (exists (select 1 from public.org_members m where m.org_id = expense_allocations.org_id and m.user_id = auth.uid()))
with check (exists (select 1 from public.org_members m where m.org_id = expense_allocations.org_id and m.user_id = auth.uid()));

drop policy if exists expense_allocation_audit_select_member on public.expense_allocation_audit;
create policy expense_allocation_audit_select_member
on public.expense_allocation_audit
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = expense_allocation_audit.org_id and m.user_id = auth.uid()));

-- 4) RPC: get allocations for one expense
create or replace function public.get_expense_allocations(p_expense_id uuid)
returns table(cost_center_code text, amount numeric)
language sql
stable
security definer
set search_path = public
as $$
  select a.cost_center_code, a.amount
  from public.expense_allocations a
  where a.expense_id = p_expense_id
  order by a.cost_center_code asc;
$$;

revoke all on function public.get_expense_allocations(uuid) from public;
grant execute on function public.get_expense_allocations(uuid) to authenticated;

-- 5) RPC: preview allocation status
create or replace function public.preview_expense_allocation(p_expense_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_exp public.expenses;
  v_alloc numeric;
begin
  select * into v_exp from public.expenses where id=p_expense_id;
  if not found then raise exception 'Expense not found'; end if;

  if not public.is_org_member(v_exp.org_id) then raise exception 'Forbidden'; end if;

  select coalesce(sum(amount),0) into v_alloc
  from public.expense_allocations
  where expense_id=p_expense_id;

  return jsonb_build_object(
    'expense_id', p_expense_id,
    'expense_amount', v_exp.amount,
    'allocated_amount', v_alloc,
    'unallocated_amount', greatest(v_exp.amount - v_alloc, 0),
    'status', case
      when v_alloc = 0 then 'unallocated'
      when abs(v_alloc - v_exp.amount) <= 0.01 then 'allocated'
      else 'partial'
    end
  );
end $$;

revoke all on function public.preview_expense_allocation(uuid) from public;
grant execute on function public.preview_expense_allocation(uuid) to authenticated;

-- 6) RPC: list cost center codes (for dropdown)
create or replace function public.list_cost_center_codes(p_org_id uuid)
returns table(cost_center_code text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct cost_center_code
  from (
    select nullif(trim(e.cost_center_code),'') as cost_center_code
    from public.expenses e
    where e.org_id = p_org_id
    union all
    select nullif(trim(a.cost_center_code),'') as cost_center_code
    from public.expense_allocations a
    where a.org_id = p_org_id
    union all
    select 'UNALLOCATED'::text
  ) x
  where cost_center_code is not null
  order by cost_center_code asc;
$$;

revoke all on function public.list_cost_center_codes(uuid) from public;
grant execute on function public.list_cost_center_codes(uuid) to authenticated;

-- 7) RPC: list expenses with allocation status for UI
create or replace function public.list_expenses_for_allocation(p_org_id uuid, p_limit int default 50)
returns table(
  id uuid,
  expense_date date,
  vendor text,
  category text,
  amount numeric,
  allocated_amount numeric,
  allocation_status text,
  reference_number text
)
language sql
stable
security definer
set search_path = public
as $$
  with alloc as (
    select expense_id, sum(amount) as allocated_amount
    from public.expense_allocations
    where org_id = p_org_id
    group by expense_id
  )
  select
    e.id,
    e.expense_date,
    e.vendor,
    e.category,
    e.amount,
    coalesce(a.allocated_amount, 0) as allocated_amount,
    case
      when coalesce(a.allocated_amount,0) = 0 then 'unallocated'
      when abs(coalesce(a.allocated_amount,0) - e.amount) <= 0.01 then 'allocated'
      else 'partial'
    end as allocation_status,
    e.reference_number
  from public.expenses e
  left join alloc a on a.expense_id = e.id
  where e.org_id = p_org_id
  order by e.expense_date desc, e.created_at desc
  limit greatest(1, least(p_limit, 500));
$$;

revoke all on function public.list_expenses_for_allocation(uuid, int) from public;
grant execute on function public.list_expenses_for_allocation(uuid, int) to authenticated;

-- 8) RPC: save allocations (sum must match expense amount)
create or replace function public.allocate_expense_to_cost_centers(p_expense_id uuid, p_allocations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exp public.expenses;
  v_sum numeric := 0;
  v_item jsonb;
  v_code text;
  v_amount numeric;
  v_prev jsonb;
begin
  select * into v_exp from public.expenses where id=p_expense_id;
  if not found then raise exception 'Expense not found'; end if;

  if not public.is_org_member(v_exp.org_id) then
    raise exception 'Forbidden';
  end if;

  if jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'allocations must be a JSON array';
  end if;

  -- validate + sum
  for v_item in select * from jsonb_array_elements(p_allocations)
  loop
    v_code := nullif(trim(v_item->>'cost_center_code'),'');
    if v_code is null then raise exception 'Missing cost_center_code'; end if;
    v_amount := (v_item->>'amount')::numeric;
    if v_amount is null then raise exception 'Invalid amount for %', v_code; end if;
    if v_amount < 0 then raise exception 'Negative amount not allowed'; end if;
    v_sum := v_sum + v_amount;
  end loop;

  if abs(v_sum - v_exp.amount) > 0.01 then
    raise exception 'Allocation sum % must equal expense amount %', v_sum, v_exp.amount;
  end if;

  -- capture previous
  select coalesce(
    jsonb_agg(jsonb_build_object('cost_center_code', cost_center_code, 'amount', amount) order by cost_center_code),
    '[]'::jsonb
  ) into v_prev
  from public.expense_allocations
  where expense_id=p_expense_id;

  -- replace allocations
  delete from public.expense_allocations where expense_id=p_expense_id;

  insert into public.expense_allocations(expense_id, org_id, cost_center_code, amount, created_by)
  select
    p_expense_id,
    v_exp.org_id,
    nullif(trim(x->>'cost_center_code'), ''),
    (x->>'amount')::numeric,
    auth.uid()
  from jsonb_array_elements(p_allocations) x;

  insert into public.expense_allocation_audit(expense_id, org_id, changed_by, previous_allocations, new_allocations)
  values(p_expense_id, v_exp.org_id, auth.uid(), v_prev, p_allocations);

  return jsonb_build_object('ok', true, 'allocated_amount', v_sum);
end $$;

revoke all on function public.allocate_expense_to_cost_centers(uuid, jsonb) from public;
grant execute on function public.allocate_expense_to_cost_centers(uuid, jsonb) to authenticated;

-- 9) Analytics: allocated expenses by cost center (view + public RPC wrapper)
create or replace view analytics.v_expenses_cost_center_daily as
select
  org_id,
  day,
  cost_center_code,
  sum(amount) as amount
from (
  -- allocated expenses: use allocation rows
  select
    e.org_id,
    e.expense_date as day,
    a.cost_center_code,
    a.amount
  from public.expenses e
  join public.expense_allocations a on a.expense_id = e.id

  union all

  -- unallocated expenses: bucket to UNALLOCATED
  select
    e.org_id,
    e.expense_date as day,
    'UNALLOCATED'::text as cost_center_code,
    e.amount
  from public.expenses e
  where not exists (select 1 from public.expense_allocations a where a.expense_id = e.id)
) x
group by org_id, day, cost_center_code;

create or replace function public.get_expenses_cost_center_daily(p_org_id uuid, p_limit int default 90)
returns table(day date, cost_center_code text, amount numeric)
language sql
stable
security definer
set search_path = public, analytics
as $$
  select day::date, cost_center_code, amount
  from analytics.v_expenses_cost_center_daily
  where org_id = p_org_id
  order by day desc, cost_center_code asc
  limit greatest(1, least(p_limit, 3650));
$$;

revoke all on function public.get_expenses_cost_center_daily(uuid, int) from public;
grant execute on function public.get_expenses_cost_center_daily(uuid, int) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
