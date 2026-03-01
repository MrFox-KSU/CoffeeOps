begin;

-- =========================================
-- PLATFORM: super admin + settings
-- =========================================
create table if not exists public.platform_admins (
  user_id uuid primary key,
  email text not null,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;
drop policy if exists platform_admins_select_admin on public.platform_admins;
create policy platform_admins_select_admin
on public.platform_admins
for select to authenticated
using (exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()));

drop policy if exists platform_admins_write_admin on public.platform_admins;
create policy platform_admins_write_admin
on public.platform_admins
for all to authenticated
using (exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()))
with check (exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()));

create table if not exists public.platform_settings (
  id int primary key default 1,
  support_email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.platform_settings enable row level security;

-- Everyone authenticated can read support_email (needed for pending page)
drop policy if exists platform_settings_select_auth on public.platform_settings;
create policy platform_settings_select_auth
on public.platform_settings
for select to authenticated
using (true);

-- Only platform admins can update
drop policy if exists platform_settings_update_admin on public.platform_settings;
create policy platform_settings_update_admin
on public.platform_settings
for update to authenticated
using (exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()))
with check (exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()));

drop trigger if exists trg_platform_settings_set_updated_at on public.platform_settings;
create trigger trg_platform_settings_set_updated_at
before update on public.platform_settings
for each row execute function public.update_updated_at_column();

-- Bootstrap: if platform_admins empty, pick earliest profile as platform admin (deterministic)
insert into public.platform_admins(user_id, email)
select u.id, u.email
from auth.users u
where u.email is not null
order by u.created_at asc
limit 1
on conflict (user_id) do nothing;

-- Bootstrap support email from first platform admin if settings row missing
insert into public.platform_settings(id, support_email)
select 1,
  coalesce(
    (select pa.email from public.platform_admins pa order by pa.created_at asc limit 1),
    (select u.email from auth.users u where u.email is not null order by u.created_at asc limit 1)
  )
where not exists (select 1 from public.platform_settings where id=1);

-- Helper: platform admin boolean
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
as $$
  select exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid());
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;

-- RPC: support email for pending page
create or replace function public.get_platform_support_email()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select support_email
  from public.platform_settings
  where id=1;
$$;

revoke all on function public.get_platform_support_email() from public;
grant execute on function public.get_platform_support_email() to authenticated;

-- RPC: add another platform admin (platform-admin only)
create or replace function public.platform_add_admin(p_user_id uuid, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  insert into public.platform_admins(user_id, email)
  values (p_user_id, p_email)
  on conflict (user_id) do update set email = excluded.email;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_add_admin(uuid,text) from public;
grant execute on function public.platform_add_admin(uuid,text) to authenticated;

-- =========================================
-- SUBSCRIPTIONS: tiers + org assignment
-- =========================================
create table if not exists public.subscription_tiers (
  tier_code text primary key,
  name text not null,
  max_branches int not null check (max_branches >= 1),
  max_benchmark_plots int not null check (max_benchmark_plots between 1 and 6),
  global_benchmark_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.subscription_tiers enable row level security;

-- Everyone authenticated can read tiers (not sensitive)
drop policy if exists subscription_tiers_select_auth on public.subscription_tiers;
create policy subscription_tiers_select_auth
on public.subscription_tiers
for select to authenticated
using (true);

-- Only platform admins can write
drop policy if exists subscription_tiers_write_admin on public.subscription_tiers;
create policy subscription_tiers_write_admin
on public.subscription_tiers
for all to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin());

drop trigger if exists trg_subscription_tiers_set_updated_at on public.subscription_tiers;
create trigger trg_subscription_tiers_set_updated_at
before update on public.subscription_tiers
for each row execute function public.update_updated_at_column();

-- Default tiers (platform admin can edit later)
insert into public.subscription_tiers(tier_code, name, max_branches, max_benchmark_plots, global_benchmark_enabled)
values
  ('free','Free',3,4,false),
  ('pro','Pro',20,6,true),
  ('enterprise','Enterprise',200,6,true)
on conflict (tier_code) do update
set name=excluded.name,
    max_branches=excluded.max_branches,
    max_benchmark_plots=excluded.max_benchmark_plots,
    global_benchmark_enabled=excluded.global_benchmark_enabled;

-- Org columns
alter table public.orgs
  add column if not exists subscription_tier_code text not null default 'free',
  add column if not exists support_email text;

do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema='public'
      and table_name='orgs'
      and constraint_name='orgs_subscription_tier_fkey'
  ) then
    alter table public.orgs
      add constraint orgs_subscription_tier_fkey
      foreign key (subscription_tier_code)
      references public.subscription_tiers(tier_code);
  end if;
end $$;

-- RPC: org entitlements (scoped)
create or replace function public.get_org_entitlements(p_org_id uuid)
returns table(max_branches int, max_benchmark_plots int, global_benchmark_enabled boolean, tier_code text)
language sql
stable
security definer
set search_path = public
as $$
  select t.max_branches, t.max_benchmark_plots, t.global_benchmark_enabled, t.tier_code
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
    and (public.is_platform_admin() or public.is_org_member(p_org_id));
$$;

revoke all on function public.get_org_entitlements(uuid) from public;
grant execute on function public.get_org_entitlements(uuid) to authenticated;

-- =========================================
-- APPROVAL GATE: org_members.status enforced
-- =========================================

alter table public.org_members
  add column if not exists status text not null default 'pending',
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid;

do $$
begin
  if not exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema='public'
      and table_name='org_members'
      and constraint_name='org_members_status_check'
  ) then
    alter table public.org_members
      add constraint org_members_status_check
      check (status in ('pending','approved','rejected','suspended'));
  end if;
end $$;

-- Backfill existing members to approved (keeps current installs working)
update public.org_members
set status='approved',
    approved_at=coalesce(approved_at, now())
where status='pending';

-- Update is_org_member to require approved OR platform admin
create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_platform_admin()
    or exists (
      select 1
      from public.org_members m
      where m.org_id = p_org_id
        and m.user_id = auth.uid()
        and m.status = 'approved'
    );
$$;

revoke all on function public.is_org_member(uuid) from public;
grant execute on function public.is_org_member(uuid) to authenticated;

create or replace function public.is_org_super_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_platform_admin()
    or exists (
      select 1
      from public.org_members m
      where m.org_id = p_org_id
        and m.user_id = auth.uid()
        and m.status='approved'
        and m.role='super_admin'
    );
$$;

revoke all on function public.is_org_super_admin(uuid) from public;
grant execute on function public.is_org_super_admin(uuid) to authenticated;

-- Trigger: only platform admin can change org_members.status
create or replace function public.trg_org_members_status_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status then
      if not public.is_platform_admin() then
        raise exception 'Only platform admin can approve/reject/suspend members';
      end if;

      if new.status = 'approved' then
        new.approved_at := now();
        new.approved_by := auth.uid();
      end if;
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_org_members_status_guard on public.org_members;
create trigger trg_org_members_status_guard
before update on public.org_members
for each row execute function public.trg_org_members_status_guard();

-- RPC: platform admin approve/reject
create or replace function public.platform_set_member_status(
  p_org_id uuid,
  p_user_id uuid,
  p_status text,
  p_role text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  update public.org_members
  set
    status = p_status,
    role = coalesce(p_role, role)
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.platform_set_member_status(uuid,uuid,text,text) from public;
grant execute on function public.platform_set_member_status(uuid,uuid,text,text) to authenticated;

-- RPC: list pending members across all orgs (platform admin)
create or replace function public.platform_list_pending_members(p_limit int default 100)
returns table(
  org_id uuid,
  org_name text,
  user_id uuid,
  user_email text,
  role text,
  requested_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.id,
    o.name,
    m.user_id,
    p.email,
    m.role,
    m.created_at as requested_at
  from public.org_members m
  join public.orgs o on o.id = m.org_id
  left join public.profiles p on p.user_id = m.user_id
  where public.is_platform_admin()
    and m.status = 'pending'
  order by m.created_at asc
  limit greatest(1, least(p_limit, 500));
$$;

revoke all on function public.platform_list_pending_members(int) from public;
grant execute on function public.platform_list_pending_members(int) to authenticated;

-- =========================================
-- ORG + BRANCH dropdown RPCs
-- =========================================
create or replace function public.list_orgs_for_dropdown()
returns table(
  org_id uuid,
  name text,
  subscription_tier_code text,
  support_email text
)
language sql
stable
security definer
set search_path = public
as $$
  -- platform admin sees all orgs
  select o.id, o.name, o.subscription_tier_code, coalesce(o.support_email, (select support_email from public.platform_settings where id=1))
  from public.orgs o
  where public.is_platform_admin()

  union all

  -- normal users: only approved memberships
  select o.id, o.name, o.subscription_tier_code, coalesce(o.support_email, (select support_email from public.platform_settings where id=1))
  from public.orgs o
  join public.org_members m on m.org_id = o.id
  where not public.is_platform_admin()
    and m.user_id = auth.uid()
    and m.status = 'approved'
  order by name asc;
$$;

revoke all on function public.list_orgs_for_dropdown() from public;
grant execute on function public.list_orgs_for_dropdown() to authenticated;

create or replace function public.list_branches_for_org(p_org_id uuid)
returns table(branch_id uuid, code text, name text, is_default boolean)
language sql
stable
security definer
set search_path = public
as $$
  select b.id, b.code, b.name, b.is_default
  from public.branches b
  where b.org_id = p_org_id
    and public.is_org_member(p_org_id)
  order by b.is_default desc, b.name asc;
$$;

revoke all on function public.list_branches_for_org(uuid) from public;
grant execute on function public.list_branches_for_org(uuid) to authenticated;

-- =========================================
-- BRANCH LIMIT (DB trigger)
-- =========================================
create or replace function public.trg_enforce_branch_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
  v_cnt int;
begin
  if public.is_platform_admin() then
    return new;
  end if;

  select t.max_branches into v_max
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = new.org_id;

  if v_max is null then
    v_max := 1;
  end if;

  select count(*) into v_cnt
  from public.branches
  where org_id = new.org_id;

  if v_cnt >= v_max then
    raise exception 'Branch limit exceeded (max_branches=%)', v_max;
  end if;

  return new;
end $$;

drop trigger if exists trg_enforce_branch_limit on public.branches;
create trigger trg_enforce_branch_limit
before insert on public.branches
for each row execute function public.trg_enforce_branch_limit();

-- =========================================
-- BENCHMARKS: privacy-safe global points (bucketed others)
-- =========================================
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
  n int                -- null for self, bucket size for others
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days int := greatest(7, least(p_days, 365));
  v_anchor date;
  v_start date;
  v_end date;
  v_max_plots int;
  v_global boolean;
  v_other_cnt int;
  v_buckets int;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'Forbidden';
  end if;

  select public.org_anchor_date(p_org_id) into v_anchor;
  v_end := v_anchor;
  v_start := v_anchor - (v_days - 1);

  select t.max_benchmark_plots, (t.global_benchmark_enabled or public.is_platform_admin())
    into v_max_plots, v_global
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id;

  if v_max_plots is null then v_max_plots := 4; end if;

  -- Base metrics per branch (self + other)
  create temporary table tmp_branch_metrics on commit drop as
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
  where inv.invoice_date between v_start and v_end
    and inv.branch_id is not null
  group by inv.org_id, inv.branch_id, branch_name;

  select count(*) into v_other_cnt
  from tmp_branch_metrics
  where org_id <> p_org_id;

  v_buckets := greatest(1, least(20, floor(coalesce(v_other_cnt,0) / 5.0)::int));

  -- Helper CTE emulation via RETURN QUERY blocks. Plot order is fixed; tier limits restrict count.
  -- Plot 1 (order 1): Net Sales vs Gross Margin
  if v_max_plots >= 1 then
    return query
    select
      'sales_vs_margin'::text,
      'Net Sales vs Gross Margin'::text,
      'Net Sales'::text,
      'Gross Margin %'::text,
      'self'::text,
      bm.branch_id,
      bm.branch_name::text,
      bm.net_sales::numeric,
      case when bm.net_sales=0 then null else ((bm.net_sales - bm.cogs_total)/bm.net_sales) end,
      null::int
    from tmp_branch_metrics bm
    where bm.org_id = p_org_id;

    if v_global then
      return query
      with other as (
        select
          bm.net_sales::numeric as x,
          case when bm.net_sales=0 then null else ((bm.net_sales - bm.cogs_total)/bm.net_sales) end as y
        from tmp_branch_metrics bm
        where bm.org_id <> p_org_id
      ),
      b as (
        select ntile(v_buckets) over(order by x) as bucket, x, y
        from other
        where x is not null and y is not null
      )
      select
        'sales_vs_margin'::text,
        'Net Sales vs Gross Margin'::text,
        'Net Sales'::text,
        'Gross Margin %'::text,
        'others'::text,
        null::uuid,
        'Others'::text,
        avg(x),
        avg(y),
        count(*)::int
      from b
      group by bucket;
    end if;
  end if;

  -- Plot 2 (order 2): Invoices vs Avg Ticket
  if v_max_plots >= 2 then
    return query
    select
      'invoices_vs_ticket'::text,
      'Invoices vs Avg Ticket'::text,
      'Invoices'::text,
      'Avg Ticket'::text,
      'self'::text,
      bm.branch_id,
      bm.branch_name::text,
      bm.invoices::numeric,
      case when bm.invoices=0 then null else (bm.net_sales / bm.invoices) end,
      null::int
    from tmp_branch_metrics bm
    where bm.org_id = p_org_id;

    if v_global then
      return query
      with other as (
        select
          bm.invoices::numeric as x,
          case when bm.invoices=0 then null else (bm.net_sales / bm.invoices) end as y
        from tmp_branch_metrics bm
        where bm.org_id <> p_org_id
      ),
      b as (
        select ntile(v_buckets) over(order by x) as bucket, x, y
        from other
        where x is not null and y is not null
      )
      select
        'invoices_vs_ticket'::text,
        'Invoices vs Avg Ticket'::text,
        'Invoices'::text,
        'Avg Ticket'::text,
        'others'::text,
        null::uuid,
        'Others'::text,
        avg(x),
        avg(y),
        count(*)::int
      from b
      group by bucket;
    end if;
  end if;

  -- Plot 3 (order 3): Labor % vs Gross Margin
  if v_max_plots >= 3 then
    return query
    select
      'labor_pct_vs_margin'::text,
      'Labor % vs Gross Margin'::text,
      'Labor %'::text,
      'Gross Margin %'::text,
      'self'::text,
      bm.branch_id,
      bm.branch_name::text,
      case when bm.net_sales=0 then null else (bm.cogs_labor/bm.net_sales) end,
      case when bm.net_sales=0 then null else ((bm.net_sales - bm.cogs_total)/bm.net_sales) end,
      null::int
    from tmp_branch_metrics bm
    where bm.org_id = p_org_id;

    if v_global then
      return query
      with other as (
        select
          case when bm.net_sales=0 then null else (bm.cogs_labor/bm.net_sales) end as x,
          case when bm.net_sales=0 then null else ((bm.net_sales - bm.cogs_total)/bm.net_sales) end as y
        from tmp_branch_metrics bm
        where bm.org_id <> p_org_id
      ),
      b as (
        select ntile(v_buckets) over(order by x) as bucket, x, y
        from other
        where x is not null and y is not null
      )
      select
        'labor_pct_vs_margin'::text,
        'Labor % vs Gross Margin'::text,
        'Labor %'::text,
        'Gross Margin %'::text,
        'others'::text,
        null::uuid,
        'Others'::text,
        avg(x),
        avg(y),
        count(*)::int
      from b
      group by bucket;
    end if;
  end if;

  -- Plot 4 (order 4): Overhead % vs Gross Margin
  if v_max_plots >= 4 then
    return query
    select
      'overhead_pct_vs_margin'::text,
      'Overhead % vs Gross Margin'::text,
      'Overhead %'::text,
      'Gross Margin %'::text,
      'self'::text,
      bm.branch_id,
      bm.branch_name::text,
      case when bm.net_sales=0 then null else (bm.cogs_overhead/bm.net_sales) end,
      case when bm.net_sales=0 then null else ((bm.net_sales - bm.cogs_total)/bm.net_sales) end,
      null::int
    from tmp_branch_metrics bm
    where bm.org_id = p_org_id;

    if v_global then
      return query
      with other as (
        select
          case when bm.net_sales=0 then null else (bm.cogs_overhead/bm.net_sales) end as x,
          case when bm.net_sales=0 then null else ((bm.net_sales - bm.cogs_total)/bm.net_sales) end as y
        from tmp_branch_metrics bm
        where bm.org_id <> p_org_id
      ),
      b as (
        select ntile(v_buckets) over(order by x) as bucket, x, y
        from other
        where x is not null and y is not null
      )
      select
        'overhead_pct_vs_margin'::text,
        'Overhead % vs Gross Margin'::text,
        'Overhead %'::text,
        'Gross Margin %'::text,
        'others'::text,
        null::uuid,
        'Others'::text,
        avg(x),
        avg(y),
        count(*)::int
      from b
      group by bucket;
    end if;
  end if;

  -- Plot 5 (order 5): Net Sales vs Gross Profit
  if v_max_plots >= 5 then
    return query
    select
      'sales_vs_gross_profit'::text,
      'Net Sales vs Gross Profit'::text,
      'Net Sales'::text,
      'Gross Profit'::text,
      'self'::text,
      bm.branch_id,
      bm.branch_name::text,
      bm.net_sales::numeric,
      (bm.net_sales - bm.cogs_total)::numeric,
      null::int
    from tmp_branch_metrics bm
    where bm.org_id = p_org_id;

    if v_global then
      return query
      with other as (
        select
          bm.net_sales::numeric as x,
          (bm.net_sales - bm.cogs_total)::numeric as y
        from tmp_branch_metrics bm
        where bm.org_id <> p_org_id
      ),
      b as (
        select ntile(v_buckets) over(order by x) as bucket, x, y
        from other
        where x is not null and y is not null
      )
      select
        'sales_vs_gross_profit'::text,
        'Net Sales vs Gross Profit'::text,
        'Net Sales'::text,
        'Gross Profit'::text,
        'others'::text,
        null::uuid,
        'Others'::text,
        avg(x),
        avg(y),
        count(*)::int
      from b
      group by bucket;
    end if;
  end if;

  -- Plot 6 (order 6): Avg Ticket vs COGS per Unit
  if v_max_plots >= 6 then
    return query
    select
      'ticket_vs_cogs_unit'::text,
      'Avg Ticket vs COGS/Unit'::text,
      'Avg Ticket'::text,
      'COGS/Unit'::text,
      'self'::text,
      bm.branch_id,
      bm.branch_name::text,
      case when bm.invoices=0 then null else (bm.net_sales/bm.invoices) end,
      case when bm.units_sold=0 then null else (bm.cogs_total/bm.units_sold) end,
      null::int
    from tmp_branch_metrics bm
    where bm.org_id = p_org_id;

    if v_global then
      return query
      with other as (
        select
          case when bm.invoices=0 then null else (bm.net_sales/bm.invoices) end as x,
          case when bm.units_sold=0 then null else (bm.cogs_total/bm.units_sold) end as y
        from tmp_branch_metrics bm
        where bm.org_id <> p_org_id
      ),
      b as (
        select ntile(v_buckets) over(order by x) as bucket, x, y
        from other
        where x is not null and y is not null
      )
      select
        'ticket_vs_cogs_unit'::text,
        'Avg Ticket vs COGS/Unit'::text,
        'Avg Ticket'::text,
        'COGS/Unit'::text,
        'others'::text,
        null::uuid,
        'Others'::text,
        avg(x),
        avg(y),
        count(*)::int
      from b
      group by bucket;
    end if;
  end if;

end $$;

revoke all on function public.get_benchmark_points(uuid,int) from public;
grant execute on function public.get_benchmark_points(uuid,int) to authenticated;

select pg_notify('pgrst','reload schema');
commit;