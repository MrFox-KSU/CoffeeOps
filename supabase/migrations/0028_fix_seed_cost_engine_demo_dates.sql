begin;

create or replace function public.seed_cost_engine_demo(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a date;
  beans uuid; milk uuid; cup uuid; lid uuid;
  rv_esp uuid; rv_lat uuid;
begin
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  -- Align seed dates to your real sales/expense dates
  a := public.org_anchor_date(p_org_id);

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
  select p_org_id, ing_id, (a - (n||' days')::interval)::date, qty_base, total_cost, 'SAR', 'SeedVendor'
  from (
    select beans as ing_id, 10000::numeric as qty_base, 1200::numeric as total_cost
    union all select milk, 20000, 900
    union all select cup, 500, 250
    union all select lid, 500, 180
  ) base
  cross join generate_series(0,60,15) n;

  insert into public.recipe_versions(org_id, sku, effective_start, yield_qty, notes)
  values
    (p_org_id,'ESP-SGL', (a - interval '365 days')::date, 10, 'DEMO'),
    (p_org_id,'LAT-LRG', (a - interval '365 days')::date, 10, 'DEMO')
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
  values (p_org_id,'BARISTA', (a - interval '365 days')::date, 22.0, 0.25)
  on conflict (org_id, role_code, effective_start) do update
    set hourly_rate=excluded.hourly_rate, burden_pct=excluded.burden_pct;

  insert into public.product_labor_specs(org_id, sku, role_code, seconds_per_unit)
  values
    (p_org_id,'ESP-SGL','BARISTA', 35),
    (p_org_id,'LAT-LRG','BARISTA', 75)
  on conflict (org_id, sku, role_code) do update set seconds_per_unit=excluded.seconds_per_unit;

  insert into public.org_cost_engine_settings(org_id) values (p_org_id)
  on conflict (org_id) do nothing;

  return jsonb_build_object('ok', true, 'seeded', true, 'anchor_date', a);
end $$;

revoke all on function public.seed_cost_engine_demo(uuid) from public;
grant execute on function public.seed_cost_engine_demo(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;