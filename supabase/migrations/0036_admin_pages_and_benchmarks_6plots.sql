begin;

-- ---------------------------------------------
-- Platform admin: list orgs + set org tier
-- ---------------------------------------------
create or replace function public.platform_list_orgs(p_limit int default 200)
returns table(
  org_id uuid,
  name text,
  subscription_tier_code text,
  branch_count int,
  support_email text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.id,
    o.name,
    o.subscription_tier_code,
    (select count(*) from public.branches b where b.org_id = o.id)::int as branch_count,
    coalesce(o.support_email, (select support_email from public.platform_settings where id=1)) as support_email,
    o.created_at
  from public.orgs o
  where public.is_platform_admin()
  order by o.created_at desc
  limit greatest(1, least(p_limit, 2000));
$$;

revoke all on function public.platform_list_orgs(int) from public;
grant execute on function public.platform_list_orgs(int) to authenticated;

create or replace function public.platform_set_org_tier(p_org_id uuid, p_tier_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  update public.orgs
  set subscription_tier_code = p_tier_code
  where id = p_org_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_set_org_tier(uuid,text) from public;
grant execute on function public.platform_set_org_tier(uuid,text) to authenticated;

-- ---------------------------------------------
-- Benchmarks: extend to 6 plots (no temp tables)
-- Fixes ambiguity by using s.xv/s.yv aliases
-- ---------------------------------------------
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
    select 'sales_vs_margin','Net Sales vs Gross Margin','Net Sales','Gross Margin %',
      'self', mx.branch_id, mx.branch_name, mx.net_sales::numeric, mx.gross_margin::numeric, null::int, 1
    from mx where mx.org_id = p_org_id
  ),
  p1_oth as (
    select 'sales_vs_margin','Net Sales vs Gross Margin','Net Sales','Gross Margin %',
      'others', null::uuid, 'Others', avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 1
    from (
      select ntile((select b from bcnt)) over(order by mx.net_sales) as bucket,
             mx.net_sales::numeric as xv,
             mx.gross_margin::numeric as yv
      from mx where mx.org_id <> p_org_id and mx.net_sales is not null and mx.gross_margin is not null
    ) s
    group by s.bucket
  ),

  -- Plot 2: Invoices vs Avg Ticket
  p2_self as (
    select 'invoices_vs_ticket','Invoices vs Avg Ticket','Invoices','Avg Ticket',
      'self', mx.branch_id, mx.branch_name, mx.invoices::numeric, mx.avg_ticket::numeric, null::int, 2
    from mx where mx.org_id = p_org_id
  ),
  p2_oth as (
    select 'invoices_vs_ticket','Invoices vs Avg Ticket','Invoices','Avg Ticket',
      'others', null::uuid, 'Others', avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 2
    from (
      select ntile((select b from bcnt)) over(order by mx.invoices) as bucket,
             mx.invoices::numeric as xv,
             mx.avg_ticket::numeric as yv
      from mx where mx.org_id <> p_org_id and mx.invoices is not null and mx.avg_ticket is not null
    ) s
    group by s.bucket
  ),

  -- Plot 3: Labor % vs Gross Margin
  p3_self as (
    select 'labor_pct_vs_margin','Labor % vs Gross Margin','Labor %','Gross Margin %',
      'self', mx.branch_id, mx.branch_name, mx.labor_pct::numeric, mx.gross_margin::numeric, null::int, 3
    from mx where mx.org_id = p_org_id
  ),
  p3_oth as (
    select 'labor_pct_vs_margin','Labor % vs Gross Margin','Labor %','Gross Margin %',
      'others', null::uuid, 'Others', avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 3
    from (
      select ntile((select b from bcnt)) over(order by mx.labor_pct) as bucket,
             mx.labor_pct::numeric as xv,
             mx.gross_margin::numeric as yv
      from mx where mx.org_id <> p_org_id and mx.labor_pct is not null and mx.gross_margin is not null
    ) s
    group by s.bucket
  ),

  -- Plot 4: Overhead % vs Gross Margin
  p4_self as (
    select 'overhead_pct_vs_margin','Overhead % vs Gross Margin','Overhead %','Gross Margin %',
      'self', mx.branch_id, mx.branch_name, mx.overhead_pct::numeric, mx.gross_margin::numeric, null::int, 4
    from mx where mx.org_id = p_org_id
  ),
  p4_oth as (
    select 'overhead_pct_vs_margin','Overhead % vs Gross Margin','Overhead %','Gross Margin %',
      'others', null::uuid, 'Others', avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 4
    from (
      select ntile((select b from bcnt)) over(order by mx.overhead_pct) as bucket,
             mx.overhead_pct::numeric as xv,
             mx.gross_margin::numeric as yv
      from mx where mx.org_id <> p_org_id and mx.overhead_pct is not null and mx.gross_margin is not null
    ) s
    group by s.bucket
  ),

  -- Plot 5: Net Sales vs Gross Profit
  p5_self as (
    select 'sales_vs_gross_profit','Net Sales vs Gross Profit','Net Sales','Gross Profit',
      'self', mx.branch_id, mx.branch_name, mx.net_sales::numeric, mx.gross_profit::numeric, null::int, 5
    from mx where mx.org_id = p_org_id
  ),
  p5_oth as (
    select 'sales_vs_gross_profit','Net Sales vs Gross Profit','Net Sales','Gross Profit',
      'others', null::uuid, 'Others', avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 5
    from (
      select ntile((select b from bcnt)) over(order by mx.net_sales) as bucket,
             mx.net_sales::numeric as xv,
             mx.gross_profit::numeric as yv
      from mx where mx.org_id <> p_org_id and mx.net_sales is not null and mx.gross_profit is not null
    ) s
    group by s.bucket
  ),

  -- Plot 6: Avg Ticket vs COGS/Unit
  p6_self as (
    select 'ticket_vs_cogs_unit','Avg Ticket vs COGS/Unit','Avg Ticket','COGS/Unit',
      'self', mx.branch_id, mx.branch_name, mx.avg_ticket::numeric, mx.cogs_per_unit::numeric, null::int, 6
    from mx where mx.org_id = p_org_id
  ),
  p6_oth as (
    select 'ticket_vs_cogs_unit','Avg Ticket vs COGS/Unit','Avg Ticket','COGS/Unit',
      'others', null::uuid, 'Others', avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 6
    from (
      select ntile((select b from bcnt)) over(order by mx.avg_ticket) as bucket,
             mx.avg_ticket::numeric as xv,
             mx.cogs_per_unit::numeric as yv
      from mx where mx.org_id <> p_org_id and mx.avg_ticket is not null and mx.cogs_per_unit is not null
    ) s
    group by s.bucket
  ),

  points as (
    select * from p1_self union all select * from p1_oth
    union all select * from p2_self union all select * from p2_oth
    union all select * from p3_self union all select * from p3_oth
    union all select * from p4_self union all select * from p4_oth
    union all select * from p5_self union all select * from p5_oth
    union all select * from p6_self union all select * from p6_oth
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