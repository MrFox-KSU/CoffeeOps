begin;

-- Ingredients (materials + packaging)
insert into public.ingredients(org_id, ingredient_code, name, kind, base_uom)
values
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','BEANS','Coffee Beans','material','g'),
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','MILK','Milk','material','ml'),
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','CUP12','Cup 12oz','packaging','unit'),
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','LID','Lid','packaging','unit')
on conflict (org_id, ingredient_code) do update set name=excluded.name, kind=excluded.kind, base_uom=excluded.base_uom;

-- Receipts (WAC inputs) over last 60 days (every 15 days)
insert into public.ingredient_receipts(org_id, ingredient_id, receipt_date, qty_base, total_cost, currency, vendor)
select
  '2f0c88c6-3de8-48aa-b39c-bb085d37a568',
  i.id,
  (current_date - (n||' days')::interval)::date as receipt_date,
  case i.ingredient_code
    when 'BEANS' then 10000
    when 'MILK'  then 20000
    when 'CUP12' then 500
    when 'LID'   then 500
  end as qty_base,
  case i.ingredient_code
    when 'BEANS' then 1200
    when 'MILK'  then 900
    when 'CUP12' then 250
    when 'LID'   then 180
  end as total_cost,
  'SAR',
  'SeedVendor'
from public.ingredients i
cross join generate_series(1,60,15) n
where i.org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568'
on conflict do nothing;

-- Recipe versions (batch yield 10)
insert into public.recipe_versions(org_id, sku, effective_start, yield_qty, notes)
values
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','ESP-SGL', current_date - 365, 10, 'Batch yield 10 shots'),
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','LAT-LRG', current_date - 365, 10, 'Batch yield 10 lattes')
on conflict (org_id, sku, effective_start) do update set yield_qty=excluded.yield_qty;

-- Recipe items
with rv as (
  select id, sku
  from public.recipe_versions
  where org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568' and sku in ('ESP-SGL','LAT-LRG')
  order by effective_start desc
),
ing as (
  select ingredient_code, id, base_uom
  from public.ingredients
  where org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568'
)
insert into public.recipe_items(recipe_version_id, ingredient_id, qty, uom, loss_pct)
select rv.id,
       (select id from ing where ingredient_code='BEANS'),
       case when rv.sku='ESP-SGL' then 180 else 160 end,
       'g',
       0.02
from rv
on conflict (recipe_version_id, ingredient_id) do update set qty=excluded.qty, loss_pct=excluded.loss_pct;

-- Milk for latte
insert into public.recipe_items(recipe_version_id, ingredient_id, qty, uom, loss_pct)
select rv.id,
       (select id from public.ingredients where org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568' and ingredient_code='MILK'),
       2500, 'ml', 0.01
from public.recipe_versions rv
where rv.org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568' and rv.sku='LAT-LRG'
on conflict (recipe_version_id, ingredient_id) do update set qty=excluded.qty, loss_pct=excluded.loss_pct;

-- Packaging per unit: cup + lid for both SKUs
insert into public.product_packaging_items(org_id, sku, ingredient_id, qty, uom)
select '2f0c88c6-3de8-48aa-b39c-bb085d37a568', s.sku, i.id, 1, 'unit'
from (values ('ESP-SGL'),('LAT-LRG')) s(sku)
join public.ingredients i on i.org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568' and i.ingredient_code='CUP12'
on conflict (org_id, sku, ingredient_id) do update set qty=excluded.qty;

insert into public.product_packaging_items(org_id, sku, ingredient_id, qty, uom)
select '2f0c88c6-3de8-48aa-b39c-bb085d37a568', s.sku, i.id, 1, 'unit'
from (values ('ESP-SGL'),('LAT-LRG')) s(sku)
join public.ingredients i on i.org_id='2f0c88c6-3de8-48aa-b39c-bb085d37a568' and i.ingredient_code='LID'
on conflict (org_id, sku, ingredient_id) do update set qty=excluded.qty;

-- Labor
insert into public.labor_rates(org_id, role_code, effective_start, hourly_rate, burden_pct)
values ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','BARISTA', current_date - 365, 22.0, 0.25)
on conflict (org_id, role_code, effective_start) do update set hourly_rate=excluded.hourly_rate, burden_pct=excluded.burden_pct;

insert into public.product_labor_specs(org_id, sku, role_code, seconds_per_unit)
values
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','ESP-SGL','BARISTA', 35),
  ('2f0c88c6-3de8-48aa-b39c-bb085d37a568','LAT-LRG','BARISTA', 75)
on conflict (org_id, sku, role_code) do update set seconds_per_unit=excluded.seconds_per_unit;

commit;
