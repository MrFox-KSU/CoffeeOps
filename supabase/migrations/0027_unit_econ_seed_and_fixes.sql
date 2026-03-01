begin;

-- A) Fix apply_unit_economics_to_sales_job: avoid sku ambiguity
create or replace function public.apply_unit_economics_to_sales_job(p_job_id uuid, p_wac_days int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_org uuid;
  v_wac_days int := greatest(1, least(p_wac_days, 365));
  v_day date;
  v_sku text;

  breakdown jsonb;
  mat_u numeric;
  pack_u numeric;
  lab_u numeric;
  rv_id uuid;
  st text;
  miss jsonb;

  v_rc int := 0;
  v_lines_updated int := 0;
  v_days_recomputed int := 0;

  overhead_amt numeric;
  day_net numeric;
begin
  select * into v_job from public.import_jobs where id = p_job_id;
  if not found then raise exception 'Job not found'; end if;
  if v_job.entity_type <> 'sales' then raise exception 'Only sales jobs supported'; end if;

  v_org := v_job.org_id;
  if not public.is_org_member(v_org) then raise exception 'Forbidden'; end if;

  insert into public.org_cost_engine_settings(org_id)
  values (v_org)
  on conflict (org_id) do nothing;

  for v_day in
    select distinct invoice_date
    from public.sales_invoices
    where org_id = v_org and source_import_job_id = p_job_id
  loop
    v_days_recomputed := v_days_recomputed + 1;

    for v_sku in
      select distinct si.sku
      from public.sales_items si
      join public.sales_invoices inv on inv.id = si.invoice_id
      where si.org_id = v_org and inv.invoice_date = v_day and si.sku is not null
    loop
      breakdown := public.compute_unit_cogs(v_org, v_sku, v_day, v_wac_days);

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
        and inv.invoice_date = v_day
        and si.sku = v_sku;

      get diagnostics v_rc = row_count;
      v_lines_updated := v_lines_updated + v_rc;
    end loop;

    -- Overhead allocation (OVERHEAD + UNALLOCATED already handled inside overhead_daily())
    overhead_amt := public.overhead_daily(v_org, v_day);

    select coalesce(sum(si.net_sales),0) into day_net
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = v_org and inv.invoice_date = v_day;

    if day_net <> 0 then
      update public.sales_items si
      set
        cogs_overhead = round(overhead_amt * (si.net_sales / day_net), 4),
        cogs_total = round(si.cogs_material + si.cogs_packaging + si.cogs_labor + (overhead_amt * (si.net_sales / day_net)), 4)
      from public.sales_invoices inv
      where inv.id = si.invoice_id
        and si.org_id = v_org
        and inv.invoice_date = v_day;
    end if;

  end loop;

  return jsonb_build_object(
    'ok', true,
    'job_id', p_job_id,
    'org_id', v_org,
    'wac_days', v_wac_days,
    'days_recomputed', v_days_recomputed,
    'lines_updated', v_lines_updated
  );
end $$;

revoke all on function public.apply_unit_economics_to_sales_job(uuid,int) from public;
grant execute on function public.apply_unit_economics_to_sales_job(uuid,int) to authenticated;

-- B) Unit economics RPC (uses products.product_name)
create or replace function public.get_unit_economics_by_sku(p_org_id uuid, p_days int default 30)
returns table(
  sku text,
  product_name text,
  units_sold numeric,
  net_sales numeric,
  cogs_material numeric,
  cogs_packaging numeric,
  cogs_labor numeric,
  cogs_overhead numeric,
  cogs_total numeric,
  gross_profit numeric,
  gross_margin numeric,
  cogs_per_unit numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select public.org_anchor_date(p_org_id) as a, greatest(1, least(p_days, 3650)) as d
  ),
  w as (
    select (a - (d-1))::date as start_day, a as end_day from params
  ),
  lines as (
    select
      si.sku,
      max(coalesce(si.product_name, p.product_name, si.sku)) as product_name,
      sum(si.quantity) as units_sold,
      sum(si.net_sales) as net_sales,
      sum(si.cogs_material) as cogs_material,
      sum(si.cogs_packaging) as cogs_packaging,
      sum(si.cogs_labor) as cogs_labor,
      sum(si.cogs_overhead) as cogs_overhead,
      sum(si.cogs_total) as cogs_total
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    left join public.products p on p.org_id = inv.org_id and p.sku = si.sku
    cross join w
    where inv.org_id = p_org_id
      and inv.invoice_date between w.start_day and w.end_day
      and si.sku is not null
    group by si.sku
  )
  select
    sku,
    product_name,
    units_sold,
    net_sales,
    cogs_material,
    cogs_packaging,
    cogs_labor,
    cogs_overhead,
    cogs_total,
    (net_sales - cogs_total) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs_total)/net_sales) end as gross_margin,
    case when units_sold=0 then null else (cogs_total/units_sold) end as cogs_per_unit
  from lines
  order by gross_profit desc nulls last;
$$;

revoke all on function public.get_unit_economics_by_sku(uuid,int) from public;
grant execute on function public.get_unit_economics_by_sku(uuid,int) to authenticated;

-- C) Demo seeder RPC (no SQL Editor required)
create or replace function public.seed_cost_engine_demo(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  beans uuid; milk uuid; cup uuid; lid uuid;
  rv_esp uuid; rv_lat uuid;
begin
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  insert into public.ingredients(org_id, ingredient_code, name, kind, base_uom)
  values
    (p_org_id,'BEANS','Coffee Beans','material','g'),
    (p_org_id,'MILK','Milk','material','ml'),
    (p_org_id,'CUP12','Cup 12oz','packaging','unit'),
    (p_org_id,'LID','Lid','packaging','unit')
  on conflict (org_id, ingredient_code) do update
    set name=excluded.name, kind=excluded.kind, base_uom=excluded.base_uom;

  select id into beans from public.ingredients where org_id=p_org_id and ingredient_code='BEANS';
  select id into milk  from public.ingredients where org_id=p_org_id and ingredient_code='MILK';
  select id into cup   from public.ingredients where org_id=p_org_id and ingredient_code='CUP12';
  select id into lid   from public.ingredients where org_id=p_org_id and ingredient_code='LID';

  delete from public.ingredient_receipts where org_id=p_org_id and vendor='SeedVendor';

  insert into public.ingredient_receipts(org_id, ingredient_id, receipt_date, qty_base, total_cost, currency, vendor)
  select p_org_id, ing_id, (current_date - (n||' days')::interval)::date, qty_base, total_cost, 'SAR', 'SeedVendor'
  from (
    select beans as ing_id, 10000::numeric as qty_base, 1200::numeric as total_cost
    union all select milk, 20000, 900
    union all select cup, 500, 250
    union all select lid, 500, 180
  ) base
  cross join generate_series(1,60,15) n;

  insert into public.recipe_versions(org_id, sku, effective_start, yield_qty, notes)
  values
    (p_org_id,'ESP-SGL', current_date - 365, 10, 'DEMO'),
    (p_org_id,'LAT-LRG', current_date - 365, 10, 'DEMO')
  on conflict (org_id, sku, effective_start) do update
    set yield_qty=excluded.yield_qty, notes=excluded.notes;

  select id into rv_esp from public.recipe_versions where org_id=p_org_id and sku='ESP-SGL' order by effective_start desc limit 1;
  select id into rv_lat from public.recipe_versions where org_id=p_org_id and sku='LAT-LRG' order by effective_start desc limit 1;

  insert into public.recipe_items(recipe_version_id, ingredient_id, qty, uom, loss_pct)
  values
    (rv_esp, beans, 180, 'g', 0.02),
    (rv_lat, beans, 160, 'g', 0.02)
  on conflict (recipe_version_id, ingredient_id) do update set qty=excluded.qty, loss_pct=excluded.loss_pct;

  insert into public.recipe_items(recipe_version_id, ingredient_id, qty, uom, loss_pct)
  values (rv_lat, milk, 2500, 'ml', 0.01)
  on conflict (recipe_version_id, ingredient_id) do update set qty=excluded.qty, loss_pct=excluded.loss_pct;

  insert into public.product_packaging_items(org_id, sku, ingredient_id, qty, uom)
  values
    (p_org_id,'ESP-SGL', cup, 1, 'unit'),
    (p_org_id,'ESP-SGL', lid, 1, 'unit'),
    (p_org_id,'LAT-LRG', cup, 1, 'unit'),
    (p_org_id,'LAT-LRG', lid, 1, 'unit')
  on conflict (org_id, sku, ingredient_id) do update set qty=excluded.qty;

  insert into public.labor_rates(org_id, role_code, effective_start, hourly_rate, burden_pct)
  values (p_org_id,'BARISTA', current_date - 365, 22.0, 0.25)
  on conflict (org_id, role_code, effective_start) do update
    set hourly_rate=excluded.hourly_rate, burden_pct=excluded.burden_pct;

  insert into public.product_labor_specs(org_id, sku, role_code, seconds_per_unit)
  values
    (p_org_id,'ESP-SGL','BARISTA', 35),
    (p_org_id,'LAT-LRG','BARISTA', 75)
  on conflict (org_id, sku, role_code) do update set seconds_per_unit=excluded.seconds_per_unit;

  insert into public.org_cost_engine_settings(org_id) values (p_org_id)
  on conflict (org_id) do nothing;

  return jsonb_build_object('ok', true, 'seeded', true);
end $$;

revoke all on function public.seed_cost_engine_demo(uuid) from public;
grant execute on function public.seed_cost_engine_demo(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;