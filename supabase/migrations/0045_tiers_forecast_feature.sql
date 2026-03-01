begin;

-- A) Add forecast feature flag to tiers
alter table public.subscription_tiers
  add column if not exists forecast_enabled boolean not null default false;

-- Set sane defaults (admin can edit later)
update public.subscription_tiers
set forecast_enabled = case when tier_code in ('pro','enterprise') then true else false end
where tier_code in ('free','pro','enterprise');

-- B) Expose org features to UI (member-scoped or platform admin)
create or replace function public.get_org_features(p_org_id uuid)
returns table(
  tier_code text,
  max_branches int,
  max_benchmark_plots int,
  global_benchmark_enabled boolean,
  forecast_enabled boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.tier_code,
    t.max_branches,
    t.max_benchmark_plots,
    t.global_benchmark_enabled,
    t.forecast_enabled
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
    and (public.is_platform_admin() or public.is_org_member(p_org_id));
$$;

revoke all on function public.get_org_features(uuid) from public;
grant execute on function public.get_org_features(uuid) to authenticated;

-- C) Enforce forecast feature at DB-level (no edge-function guesswork)
-- Blocks inserts into forecast_runs if tier has forecast disabled.
create or replace function public.trg_enforce_forecast_enabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_enabled boolean;
begin
  select t.forecast_enabled into v_enabled
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = new.org_id;

  if coalesce(v_enabled,false) = false then
    raise exception 'Forecast is not enabled for this subscription tier';
  end if;

  return new;
end $$;

drop trigger if exists trg_enforce_forecast_enabled on public.forecast_runs;
create trigger trg_enforce_forecast_enabled
before insert on public.forecast_runs
for each row execute function public.trg_enforce_forecast_enabled();

select pg_notify('pgrst','reload schema');
commit;