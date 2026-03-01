begin;

-- SALES daily (scoped)
create or replace function public.get_sales_daily(
  p_org_id uuid,
  p_limit int default 60,
  p_branch_id uuid default null
)
returns table(day date, net_sales numeric, tax_amount numeric, total_amount numeric, invoices int)
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
    inv.invoice_date as day,
    sum(si.net_sales) as net_sales,
    sum(coalesce(si.tax_amount,0)) as tax_amount,
    sum(coalesce(si.total_amount,0)) as total_amount,
    count(distinct inv.external_invoice_number)::int as invoices
  from public.sales_items si
  join public.sales_invoices inv on inv.id = si.invoice_id
  cross join w
  where inv.org_id = p_org_id
    and inv.invoice_date between w.start_day and w.end_day
    and (p_branch_id is null or inv.branch_id = p_branch_id)
  group by inv.invoice_date
  order by inv.invoice_date desc;
$$;

revoke all on function public.get_sales_daily(uuid,int,uuid) from public;
grant execute on function public.get_sales_daily(uuid,int,uuid) to authenticated;

-- EXEC KPIs (scoped)
create or replace function public.get_exec_kpis(
  p_org_id uuid,
  p_days int default 30,
  p_cogs_mode text default 'engine',
  p_branch_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a date;
  d int := greatest(1, least(p_days, 3650));
  cur_start date;
  cur_end date;
  mode text := coalesce(nullif(p_cogs_mode,''),'engine');

  net_sales numeric := 0;
  cogs numeric := 0;
  invoices bigint := 0;
begin
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  a := public.org_anchor_date(p_org_id);
  cur_end := a;
  cur_start := a - (d - 1);

  select coalesce(sum(si.net_sales),0)
    into net_sales
  from public.sales_items si
  join public.sales_invoices inv on inv.id=si.invoice_id
  where inv.org_id=p_org_id
    and inv.invoice_date between cur_start and cur_end
    and (p_branch_id is null or inv.branch_id = p_branch_id);

  select count(distinct inv.external_invoice_number) into invoices
  from public.sales_invoices inv
  where inv.org_id=p_org_id
    and inv.invoice_date between cur_start and cur_end
    and (p_branch_id is null or inv.branch_id = p_branch_id);

  if mode='engine' then
    select coalesce(sum(si.cogs_total),0) into cogs
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    where inv.org_id=p_org_id
      and inv.invoice_date between cur_start and cur_end
      and (p_branch_id is null or inv.branch_id = p_branch_id);
  elsif mode='unit_cost' then
    select coalesce(sum(si.quantity * coalesce(p.unit_cost,0)),0) into cogs
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    left join public.products p on p.org_id=inv.org_id and p.sku=si.sku
    where inv.org_id=p_org_id
      and inv.invoice_date between cur_start and cur_end
      and (p_branch_id is null or inv.branch_id = p_branch_id);
  else
    cogs := 0;
  end if;

  return jsonb_build_object(
    'anchor_date', a,
    'days', d,
    'cogs_mode', mode,
    'branch_id', p_branch_id,
    'net_sales', net_sales,
    'cogs', cogs,
    'gross_profit', (net_sales - cogs),
    'gross_margin', case when net_sales=0 then null else ((net_sales - cogs)/net_sales) end,
    'invoices', invoices
  );
end $$;

revoke all on function public.get_exec_kpis(uuid,int,text,uuid) from public;
grant execute on function public.get_exec_kpis(uuid,int,text,uuid) to authenticated;

-- EXEC monthly (scoped)
create or replace function public.get_exec_monthly(
  p_org_id uuid,
  p_months int default 12,
  p_cogs_mode text default 'engine',
  p_branch_id uuid default null
)
returns table(month date, net_sales numeric, gross_profit numeric)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_months, 60)) as m,
      coalesce(nullif(p_cogs_mode,''),'engine') as mode
  ),
  win as (
    select
      date_trunc('month', a)::date as end_m,
      (date_trunc('month', a) - ((m-1) || ' months')::interval)::date as start_m,
      mode
    from params
  ),
  lines as (
    select
      date_trunc('month', inv.invoice_date)::date as month,
      sum(si.net_sales) as net_sales,
      sum(
        case
          when win.mode='engine' then si.cogs_total
          when win.mode='unit_cost' then (si.quantity * coalesce(p.unit_cost,0))
          else 0
        end
      ) as cogs
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    left join public.products p on p.org_id=inv.org_id and p.sku=si.sku
    cross join win
    where inv.org_id=p_org_id
      and inv.invoice_date >= win.start_m
      and inv.invoice_date <= (select a from params)
      and (p_branch_id is null or inv.branch_id = p_branch_id)
    group by 1
  )
  select
    month,
    net_sales,
    (net_sales - cogs) as gross_profit
  from lines
  order by month asc;
$$;

revoke all on function public.get_exec_monthly(uuid,int,text,uuid) from public;
grant execute on function public.get_exec_monthly(uuid,int,text,uuid) to authenticated;

-- Unit economics by SKU (scoped)
create or replace function public.get_unit_economics_by_sku(
  p_org_id uuid,
  p_days int default 30,
  p_branch_id uuid default null
)
returns table(
  sku text,
  product_name text,
  units_sold numeric,
  net_sales numeric,
  cogs_total numeric,
  gross_profit numeric,
  gross_margin numeric,
  cogs_per_unit numeric
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
  agg as (
    select
      si.sku,
      max(coalesce(si.product_name, p.product_name, si.sku)) as product_name,
      sum(si.quantity) as units_sold,
      sum(si.net_sales) as net_sales,
      sum(si.cogs_total) as cogs_total
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    left join public.products p on p.org_id = inv.org_id and p.sku = si.sku
    cross join w
    where inv.org_id = p_org_id
      and inv.invoice_date between w.start_day and w.end_day
      and (p_branch_id is null or inv.branch_id = p_branch_id)
      and si.sku is not null
    group by si.sku
  )
  select
    sku,
    product_name,
    units_sold,
    net_sales,
    cogs_total,
    (net_sales - cogs_total) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs_total)/net_sales) end as gross_margin,
    case when units_sold=0 then null else (cogs_total/units_sold) end as cogs_per_unit
  from agg
  order by gross_profit desc nulls last;
$$;

revoke all on function public.get_unit_economics_by_sku(uuid,int,uuid) from public;
grant execute on function public.get_unit_economics_by_sku(uuid,int,uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;