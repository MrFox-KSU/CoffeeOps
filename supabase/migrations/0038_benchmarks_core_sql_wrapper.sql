begin;

-- 1) Core SQL function (no ambiguity possible)
create or replace function public.get_benchmark_points_core(p_org_id uuid, p_days int default 30)
returns table(
  plot_id text,
  plot_title text,
  x_label text,
  y_label text,
  series text,
  branch_id uuid,
  label text,
  x numeric,
  y numeric,
  n int
)
language sql
stable
security definer
set search_path = public
as $$
with
lim as (
  select
    greatest(7, least(p_days, 365))::int as days,
    coalesce(t.max_benchmark_plots, 4)::int as max_plots,
    (t.global_benchmark_enabled or public.is_platform_admin()) as global_enabled,
    public.org_anchor_date(p_org_id) as anchor
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
),
w as (
  select
    (anchor - (days - 1))::date as start_day,
    anchor::date as end_day,
    max_plots,
    global_enabled
  from lim
),
m as (
  select
    inv.org_id,
    inv.branch_id,
    coalesce(b.name, b.code, 'Unknown') as branch_name,
    sum(si.net_sales) as net_sales,
    count(distinct inv.external_invoice_number) as invoices,
    sum(si.quantity) as units_sold,
    sum(si.cogs_total) as cogs_total,
    sum(si.cogs_labor) as cogs_labor,
    sum(si.cogs_overhead) as cogs_overhead
  from public.sales_items si
  join public.sales_invoices inv on inv.id = si.invoice_id
  left join public.branches b on b.id = inv.branch_id
  cross join w
  where inv.invoice_date between w.start_day and w.end_day
    and inv.branch_id is not null
  group by inv.org_id, inv.branch_id, branch_name
),
mx as (
  select
    m.*,
    (m.net_sales - m.cogs_total) as gross_profit,
    case when m.net_sales=0 then null else ((m.net_sales - m.cogs_total)/m.net_sales) end as gross_margin,
    case when m.invoices=0 then null else (m.net_sales/m.invoices) end as avg_ticket,
    case when m.net_sales=0 then null else (m.cogs_labor/m.net_sales) end as labor_pct,
    case when m.net_sales=0 then null else (m.cogs_overhead/m.net_sales) end as overhead_pct,
    case when m.units_sold=0 then null else (m.cogs_total/m.units_sold) end as cogs_per_unit
  from m
),
oc as (select count(*)::int as other_cnt from mx where mx.org_id <> p_org_id),
privacy as (select (other_cnt >= 10) as allow_others from oc),
bcnt as (select greatest(1, least(20, floor((select other_cnt from oc)/5.0)::int)) as b),

-- Plot 1: Net Sales vs Gross Margin
p1_self as (
  select
    'sales_vs_margin'::text as plot_id,
    'Net Sales vs Gross Margin'::text as plot_title,
    'Net Sales'::text as x_label,
    'Gross Margin %'::text as y_label,
    'self'::text as series,
    mx.branch_id as branch_id,
    mx.branch_name::text as label,
    mx.net_sales::numeric as x,
    mx.gross_margin::numeric as y,
    null::int as n,
    1 as plot_order
  from mx where mx.org_id = p_org_id
),
p1_oth as (
  select
    'sales_vs_margin'::text as plot_id,
    'Net Sales vs Gross Margin'::text as plot_title,
    'Net Sales'::text as x_label,
    'Gross Margin %'::text as y_label,
    'others'::text as series,
    null::uuid as branch_id,
    'Others'::text as label,
    avg(s.xv)::numeric as x,
    avg(s.yv)::numeric as y,
    count(*)::int as n,
    1 as plot_order
  from (
    select
      ntile((select b from bcnt)) over(order by mx.net_sales) as bucket,
      mx.net_sales::numeric as xv,
      mx.gross_margin::numeric as yv
    from mx
    where mx.org_id <> p_org_id and mx.net_sales is not null and mx.gross_margin is not null
  ) s
  group by s.bucket
),

-- Plot 2: Invoices vs Avg Ticket
p2_self as (
  select
    'invoices_vs_ticket'::text as plot_id,
    'Invoices vs Avg Ticket'::text as plot_title,
    'Invoices'::text as x_label,
    'Avg Ticket'::text as y_label,
    'self'::text as series,
    mx.branch_id as branch_id,
    mx.branch_name::text as label,
    mx.invoices::numeric as x,
    mx.avg_ticket::numeric as y,
    null::int as n,
    2 as plot_order
  from mx where mx.org_id = p_org_id
),
p2_oth as (
  select
    'invoices_vs_ticket'::text as plot_id,
    'Invoices vs Avg Ticket'::text as plot_title,
    'Invoices'::text as x_label,
    'Avg Ticket'::text as y_label,
    'others'::text as series,
    null::uuid as branch_id,
    'Others'::text as label,
    avg(s.xv)::numeric as x,
    avg(s.yv)::numeric as y,
    count(*)::int as n,
    2 as plot_order
  from (
    select
      ntile((select b from bcnt)) over(order by mx.invoices) as bucket,
      mx.invoices::numeric as xv,
      mx.avg_ticket::numeric as yv
    from mx
    where mx.org_id <> p_org_id and mx.invoices is not null and mx.avg_ticket is not null
  ) s
  group by s.bucket
),

points as (
  select * from p1_self
  union all select * from p1_oth
  union all select * from p2_self
  union all select * from p2_oth
),
filtered as (
  select
    points.plot_id, points.plot_title, points.x_label, points.y_label,
    points.series, points.branch_id, points.label, points.x, points.y, points.n,
    points.plot_order,
    w.max_plots,
    w.global_enabled,
    (select allow_others from privacy) as allow_others
  from points
  cross join w
)
select
  f.plot_id, f.plot_title, f.x_label, f.y_label,
  f.series, f.branch_id, f.label, f.x, f.y, f.n
from filtered f
where f.plot_order <= f.max_plots
  and (f.series='self' or (f.global_enabled and f.allow_others))
order by f.plot_order asc, f.series asc, f.label asc;
$$;

revoke all on function public.get_benchmark_points_core(uuid,int) from public;
grant execute on function public.get_benchmark_points_core(uuid,int) to authenticated;

-- 2) Wrapper (keeps "Forbidden" behavior)
create or replace function public.get_benchmark_points(p_org_id uuid, p_days int default 30)
returns table(
  plot_id text,
  plot_title text,
  x_label text,
  y_label text,
  series text,
  branch_id uuid,
  label text,
  x numeric,
  y numeric,
  n int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'Forbidden';
  end if;

  return query
  select *
  from public.get_benchmark_points_core(p_org_id, p_days);
end $$;

revoke all on function public.get_benchmark_points(uuid,int) from public;
grant execute on function public.get_benchmark_points(uuid,int) to authenticated;

select pg_notify('pgrst','reload schema');
commit;