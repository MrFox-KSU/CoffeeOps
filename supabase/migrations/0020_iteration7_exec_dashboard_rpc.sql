begin;

create schema if not exists analytics;

-- Helper: org access check (function already exists in your DB; keep deterministic guard)
-- We will call public.is_org_member(p_org_id) inside RPCs.

-- Helper: pick an anchor date so dashboards show data even if dataset is historic
create or replace function public.org_anchor_date(p_org_id uuid)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select greatest(
      coalesce((select max(invoice_date) from public.sales_invoices where org_id=p_org_id), '1900-01-01'::date),
      coalesce((select max(expense_date) from public.expenses where org_id=p_org_id), '1900-01-01'::date)
    )),
    current_date
  );
$$;

revoke all on function public.org_anchor_date(uuid) from public;
grant execute on function public.org_anchor_date(uuid) to authenticated;

-- EXEC KPIs (RPC): returns JSON for KPI cards + deltas
create or replace function public.get_exec_kpis(
  p_org_id uuid,
  p_days int default 30,
  p_cogs_mode text default 'unit_cost'  -- 'unit_cost' | 'none'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  a date;
  d int := greatest(1, least(p_days, 3650));
  cur_start date;
  cur_end date;
  prev_start date;
  prev_end date;

  cur_net numeric := 0;
  cur_cogs numeric := 0;
  cur_gp numeric := 0;
  cur_exp numeric := 0;
  cur_inv bigint := 0;

  prev_net numeric := 0;
  prev_cogs numeric := 0;
  prev_gp numeric := 0;
  prev_exp numeric := 0;
  prev_inv bigint := 0;

  mode text := coalesce(nullif(p_cogs_mode,''),'unit_cost');
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'Forbidden';
  end if;

  a := public.org_anchor_date(p_org_id);
  cur_end := a;
  cur_start := a - (d - 1);

  prev_end := cur_start - 1;
  prev_start := prev_end - (d - 1);

  -- current period sales
  with lines as (
    select
      si.org_id,
      inv.invoice_date,
      si.net_sales,
      si.quantity,
      si.sku
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = p_org_id
      and inv.invoice_date between cur_start and cur_end
  ),
  c as (
    select
      sum(net_sales) as net_sales,
      sum(
        case when mode='unit_cost'
          then (quantity * coalesce(p.unit_cost,0))
          else 0
        end
      ) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
  )
  select coalesce(net_sales,0), coalesce(cogs,0) into cur_net, cur_cogs
  from c;

  select count(distinct inv.external_invoice_number) into cur_inv
  from public.sales_invoices inv
  where inv.org_id=p_org_id and inv.invoice_date between cur_start and cur_end;

  cur_gp := cur_net - cur_cogs;

  -- current expenses (pre-tax amount)
  select coalesce(sum(amount),0) into cur_exp
  from public.expenses
  where org_id=p_org_id and expense_date between cur_start and cur_end;

  -- previous period sales
  with lines as (
    select
      si.org_id,
      inv.invoice_date,
      si.net_sales,
      si.quantity,
      si.sku
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = p_org_id
      and inv.invoice_date between prev_start and prev_end
  ),
  c as (
    select
      sum(net_sales) as net_sales,
      sum(
        case when mode='unit_cost'
          then (quantity * coalesce(p.unit_cost,0))
          else 0
        end
      ) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
  )
  select coalesce(net_sales,0), coalesce(cogs,0) into prev_net, prev_cogs
  from c;

  select count(distinct inv.external_invoice_number) into prev_inv
  from public.sales_invoices inv
  where inv.org_id=p_org_id and inv.invoice_date between prev_start and prev_end;

  prev_gp := prev_net - prev_cogs;

  select coalesce(sum(amount),0) into prev_exp
  from public.expenses
  where org_id=p_org_id and expense_date between prev_start and prev_end;

  return jsonb_build_object(
    'anchor_date', a,
    'days', d,
    'cogs_mode', mode,

    'net_sales', cur_net,
    'cogs', cur_cogs,
    'gross_profit', cur_gp,
    'gross_margin', case when cur_net=0 then null else (cur_gp/cur_net) end,
    'expenses', cur_exp,
    'net_profit', cur_gp - cur_exp,
    'invoices', cur_inv,

    'prev_net_sales', prev_net,
    'prev_cogs', prev_cogs,
    'prev_gross_profit', prev_gp,
    'prev_expenses', prev_exp,
    'prev_net_profit', prev_gp - prev_exp,
    'prev_invoices', prev_inv
  );
end $$;

revoke all on function public.get_exec_kpis(uuid,int,text) from public;
grant execute on function public.get_exec_kpis(uuid,int,text) to authenticated;

-- Monthly series (RPC) for hero chart
create or replace function public.get_exec_monthly(
  p_org_id uuid,
  p_months int default 12,
  p_cogs_mode text default 'unit_cost'
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
      coalesce(nullif(p_cogs_mode,''),'unit_cost') as mode
  ),
  w as (
    select
      date_trunc('month', a)::date as end_month,
      (date_trunc('month', a)::date - ((m-1) * interval '1 month'))::date as start_month,
      mode
    from params
  ),
  lines as (
    select
      si.org_id,
      date_trunc('month', inv.invoice_date)::date as month,
      si.net_sales,
      si.quantity,
      si.sku,
      w.mode
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    cross join w w
    where si.org_id=p_org_id
      and inv.invoice_date >= w.start_month
      and inv.invoice_date < (w.end_month + interval '1 month')
  ),
  agg as (
    select
      l.month,
      sum(l.net_sales) as net_sales,
      sum(case when l.mode='unit_cost' then (l.quantity * coalesce(p.unit_cost,0)) else 0 end) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
    group by l.month
  )
  select month, net_sales, (net_sales - cogs) as gross_profit
  from agg
  order by month asc;
$$;

revoke all on function public.get_exec_monthly(uuid,int,text) from public;
grant execute on function public.get_exec_monthly(uuid,int,text) to authenticated;

-- Top products (30d anchored)
create or replace function public.get_top_products_30d(
  p_org_id uuid,
  p_limit int default 10,
  p_cogs_mode text default 'unit_cost'
)
returns table(
  sku text,
  product_name text,
  category text,
  net_sales numeric,
  cogs numeric,
  gross_profit numeric,
  gross_margin numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_limit, 50)) as lim,
      coalesce(nullif(p_cogs_mode,''),'unit_cost') as mode
  ),
  w as (
    select (a - interval '29 days')::date as start_day, a as end_day, lim, mode
    from params
  ),
  lines as (
    select
      si.org_id,
      inv.invoice_date,
      si.sku,
      si.product_name,
      si.category,
      si.net_sales,
      si.quantity,
      w.mode
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    cross join w
    where si.org_id=p_org_id and inv.invoice_date between w.start_day and w.end_day
  ),
  agg as (
    select
      l.sku,
      max(l.product_name) as product_name,
      max(l.category) as category,
      sum(l.net_sales) as net_sales,
      sum(case when l.mode='unit_cost' then (l.quantity * coalesce(p.unit_cost,0)) else 0 end) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
    group by l.sku
  )
  select
    sku,
    product_name,
    category,
    net_sales,
    cogs,
    (net_sales - cogs) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs)/net_sales) end as gross_margin
  from agg
  order by gross_profit desc nulls last
  limit (select lim from w);
$$;

revoke all on function public.get_top_products_30d(uuid,int,text) from public;
grant execute on function public.get_top_products_30d(uuid,int,text) to authenticated;

-- Top categories (30d anchored)
create or replace function public.get_top_categories_30d(
  p_org_id uuid,
  p_limit int default 10,
  p_cogs_mode text default 'unit_cost'
)
returns table(
  category text,
  net_sales numeric,
  cogs numeric,
  gross_profit numeric,
  gross_margin numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_limit, 50)) as lim,
      coalesce(nullif(p_cogs_mode,''),'unit_cost') as mode
  ),
  w as (
    select (a - interval '29 days')::date as start_day, a as end_day, lim, mode
    from params
  ),
  lines as (
    select
      si.org_id,
      inv.invoice_date,
      coalesce(nullif(si.category,''),'Uncategorized') as category,
      si.net_sales,
      si.quantity,
      si.sku,
      w.mode
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    cross join w
    where si.org_id=p_org_id and inv.invoice_date between w.start_day and w.end_day
  ),
  agg as (
    select
      l.category,
      sum(l.net_sales) as net_sales,
      sum(case when l.mode='unit_cost' then (l.quantity * coalesce(p.unit_cost,0)) else 0 end) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
    group by l.category
  )
  select
    category,
    net_sales,
    cogs,
    (net_sales - cogs) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs)/net_sales) end as gross_margin
  from agg
  order by gross_profit desc nulls last
  limit (select lim from w);
$$;

revoke all on function public.get_top_categories_30d(uuid,int,text) from public;
grant execute on function public.get_top_categories_30d(uuid,int,text) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
