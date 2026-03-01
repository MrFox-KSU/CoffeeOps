begin;

-- Add engine/visibility columns
alter table public.forecast_runs
  add column if not exists engine text not null default 'github_free',
  add column if not exists visibility text not null default 'org';

alter table public.forecast_outputs
  add column if not exists engine text not null default 'github_free',
  add column if not exists visibility text not null default 'org';

-- Backfill legacy runs
update public.forecast_runs
set engine = 'edge'
where model = 'hsar_ridge_v1';

update public.forecast_outputs o
set engine = r.engine
from public.forecast_runs r
where r.id = o.run_id;

-- Constraints (idempotent)
do $$
begin
  if not exists (select 1 from information_schema.table_constraints where constraint_schema='public' and table_name='forecast_runs' and constraint_name='forecast_runs_engine_check') then
    alter table public.forecast_runs add constraint forecast_runs_engine_check check (engine in ('edge','github_free','paid_premium'));
  end if;

  if not exists (select 1 from information_schema.table_constraints where constraint_schema='public' and table_name='forecast_runs' and constraint_name='forecast_runs_visibility_check') then
    alter table public.forecast_runs add constraint forecast_runs_visibility_check check (visibility in ('org','platform'));
  end if;

  if not exists (select 1 from information_schema.table_constraints where constraint_schema='public' and table_name='forecast_outputs' and constraint_name='forecast_outputs_engine_check') then
    alter table public.forecast_outputs add constraint forecast_outputs_engine_check check (engine in ('edge','github_free','paid_premium'));
  end if;

  if not exists (select 1 from information_schema.table_constraints where constraint_schema='public' and table_name='forecast_outputs' and constraint_name='forecast_outputs_visibility_check') then
    alter table public.forecast_outputs add constraint forecast_outputs_visibility_check check (visibility in ('org','platform'));
  end if;
end $$;

-- Fix forecast RLS: platform admin sees all, users see only approved orgs (via is_org_member)
alter table public.forecast_runs enable row level security;
alter table public.forecast_outputs enable row level security;

drop policy if exists forecast_runs_select_member on public.forecast_runs;
create policy forecast_runs_select_member
on public.forecast_runs
for select to authenticated
using (public.is_platform_admin() or (visibility='org' and public.is_org_member(org_id)));

drop policy if exists forecast_outputs_select_member on public.forecast_outputs;
create policy forecast_outputs_select_member
on public.forecast_outputs
for select to authenticated
using (public.is_platform_admin() or (visibility='org' and public.is_org_member(org_id)));

-- Update trigger to allow platform admin and block paid for non-admin
create or replace function public.trg_enforce_forecast_enabled()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare v_enabled boolean;
begin
  if public.is_platform_admin() then return new; end if;

  if coalesce(new.visibility,'org') <> 'org' then
    raise exception 'Forbidden: platform-visible forecasts are admin-only';
  end if;

  if coalesce(new.engine,'github_free') = 'paid_premium' then
    raise exception 'Forbidden: paid forecast is admin-only';
  end if;

  select t.forecast_enabled into v_enabled
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = new.org_id;

  if coalesce(v_enabled,false) = false then
    raise exception 'Forecast is not enabled for this subscription tier';
  end if;

  return new;
end $$;

-- Branch history RPC
create or replace function public.get_sales_daily_range_branch(
  p_org_id uuid,
  p_branch_id uuid,
  p_start date,
  p_end date
)
returns table(day date, net_sales numeric)
language sql
stable
security definer
set search_path = public
as $$
  select inv.invoice_date as day, sum(si.net_sales) as net_sales
  from public.sales_items si
  join public.sales_invoices inv on inv.id = si.invoice_id
  where inv.org_id = p_org_id
    and inv.branch_id = p_branch_id
    and inv.invoice_date between p_start and p_end
  group by inv.invoice_date
  order by inv.invoice_date asc;
$$;

revoke all on function public.get_sales_daily_range_branch(uuid,uuid,date,date) from public;
grant execute on function public.get_sales_daily_range_branch(uuid,uuid,date,date) to authenticated, service_role;

-- Create forecast run RPC
create or replace function public.create_forecast_run(
  p_org_id uuid,
  p_branch_id uuid default null,
  p_horizon_days int default 30,
  p_history_days int default 365,
  p_engine text default 'github_free'
)
returns public.forecast_runs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_anchor date;
  v_run public.forecast_runs;
  v_engine text := coalesce(nullif(p_engine,''),'github_free');
  v_visibility text := case when v_engine='paid_premium' then 'platform' else 'org' end;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  if v_engine='paid_premium' then
    if not public.is_platform_admin() then raise exception 'Forbidden'; end if;
  else
    if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;
  end if;

  v_anchor := public.org_anchor_date(p_org_id);

  insert into public.forecast_runs(
    org_id, created_by, model,
    horizon_days, history_days, anchor_date,
    status, params, branch_id,
    engine, visibility
  ) values (
    p_org_id, v_user,
    case when v_engine='paid_premium' then 'premium_service_v1' else 'github_lgbm_v1' end,
    greatest(1, least(p_horizon_days, 365)),
    greatest(30, least(p_history_days, 3650)),
    v_anchor,
    'queued',
    jsonb_build_object('engine', v_engine),
    p_branch_id,
    v_engine,
    v_visibility
  )
  returning * into v_run;

  return v_run;
end $$;

revoke all on function public.create_forecast_run(uuid,uuid,int,int,text) from public;
grant execute on function public.create_forecast_run(uuid,uuid,int,int,text) to authenticated;

select pg_notify('pgrst','reload schema');
commit;