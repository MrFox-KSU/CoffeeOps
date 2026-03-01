begin;

create or replace function public.get_benchmark_points(p_org_id uuid, p_days int default 30)
returns table(
  plot_id text,
  plot_title text,
  x_label text,
  y_label text,
  series text,          -- 'self' | 'others'
  branch_id uuid,       -- null for others
  label text,           -- branch name for self, 'Others' for others
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
  privacy as (select other_cnt, (other_cnt >= 10) as allow_others from oc),
  bcnt as (select greatest(1, least(20, floor(other_cnt/5.0)::int)) as b from oc),

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
    select plot_id, plot_title, x_label, y_label, series, branch_id, label, x, y, n, plot_order from p1_self
    union all
    select plot_id, plot_title, x_label, y_label, series, branch_id, label, x, y, n, plot_order from p1_oth
    union all
    select plot_id, plot_title, x_label, y_label, series, branch_id, label, x, y, n, plot_order from p2_self
    union all
    select plot_id, plot_title, x_label, y_label, series, branch_id, label, x, y, n, plot_order from p2_oth
  )
  select
    p.plot_id, p.plot_title, p.x_label, p.y_label, p.series, p.branch_id, p.label, p.x, p.y, p.n
  from points p
  cross join w
  cross join privacy pr
  where p.plot_order <= w.max_plots
    and (p.series='self' or (w.global_enabled and pr.allow_others))
  order by p.plot_order asc, p.series asc, p.label asc;

end $$;

revoke all on function public.get_benchmark_points(uuid,int) from public;
grant execute on function public.get_benchmark_points(uuid,int) to authenticated;

select pg_notify('pgrst','reload schema');
commit;