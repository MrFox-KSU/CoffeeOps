begin;

-- Tier flag: paid premium availability (keep false for now)
alter table public.subscription_tiers
  add column if not exists paid_forecast_enabled boolean not null default false;

update public.subscription_tiers
set paid_forecast_enabled = false;

-- Entitlements v2 (used by forecast UI)
create or replace function public.get_forecast_entitlements_v2(p_org_id uuid)
returns table(
  tier_code text,
  forecast_enabled boolean,
  max_forecast_runs_per_day int,
  max_forecast_horizon_days int,
  max_forecast_history_days int,
  paid_forecast_enabled boolean,
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
    t.paid_forecast_enabled,
    public.is_platform_admin() as can_use_paid
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
    and (public.is_platform_admin() or public.is_org_member(p_org_id));
$$;

revoke all on function public.get_forecast_entitlements_v2(uuid) from public;
grant execute on function public.get_forecast_entitlements_v2(uuid) to authenticated;

-- Enforce paid rules inside create_forecast_run (signature unchanged)
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
  v_paid_enabled boolean;
  v_max_runs int;
  v_max_h int;
  v_max_hist int;

  v_used_today int;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  select o.subscription_tier_code,
         t.forecast_enabled,
         t.paid_forecast_enabled,
         t.max_forecast_runs_per_day,
         t.max_forecast_horizon_days,
         t.max_forecast_history_days
    into v_tier, v_enabled, v_paid_enabled, v_max_runs, v_max_h, v_max_hist
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id;

  if v_engine = 'paid_premium' then
    if not public.is_platform_admin() then
      raise exception 'Forbidden';
    end if;
    if coalesce(v_paid_enabled,false) = false then
      raise exception 'Paid premium forecast is not enabled for tier %', v_tier;
    end if;
  else
    if not public.is_org_member(p_org_id) then
      raise exception 'Forbidden';
    end if;
    if coalesce(v_enabled,false) = false then
      raise exception 'Forecast disabled for tier %', v_tier;
    end if;

    -- runs/day
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