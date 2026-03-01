begin;

-- =========================================================
-- A) Add engine + visibility (no breaking changes)
-- =========================================================
alter table public.forecast_runs
  add column if not exists engine text not null default 'edge',
  add column if not exists visibility text not null default 'org';

alter table public.forecast_outputs
  add column if not exists engine text not null default 'edge',
  add column if not exists visibility text not null default 'org';

-- Constraints (idempotent)
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public' and table_name='forecast_runs' and constraint_name='forecast_runs_engine_check'
  ) then
    alter table public.forecast_runs
      add constraint forecast_runs_engine_check check (engine in ('edge','github_free','paid_premium'));
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public' and table_name='forecast_runs' and constraint_name='forecast_runs_visibility_check'
  ) then
    alter table public.forecast_runs
      add constraint forecast_runs_visibility_check check (visibility in ('org','platform'));
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public' and table_name='forecast_outputs' and constraint_name='forecast_outputs_visibility_check'
  ) then
    alter table public.forecast_outputs
      add constraint forecast_outputs_visibility_check check (visibility in ('org','platform'));
  end if;
end $$;

-- =========================================================
-- B) RLS: paid/premium is platform-admin only (enforced)
-- =========================================================
drop policy if exists forecast_runs_select_member on public.forecast_runs;
create policy forecast_runs_select_member
on public.forecast_runs
for select to authenticated
using (
  public.is_platform_admin()
  or (visibility = 'org' and public.is_org_member(org_id))
);

drop policy if exists forecast_outputs_select_member on public.forecast_outputs;
create policy forecast_outputs_select_member
on public.forecast_outputs
for select to authenticated
using (
  public.is_platform_admin()
  or (visibility = 'org' and public.is_org_member(org_id))
);

-- =========================================================
-- C) Update forecast_enabled trigger:
--    - platform admin can always insert
--    - non-admin cannot insert platform-visible or paid engine
-- =========================================================
create or replace function public.trg_enforce_forecast_enabled()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare v_enabled boolean;
begin
  -- Platform admin override (needed for premium later + admin testing)
  if public.is_platform_admin() then
    return new;
  end if;

  -- Non-admin cannot create platform-visible runs
  if coalesce(new.visibility,'org') <> 'org' then
    raise exception 'Forbidden: platform-visible forecasts are admin-only';
  end if;

  -- Non-admin cannot use paid engine
  if new.engine = 'paid_premium' then
    raise exception 'Forbidden: paid forecast is admin-only';
  end if;

  -- Standard tier gating
  select t.forecast_enabled into v_enabled
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = new.org_id;

  if coalesce(v_enabled,false) = false then
    raise exception 'Forecast is not enabled for this subscription tier';
  end if;

  return new;
end $$;

-- =========================================================
-- D) Create RPC: branch-aware sales daily range (for GitHub training/predict)
-- =========================================================
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
  select
    inv.invoice_date as day,
    sum(si.net_sales) as net_sales
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

-- =========================================================
-- E) Model configs (admin-only) for tuning knobs
-- =========================================================
create table if not exists public.forecast_model_configs (
  engine text not null,
  target text not null default 'net_sales',
  granularity text not null, -- 'org'|'branch'
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (engine, target, granularity)
);

alter table public.forecast_model_configs enable row level security;

drop policy if exists forecast_model_configs_admin on public.forecast_model_configs;
create policy forecast_model_configs_admin
on public.forecast_model_configs
for all to authenticated
using (public.is_platform_admin())
with check (public.is_platform_admin());

insert into public.forecast_model_configs(engine,target,granularity,config)
values
  ('github_free','net_sales','org', jsonb_build_object(
    'algo','lgbm_quantile',
    'quantiles', jsonb_build_array(0.05,0.10,0.50,0.90,0.95),
    'lags', jsonb_build_array(1,7,14,28),
    'rolling', jsonb_build_array(7,14,28),
    'cv_folds', 5
  )),
  ('github_free','net_sales','branch', jsonb_build_object(
    'algo','lgbm_quantile',
    'quantiles', jsonb_build_array(0.05,0.10,0.50,0.90,0.95),
    'lags', jsonb_build_array(1,7,14,28),
    'rolling', jsonb_build_array(7,14,28),
    'cv_folds', 5
  )),
  ('paid_premium','net_sales','org', jsonb_build_object(
    'algo','service',
    'notes','Configured later via secrets/endpoint'
  )),
  ('paid_premium','net_sales','branch', jsonb_build_object(
    'algo','service',
    'notes','Configured later via secrets/endpoint'
  ))
on conflict (engine,target,granularity) do update
set config = excluded.config,
    updated_at = now();

-- =========================================================
-- F) RPC: create forecast run (used by edge function)
-- =========================================================
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
  v_model text := case
    when v_engine='paid_premium' then 'premium_service_v1'
    when v_engine='github_free' then 'github_lgbm_v1'
    else 'edge_ets_v1'
  end;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  if v_visibility='platform' then
    if not public.is_platform_admin() then
      raise exception 'Forbidden';
    end if;
  else
    if not public.is_org_member(p_org_id) then
      raise exception 'Forbidden';
    end if;
  end if;

  v_anchor := public.org_anchor_date(p_org_id);

  insert into public.forecast_runs(
    org_id, created_by, model,
    horizon_days, history_days, anchor_date,
    status, params, branch_id,
    engine, visibility
  ) values (
    p_org_id, v_user, v_model,
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