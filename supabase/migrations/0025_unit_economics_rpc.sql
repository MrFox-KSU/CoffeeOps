begin;

create or replace function public.get_unit_economics_by_sku(
  p_org_id uuid,
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
  cogs_per_unit numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_days, 3650)) as d
  ),
  w as (
    select (a - (d-1))::date as start_day, a as end_day
    from params
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
      and si.sku is not null
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
    case when units_sold=0 then null else (cogs_total/units_sold) end as cogs_per_unit
  from lines
  order by gross_profit desc nulls last;
$$;

revoke all on function public.get_unit_economics_by_sku(uuid,int) from public;
grant execute on function public.get_unit_economics_by_sku(uuid,int) to authenticated;

select pg_notify('pgrst','reload schema');
commit;
