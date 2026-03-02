begin;

-- ------------------------------------------------------------
-- A) Add forecast controls to subscription tiers (idempotent)
-- ------------------------------------------------------------
alter table public.subscription_tiers
  add column if not exists forecast_enabled boolean not null default true,
  add column if not exists max_forecast_runs_per_day int not null default 3,
  add column if not exists max_forecast_horizon_days int not null default 30,
  add column if not exists max_forecast_history_days int not null default 365;

do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public' and table_name='subscription_tiers'
      and constraint_name='subscription_tiers_max_forecast_runs_per_day_check'
  ) then
    alter table public.subscription_tiers
      add constraint subscription_tiers_max_forecast_runs_per_day_check
      check (max_forecast_runs_per_day between 0 and 1000);
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public' and table_name='subscription_tiers'
      and constraint_name='subscription_tiers_max_forecast_horizon_days_check'
  ) then
    alter table public.subscription_tiers
      add constraint subscription_tiers_max_forecast_horizon_days_check
      check (max_forecast_horizon_days between 1 and 3650);
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_schema='public' and table_name='subscription_tiers'
      and constraint_name='subscription_tiers_max_forecast_history_days_check'
  ) then
    alter table public.subscription_tiers
      add constraint subscription_tiers_max_forecast_history_days_check
      check (max_forecast_history_days between 30 and 3650);
  end if;
end $$;

-- Sensible defaults (platform admin can edit later)
update public.subscription_tiers
set
  forecast_enabled = true,
  max_forecast_runs_per_day = case
    when tier_code='free' then 3
    when tier_code='pro' then 20
    when tier_code='enterprise' then 200
    else max_forecast_runs_per_day
  end,
  max_forecast_horizon_days = case
    when tier_code='free' then 30
    when tier_code='pro' then 90
    when tier_code='enterprise' then 365
    else max_forecast_horizon_days
  end,
  max_forecast_history_days = case
    when tier_code='free' then 365
    when tier_code='pro' then 730
    when tier_code='enterprise' then 1825
    else max_forecast_history_days
  end;

-- ------------------------------------------------------------
-- B) Entitlements RPC for UI (do NOT change existing RPC return types)
-- ------------------------------------------------------------
create or replace function public.get_forecast_entitlements(p_org_id uuid)
returns table(
  tier_code text,
  forecast_enabled boolean,
  max_forecast_runs_per_day int,
  max_forecast_horizon_days int,
  max_forecast_history_days int,
  can_use_paid boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.subscription_tier_code as tier_code,
    t.forecast_enabled,
    t.max_forecast_runs_per_day,
    t.max_forecast_horizon_days,
    t.max_forecast_history_days,
    public.is_platform_admin() as can_use_paid
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
    and (public.is_platform_admin() or public.is_org_member(p_org_id));
$$;

revoke all on function public.get_forecast_entitlements(uuid) from public;
grant execute on function public.get_forecast_entitlements(uuid) to authenticated;

-- ------------------------------------------------------------
-- C) Enforce limits in create_forecast_run (signature unchanged)
-- ------------------------------------------------------------
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

  v_tier text;
  v_enabled boolean;
  v_max_runs int;
  v_max_h int;
  v_max_hist int;

  v_used_today int;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  -- Membership / admin rules
  if v_engine='paid_premium' then
    if not public.is_platform_admin() then raise exception 'Forbidden'; end if;
  else
    if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;
  end if;

  -- Load tier entitlements
  select o.subscription_tier_code, t.forecast_enabled, t.max_forecast_runs_per_day, t.max_forecast_horizon_days, t.max_forecast_history_days
    into v_tier, v_enabled, v_max_runs, v_max_h, v_max_hist
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id;

  if not public.is_platform_admin() then
    if coalesce(v_enabled,false) = false then
      raise exception 'Forecast disabled for tier %', v_tier;
    end if;

    -- Users can only run github_free (paid_premium already blocked above)
    if v_engine <> 'github_free' then
      raise exception 'Forbidden';
    end if;

    -- Per-org daily run limit
    if coalesce(v_max_runs,0) > 0 then
      select count(*) into v_used_today
      from public.forecast_runs r
      where r.org_id = p_org_id
        and r.created_at >= date_trunc('day', now())
        and r.created_at <  date_trunc('day', now()) + interval '1 day'
        and r.engine = 'github_free';

      if v_used_today >= v_max_runs then
        raise exception 'Daily forecast limit reached (%/%). Tier=%', v_used_today, v_max_runs, v_tier;
      end if;
    end if;

    -- Horizon / history limits
    if p_horizon_days > v_max_h then
      raise exception 'Horizon exceeds tier limit (requested %, max %). Tier=%', p_horizon_days, v_max_h, v_tier;
    end if;

    if p_history_days > v_max_hist then
      raise exception 'History exceeds tier limit (requested %, max %). Tier=%', p_history_days, v_max_hist, v_tier;
    end if;
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
    greatest(1, least(p_horizon_days, 3650)),
    greatest(30, least(p_history_days, 3650)),
    v_anchor,
    'queued',
    jsonb_build_object('engine', v_engine, 'tier', v_tier),
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