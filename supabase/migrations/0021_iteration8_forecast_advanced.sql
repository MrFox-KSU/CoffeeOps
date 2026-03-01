begin;

-- Forecast runs (idempotent)
create table if not exists public.forecast_runs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  created_by uuid not null,
  model text not null default 'hsar_ridge_v1',
  horizon_days int not null default 30 check (horizon_days between 1 and 365),
  history_days int not null default 365 check (history_days between 30 and 3650),
  anchor_date date not null,
  status text not null check (status in ('queued','running','succeeded','failed')),
  metrics jsonb not null default '{}'::jsonb,
  params jsonb not null default '{}'::jsonb,
  message text null,
  created_at timestamptz not null default now(),
  started_at timestamptz null,
  finished_at timestamptz null
);

create index if not exists forecast_runs_org_created_idx on public.forecast_runs(org_id, created_at desc);

-- Forecast outputs (P50 + intervals)
create table if not exists public.forecast_outputs (
  id bigserial primary key,
  run_id uuid not null references public.forecast_runs(id) on delete cascade,
  org_id uuid not null references public.orgs(id) on delete cascade,
  day date not null,
  p50_net_sales numeric not null,
  p80_low numeric not null,
  p80_high numeric not null,
  p95_low numeric not null,
  p95_high numeric not null,
  created_at timestamptz not null default now(),
  unique(run_id, day)
);

create index if not exists forecast_outputs_run_day_idx on public.forecast_outputs(run_id, day);

-- RLS read for org members
alter table public.forecast_runs enable row level security;
alter table public.forecast_outputs enable row level security;

drop policy if exists forecast_runs_select_member on public.forecast_runs;
create policy forecast_runs_select_member
on public.forecast_runs
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = forecast_runs.org_id and m.user_id = auth.uid()));

drop policy if exists forecast_outputs_select_member on public.forecast_outputs;
create policy forecast_outputs_select_member
on public.forecast_outputs
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = forecast_outputs.org_id and m.user_id = auth.uid()));

-- Helper: daily net sales range (deterministic)
create or replace function public.get_sales_daily_range(p_org_id uuid, p_start date, p_end date)
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
    and inv.invoice_date between p_start and p_end
  group by inv.invoice_date
  order by inv.invoice_date asc;
$$;

revoke all on function public.get_sales_daily_range(uuid,date,date) from public;
grant execute on function public.get_sales_daily_range(uuid,date,date) to authenticated, service_role;

-- List runs for org
create or replace function public.list_forecast_runs(p_org_id uuid, p_limit int default 20)
returns table(id uuid, created_at timestamptz, status text, horizon_days int, history_days int, anchor_date date, model text, message text)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.created_at, r.status, r.horizon_days, r.history_days, r.anchor_date, r.model, r.message
  from public.forecast_runs r
  where r.org_id = p_org_id
  order by r.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

revoke all on function public.list_forecast_runs(uuid,int) from public;
grant execute on function public.list_forecast_runs(uuid,int) to authenticated;

-- Outputs for run
create or replace function public.get_forecast_outputs(p_run_id uuid)
returns table(day date, p50_net_sales numeric, p80_low numeric, p80_high numeric, p95_low numeric, p95_high numeric)
language sql
stable
security definer
set search_path = public
as $$
  select o.day, o.p50_net_sales, o.p80_low, o.p80_high, o.p95_low, o.p95_high
  from public.forecast_outputs o
  where o.run_id = p_run_id
  order by o.day asc;
$$;

revoke all on function public.get_forecast_outputs(uuid) from public;
grant execute on function public.get_forecast_outputs(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;
