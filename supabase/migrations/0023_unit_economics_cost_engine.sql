begin;

create schema if not exists analytics;

-- ----------------------------
-- 1) Cost engine tables
-- ----------------------------

-- Ingredients catalog (materials + packaging)
create table if not exists public.ingredients (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  ingredient_code text not null,
  name text not null,
  kind text not null check (kind in ('material','packaging')),
  base_uom text not null check (base_uom in ('g','ml','unit')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, ingredient_code)
);

create index if not exists ingredients_org_idx on public.ingredients(org_id);

drop trigger if exists trg_ingredients_set_updated_at on public.ingredients;
create trigger trg_ingredients_set_updated_at
before update on public.ingredients
for each row execute function public.update_updated_at_column();

alter table public.ingredients enable row level security;
drop policy if exists ingredients_select_member on public.ingredients;
create policy ingredients_select_member
on public.ingredients
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = ingredients.org_id and m.user_id = auth.uid()));

-- Receipts/cost inputs for WAC
create table if not exists public.ingredient_receipts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id) on delete cascade,
  receipt_date date not null,
  qty_base numeric not null check (qty_base > 0),
  total_cost numeric not null check (total_cost >= 0),
  currency text null,
  vendor text null,
  created_at timestamptz not null default now()
);

create index if not exists ingredient_receipts_org_ing_date_idx
  on public.ingredient_receipts(org_id, ingredient_id, receipt_date);

alter table public.ingredient_receipts enable row level security;
drop policy if exists ingredient_receipts_select_member on public.ingredient_receipts;
create policy ingredient_receipts_select_member
on public.ingredient_receipts
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = ingredient_receipts.org_id and m.user_id = auth.uid()));

-- Recipe versions (batch with yield)
create table if not exists public.recipe_versions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  sku text not null,
  effective_start date not null,
  effective_end date null,
  yield_qty numeric not null check (yield_qty > 0),
  notes text null,
  created_at timestamptz not null default now(),
  unique (org_id, sku, effective_start)
);

create index if not exists recipe_versions_org_sku_idx on public.recipe_versions(org_id, sku);

alter table public.recipe_versions enable row level security;
drop policy if exists recipe_versions_select_member on public.recipe_versions;
create policy recipe_versions_select_member
on public.recipe_versions
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = recipe_versions.org_id and m.user_id = auth.uid()));

-- Recipe items (materials)
create table if not exists public.recipe_items (
  id uuid primary key default gen_random_uuid(),
  recipe_version_id uuid not null references public.recipe_versions(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  qty numeric not null check (qty >= 0),
  uom text not null,
  loss_pct numeric not null default 0 check (loss_pct >= 0 and loss_pct <= 1),
  created_at timestamptz not null default now(),
  unique (recipe_version_id, ingredient_id)
);

create index if not exists recipe_items_version_idx on public.recipe_items(recipe_version_id);

alter table public.recipe_items enable row level security;
drop policy if exists recipe_items_select_member on public.recipe_items;
create policy recipe_items_select_member
on public.recipe_items
for select to authenticated
using (exists (
  select 1
  from public.recipe_versions rv
  join public.org_members m on m.org_id = rv.org_id
  where rv.id = recipe_items.recipe_version_id and m.user_id = auth.uid()
));

-- Packaging items per SKU (uses ingredients(kind=packaging))
create table if not exists public.product_packaging_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  sku text not null,
  ingredient_id uuid not null references public.ingredients(id) on delete restrict,
  qty numeric not null check (qty >= 0),
  uom text not null,
  created_at timestamptz not null default now(),
  unique (org_id, sku, ingredient_id)
);

create index if not exists packaging_org_sku_idx on public.product_packaging_items(org_id, sku);

alter table public.product_packaging_items enable row level security;
drop policy if exists product_packaging_items_select_member on public.product_packaging_items;
create policy product_packaging_items_select_member
on public.product_packaging_items
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = product_packaging_items.org_id and m.user_id = auth.uid()));

-- Labor roles + rates
create table if not exists public.labor_roles (
  role_code text primary key,
  name text not null
);

insert into public.labor_roles(role_code, name)
values ('BARISTA','Barista')
on conflict (role_code) do nothing;

create table if not exists public.labor_rates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  role_code text not null references public.labor_roles(role_code) on delete restrict,
  effective_start date not null,
  hourly_rate numeric not null check (hourly_rate >= 0),
  burden_pct numeric not null default 0.25 check (burden_pct >= 0 and burden_pct <= 2),
  created_at timestamptz not null default now(),
  unique (org_id, role_code, effective_start)
);

create index if not exists labor_rates_org_role_idx on public.labor_rates(org_id, role_code, effective_start desc);

alter table public.labor_rates enable row level security;
drop policy if exists labor_rates_select_member on public.labor_rates;
create policy labor_rates_select_member
on public.labor_rates
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = labor_rates.org_id and m.user_id = auth.uid()));

-- Product labor spec per SKU (seconds per unit by role)
create table if not exists public.product_labor_specs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  sku text not null,
  role_code text not null references public.labor_roles(role_code) on delete restrict,
  seconds_per_unit int not null check (seconds_per_unit >= 0),
  created_at timestamptz not null default now(),
  unique (org_id, sku, role_code)
);

create index if not exists product_labor_org_sku_idx on public.product_labor_specs(org_id, sku);

alter table public.product_labor_specs enable row level security;
drop policy if exists product_labor_specs_select_member on public.product_labor_specs;
create policy product_labor_specs_select_member
on public.product_labor_specs
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = product_labor_specs.org_id and m.user_id = auth.uid()));

-- Settings (deterministic defaults)
create table if not exists public.org_cost_engine_settings (
  org_id uuid primary key references public.orgs(id) on delete cascade,
  wac_days int not null default 30 check (wac_days between 1 and 365),
  overhead_codes text[] not null default ARRAY['OVERHEAD']::text[],
  treat_unallocated_as_overhead boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.org_cost_engine_settings enable row level security;
drop policy if exists org_cost_engine_settings_select_member on public.org_cost_engine_settings;
create policy org_cost_engine_settings_select_member
on public.org_cost_engine_settings
for select to authenticated
using (exists (select 1 from public.org_members m where m.org_id = org_cost_engine_settings.org_id and m.user_id = auth.uid()));

-- ----------------------------
-- 2) Helper functions (uom, recipe pick, WAC, labor rate)
-- ----------------------------

create or replace function public.to_base_qty(p_qty numeric, p_uom text, p_base_uom text)
returns numeric
language plpgsql
immutable
as $$
declare u text := lower(trim(p_uom));
declare b text := lower(trim(p_base_uom));
begin
  if p_qty is null then return null; end if;
  if u = b then return p_qty; end if;

  if b='g' then
    if u='kg' then return p_qty * 1000;
    elsif u='mg' then return p_qty / 1000;
    end if;
  elsif b='ml' then
    if u='l' then return p_qty * 1000;
    end if;
  elsif b='unit' then
    if u in ('pcs','piece','pieces','unit') then return p_qty;
    end if;
  end if;

  raise exception 'Unsupported uom conversion: qty=% uom=% base=%', p_qty, p_uom, p_base_uom;
end $$;

create or replace function public.select_recipe_version_id(p_org_id uuid, p_sku text, p_as_of date)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select rv.id
  from public.recipe_versions rv
  where rv.org_id = p_org_id
    and rv.sku = p_sku
    and rv.effective_start <= p_as_of
    and (rv.effective_end is null or rv.effective_end > p_as_of)
  order by rv.effective_start desc
  limit 1;
$$;

revoke all on function public.select_recipe_version_id(uuid,text,date) from public;
grant execute on function public.select_recipe_version_id(uuid,text,date) to authenticated, service_role;

create or replace function public.select_loaded_hourly_rate(p_org_id uuid, p_role_code text, p_as_of date)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select lr.hourly_rate * (1 + lr.burden_pct)
  from public.labor_rates lr
  where lr.org_id = p_org_id
    and lr.role_code = p_role_code
    and lr.effective_start <= p_as_of
  order by lr.effective_start desc
  limit 1;
$$;

revoke all on function public.select_loaded_hourly_rate(uuid,text,date) from public;
grant execute on function public.select_loaded_hourly_rate(uuid,text,date) to authenticated, service_role;

-- WAC 30-day (or N day) with fallback last-known
create or replace function public.wac_unit_cost(p_org_id uuid, p_ingredient_id uuid, p_as_of date, p_window_days int default 30)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w int := greatest(1, least(p_window_days, 365));
  ws date := p_as_of - (w - 1);
  sum_qty numeric;
  sum_cost numeric;
  last_qty numeric;
  last_cost numeric;
begin
  select coalesce(sum(qty_base),0), coalesce(sum(total_cost),0)
    into sum_qty, sum_cost
  from public.ingredient_receipts
  where org_id=p_org_id and ingredient_id=p_ingredient_id
    and receipt_date between ws and p_as_of;

  if sum_qty > 0 then
    return sum_cost / sum_qty;
  end if;

  select qty_base, total_cost
    into last_qty, last_cost
  from public.ingredient_receipts
  where org_id=p_org_id and ingredient_id=p_ingredient_id
    and receipt_date <= p_as_of
  order by receipt_date desc
  limit 1;

  if last_qty is not null and last_qty > 0 then
    return last_cost / last_qty;
  end if;

  return null;
end $$;

revoke all on function public.wac_unit_cost(uuid,uuid,date,int) from public;
grant execute on function public.wac_unit_cost(uuid,uuid,date,int) to authenticated, service_role;

-- ----------------------------
-- 3) Unit COGS computation (material + packaging + labor)
-- ----------------------------

create or replace function public.compute_unit_cogs(p_org_id uuid, p_sku text, p_as_of date, p_wac_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w int := greatest(1, least(p_wac_days, 365));
  rv_id uuid;
  yield_qty numeric;
  mat_batch numeric := 0;
  mat_unit numeric := 0;
  pack_unit numeric := 0;
  labor_unit numeric := 0;

  missing jsonb := '[]'::jsonb;
  status text := 'ok';
  model text := 'wac30_recipe_labor_pack_oh_v1';

  rec record;
  cost numeric;
  base_uom text;
  qty_base numeric;
  loaded_rate numeric;
begin
  rv_id := public.select_recipe_version_id(p_org_id, p_sku, p_as_of);

  if rv_id is null then
    -- fallback to products.unit_cost as material
    select coalesce(p.unit_cost,0) into mat_unit
    from public.products p
    where p.org_id=p_org_id and p.sku=p_sku;

    status := 'fallback';
    missing := missing || jsonb_build_array('missing_recipe');
  else
    select rv.yield_qty into yield_qty from public.recipe_versions rv where rv.id=rv_id;

    for rec in
      select ri.qty, ri.uom, ri.loss_pct, i.id as ingredient_id, i.base_uom, i.ingredient_code
      from public.recipe_items ri
      join public.ingredients i on i.id = ri.ingredient_id
      where ri.recipe_version_id = rv_id
    loop
      cost := public.wac_unit_cost(p_org_id, rec.ingredient_id, p_as_of, w);
      if cost is null then
        status := 'missing_inputs';
        missing := missing || jsonb_build_array('ingredient_cost:' || rec.ingredient_code);
        continue;
      end if;

      qty_base := public.to_base_qty(rec.qty, rec.uom, rec.base_uom) * (1 + rec.loss_pct);
      mat_batch := mat_batch + (qty_base * cost);
    end loop;

    mat_unit := case when yield_qty is null or yield_qty = 0 then 0 else (mat_batch / yield_qty) end;
  end if;

  -- Packaging per unit
  for rec in
    select pi.qty, pi.uom, i.id as ingredient_id, i.base_uom, i.ingredient_code
    from public.product_packaging_items pi
    join public.ingredients i on i.id = pi.ingredient_id
    where pi.org_id = p_org_id and pi.sku = p_sku
  loop
    cost := public.wac_unit_cost(p_org_id, rec.ingredient_id, p_as_of, w);
    if cost is null then
      if status = 'ok' then status := 'missing_inputs'; end if;
      missing := missing || jsonb_build_array('packaging_cost:' || rec.ingredient_code);
      continue;
    end if;

    qty_base := public.to_base_qty(rec.qty, rec.uom, rec.base_uom);
    pack_unit := pack_unit + (qty_base * cost);
  end loop;

  -- Labor per unit
  for rec in
    select pls.role_code, pls.seconds_per_unit
    from public.product_labor_specs pls
    where pls.org_id = p_org_id and pls.sku = p_sku
  loop
    loaded_rate := public.select_loaded_hourly_rate(p_org_id, rec.role_code, p_as_of);
    if loaded_rate is null then
      if status = 'ok' then status := 'missing_inputs'; end if;
      missing := missing || jsonb_build_array('labor_rate:' || rec.role_code);
      continue;
    end if;

    labor_unit := labor_unit + ((rec.seconds_per_unit::numeric / 3600) * loaded_rate);
  end loop;

  return jsonb_build_object(
    'sku', p_sku,
    'as_of', p_as_of,
    'wac_days', w,
    'recipe_version_id', rv_id,
    'material_unit', round(mat_unit, 6),
    'packaging_unit', round(pack_unit, 6),
    'labor_unit', round(labor_unit, 6),
    'status', status,
    'missing', missing,
    'model', model
  );
end $$;

revoke all on function public.compute_unit_cogs(uuid,text,date,int) from public;
grant execute on function public.compute_unit_cogs(uuid,text,date,int) to authenticated, service_role;

-- ----------------------------
-- 4) Overhead daily + apply unit economics to sales job
-- ----------------------------

create or replace function public.overhead_daily(p_org_id uuid, p_day date)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  with overhead_alloc as (
    select coalesce(sum(a.amount),0) as amt
    from public.expense_allocations a
    join public.expenses e on e.id = a.expense_id
    where e.org_id = p_org_id
      and e.expense_date = p_day
      and upper(a.cost_center_code) = 'OVERHEAD'
  ),
  unallocated as (
    select coalesce(sum(e.amount),0) as amt
    from public.expenses e
    where e.org_id = p_org_id
      and e.expense_date = p_day
      and not exists (select 1 from public.expense_allocations a where a.expense_id = e.id)
  )
  select (select amt from overhead_alloc) + (select amt from unallocated);
$$;

revoke all on function public.overhead_daily(uuid,date) from public;
grant execute on function public.overhead_daily(uuid,date) to authenticated, service_role;

-- Apply engine costs to all sales lines on days touched by a sales import job
create or replace function public.apply_unit_economics_to_sales_job(p_job_id uuid, p_wac_days int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_org uuid;
  w int := greatest(1, least(p_wac_days, 365));
  d date;
  sku text;
  breakdown jsonb;
  mat_u numeric;
  pack_u numeric;
  lab_u numeric;
  rv_id uuid;
  st text;
  miss jsonb;
  updated_lines int := 0;
  updated_days int := 0;

  v_rc int := 0;
  overhead_amt numeric;
  day_net numeric;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;
  if v_job.entity_type <> 'sales' then raise exception 'Only sales jobs supported'; end if;

  v_org := v_job.org_id;
  if not public.is_org_member(v_org) then raise exception 'Forbidden'; end if;

  -- Ensure settings row exists (deterministic)
  insert into public.org_cost_engine_settings(org_id)
  values (v_org)
  on conflict (org_id) do nothing;

  -- Days affected by this job (invoices imported by this job)
  for d in
    select distinct invoice_date
    from public.sales_invoices
    where org_id = v_org and source_import_job_id = p_job_id
  loop
    updated_days := updated_days + 1;

    -- Compute unit economics per (day, sku) once, then update all lines
    for sku in
      select distinct si.sku
      from public.sales_items si
      join public.sales_invoices inv on inv.id = si.invoice_id
      where si.org_id = v_org and inv.invoice_date = d and si.sku is not null
    loop
      breakdown := public.compute_unit_cogs(v_org, sku, d, w);
      mat_u := (breakdown->>'material_unit')::numeric;
      pack_u := (breakdown->>'packaging_unit')::numeric;
      lab_u := (breakdown->>'labor_unit')::numeric;
      rv_id := nullif(breakdown->>'recipe_version_id','')::uuid;
      st := breakdown->>'status';
      miss := breakdown->'missing';

      update public.sales_items si
      set
        cogs_material = round(si.quantity * mat_u, 4),
        cogs_packaging = round(si.quantity * pack_u, 4),
        cogs_labor = round(si.quantity * lab_u, 4),
        cogs_model = breakdown->>'model',
        cogs_status = st,
        cogs_missing = coalesce(miss,'[]'::jsonb),
        recipe_version_id = rv_id
      from public.sales_invoices inv
      where inv.id = si.invoice_id
        and si.org_id = v_org
        and inv.invoice_date = d
        and si.sku = sku;

      get diagnostics v_rc = row_count;
      updated_lines := updated_lines + v_rc;
    end loop;

    -- Lines without sku: mark missing inputs deterministically
    update public.sales_items si
    set
      cogs_material = 0,
      cogs_packaging = 0,
      cogs_labor = 0,
      cogs_model = 'wac30_missing_sku_v1',
      cogs_status = 'missing_inputs',
      cogs_missing = jsonb_build_array('missing_sku')
    from public.sales_invoices inv
    where inv.id = si.invoice_id
      and si.org_id = v_org
      and inv.invoice_date = d
      and si.sku is null;

    -- Overhead allocation for the day (OVERHEAD + UNALLOCATED)
    overhead_amt := public.overhead_daily(v_org, d);

    select coalesce(sum(si.net_sales),0) into day_net
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = v_org and inv.invoice_date = d;

    if day_net <> 0 then
      update public.sales_items si
      set
        cogs_overhead = round(overhead_amt * (si.net_sales / day_net), 4),
        cogs_total = round(si.cogs_material + si.cogs_packaging + si.cogs_labor + (overhead_amt * (si.net_sales / day_net)), 4)
      from public.sales_invoices inv
      where inv.id = si.invoice_id
        and si.org_id = v_org
        and inv.invoice_date = d;
    else
      update public.sales_items si
      set
        cogs_overhead = 0,
        cogs_total = round(si.cogs_material + si.cogs_packaging + si.cogs_labor, 4),
        cogs_status = case when si.cogs_status='ok' then 'missing_inputs' else si.cogs_status end,
        cogs_missing = (coalesce(si.cogs_missing,'[]'::jsonb) || jsonb_build_array('overhead_unallocatable_day'))
      from public.sales_invoices inv
      where inv.id = si.invoice_id
        and si.org_id = v_org
        and inv.invoice_date = d;
    end if;

  end loop;

  return jsonb_build_object(
    'ok', true,
    'job_id', p_job_id,
    'org_id', v_org,
    'wac_days', w,
    'days_recomputed', updated_days,
    'lines_updated', updated_lines
  );
end $$;

revoke all on function public.apply_unit_economics_to_sales_job(uuid,int) from public;
grant execute on function public.apply_unit_economics_to_sales_job(uuid,int) to authenticated;

-- ----------------------------
-- 5) Extend sales_items schema for stored COGS
-- ----------------------------
alter table public.sales_items
  add column if not exists cogs_material numeric not null default 0,
  add column if not exists cogs_packaging numeric not null default 0,
  add column if not exists cogs_labor numeric not null default 0,
  add column if not exists cogs_overhead numeric not null default 0,
  add column if not exists cogs_total numeric not null default 0,
  add column if not exists cogs_model text not null default 'none',
  add column if not exists cogs_status text not null default 'uncomputed',
  add column if not exists cogs_missing jsonb not null default '[]'::jsonb,
  add column if not exists recipe_version_id uuid null references public.recipe_versions(id);

-- ----------------------------
-- 6) Update dispatcher to apply unit economics after sales import
-- ----------------------------
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_res jsonb;
  v_cost jsonb;
  w int;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;

  if v_job.entity_type='products' then
    return public.import_products_from_staging(p_job_id);
  elsif v_job.entity_type='sales' then
    v_res := public.import_sales_from_staging(p_job_id);

    select coalesce(s.wac_days,30) into w
    from public.org_cost_engine_settings s
    where s.org_id = v_job.org_id;

    v_cost := public.apply_unit_economics_to_sales_job(p_job_id, w);
    return v_res || jsonb_build_object('unit_economics', v_cost);
  elsif v_job.entity_type='expenses' then
    v_res := public.import_expenses_from_staging(p_job_id);
    perform public.auto_allocate_expenses_for_job(p_job_id);
    return v_res;
  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end $$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;
