begin;

-- Sales daily (public wrapper)
create or replace function public.get_sales_daily(p_org_id uuid, p_limit int default 60)
returns table(
  day date,
  net_sales numeric,
  tax_amount numeric,
  total_amount numeric,
  invoices bigint
)
language sql
stable
security definer
set search_path = public, analytics
as $$
  select
    day::date,
    net_sales,
    tax_amount,
    total_amount,
    invoices
  from analytics.v_sales_daily
  where org_id = p_org_id
  order by day desc
  limit greatest(1, least(p_limit, 3650));
$$;

revoke all on function public.get_sales_daily(uuid, int) from public;
grant execute on function public.get_sales_daily(uuid, int) to authenticated;

-- Expenses daily (public wrapper)
create or replace function public.get_expenses_daily(p_org_id uuid, p_limit int default 60)
returns table(
  day date,
  amount numeric,
  tax_amount numeric,
  total_amount numeric,
  expense_rows bigint
)
language sql
stable
security definer
set search_path = public, analytics
as $$
  select
    day::date,
    amount,
    tax_amount,
    total_amount,
    expense_rows
  from analytics.v_expenses_daily
  where org_id = p_org_id
  order by day desc
  limit greatest(1, least(p_limit, 3650));
$$;

revoke all on function public.get_expenses_daily(uuid, int) from public;
grant execute on function public.get_expenses_daily(uuid, int) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
