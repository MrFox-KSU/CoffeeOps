begin;

-- ---------------------------------------------------------
-- 1) Fix is_platform_admin (SECURITY DEFINER) + avoid RLS recursion
-- ---------------------------------------------------------
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid());
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;

-- Replace platform_admins policies to use the function (no self-subquery recursion)
alter table public.platform_admins enable row level security;

drop policy if exists platform_admins_select_admin on public.platform_admins;
create policy platform_admins_select_admin
on public.platform_admins
for select to authenticated
using (public.is_platform_admin());

drop policy if exists platform_admins_write_admin on public.platform_admins;
create policy platform_admins_write_admin
on public.platform_admins
for all to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin());

-- platform_settings update policy should also use function
drop policy if exists platform_settings_update_admin on public.platform_settings;
create policy platform_settings_update_admin
on public.platform_settings
for update to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin());

-- ---------------------------------------------------------
-- 2) Rewrite get_benchmark_points WITHOUT temp tables / CTAS
--    (CTE-only; privacy: hide others unless >= 10 points)
-- ---------------------------------------------------------
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
      *,
      (net_sales - cogs_total) as gross_profit,
      case when net_sales=0 then null else ((net_sales - cogs_total)/net_sales) end as gross_margin,
      case when invoices=0 then null else (net_sales/invoices) end as avg_ticket
    from m
  ),
  oc as (select count(*)::int as other_cnt from mx where org_id <> p_org_id),
  privacy as (select (other_cnt >= 10) as allow_others from oc),
  bcnt as (select greatest(1, least(20, floor((select other_cnt from oc)/5.0)::int)) as b),

  p1_self as (
    select
      'sales_vs_margin'::text as plot_id,
      'Net Sales vs Gross Margin'::text as plot_title,
      'Net Sales'::text as x_label,
      'Gross Margin %'::text as y_label,
      'self'::text as series,
      branch_id,
      branch_name::text as label,
      net_sales::numeric as x,
      gross_margin::numeric as y,
      null::int as n,
      1 as plot_order
    from mx where org_id = p_org_id
  ),
  p1_oth as (
    select
      'sales_vs_margin','Net Sales vs Gross Margin','Net Sales','Gross Margin %',
      'others', null::uuid, 'Others',
      avg(x)::numeric, avg(y)::numeric, count(*)::int, 1
    from (
      select ntile((select b from bcnt)) over(order by net_sales) as bucket,
             net_sales::numeric as x,
             gross_margin::numeric as y
      from mx
      where org_id <> p_org_id and net_sales is not null and gross_margin is not null
    ) s
    group by bucket
  ),

  p2_self as (
    select
      'invoices_vs_ticket','Invoices vs Avg Ticket','Invoices','Avg Ticket',
      'self', branch_id, branch_name,
      invoices::numeric, avg_ticket::numeric, null::int, 2
    from mx where org_id = p_org_id
  ),
  p2_oth as (
    select
      'invoices_vs_ticket','Invoices vs Avg Ticket','Invoices','Avg Ticket',
      'others', null::uuid, 'Others',
      avg(x)::numeric, avg(y)::numeric, count(*)::int, 2
    from (
      select ntile((select b from bcnt)) over(order by invoices) as bucket,
             invoices::numeric as x,
             avg_ticket::numeric as y
      from mx
      where org_id <> p_org_id and invoices is not null and avg_ticket is not null
    ) s
    group by bucket
  ),

  points as (
    select * from p1_self
    union all select * from p1_oth
    union all select * from p2_self
    union all select * from p2_oth
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