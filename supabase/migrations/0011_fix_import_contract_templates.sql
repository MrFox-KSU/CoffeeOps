-- Iteration 4 prerequisite: Make the import contract deterministic + aligned with the CSV templates.
-- Source of truth: /public/templates/*.csv header rows.

begin;

-- Ensure contract table exists with expected shape (idempotent)
create table if not exists public.import_contract_fields (
  entity_type   public.import_entity not null,
  canonical_key text                not null,
  display_name  text                not null,
  data_type     text                not null,
  is_required   boolean             not null default false,
  ordinal       int                 not null default 1000,
  primary key (entity_type, canonical_key)
);

alter table public.import_contract_fields
  add column if not exists display_name text,
  add column if not exists data_type text,
  add column if not exists is_required boolean not null default false,
  add column if not exists ordinal int not null default 1000;

-- Backfill any nullable columns (older migrations)
update public.import_contract_fields set display_name = canonical_key where display_name is null;
update public.import_contract_fields set data_type = 'text' where data_type is null;

-- Replace contract deterministically
truncate table public.import_contract_fields;

-- SALES (matches public/templates/sales_lines_template.csv)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal) values
  ('sales','invoice_date','Invoice date','date',true,10),
  ('sales','external_invoice_number','Invoice number','text',true,20),
  ('sales','branch_code','Branch code','text',false,30),
  ('sales','invoice_type','Invoice type','text',false,40),
  ('sales','channel','Channel','text',false,50),
  ('sales','payment_method','Payment method','text',false,60),
  ('sales','line_number','Line number','number',false,70),
  ('sales','sku','SKU','text',false,80),
  ('sales','product_name','Product name','text',true,90),
  ('sales','category','Category','text',false,100),
  ('sales','quantity','Quantity','number',true,110),
  ('sales','unit_price','Unit price','number',false,120),
  ('sales','discount_rate','Discount rate','number',false,130),
  ('sales','net_sales','Net sales','number',true,140),
  ('sales','vat_rate','VAT rate','number',false,150),
  ('sales','tax_amount','Tax amount','number',false,160),
  ('sales','total_amount','Total amount','number',false,170),
  ('sales','currency','Currency','text',false,180);

-- PRODUCTS (matches public/templates/products_template.csv)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal) values
  ('products','sku','SKU','text',true,10),
  ('products','product_name','Product name','text',true,20),
  ('products','category','Category','text',false,30),
  ('products','default_price','Default price','number',false,40),
  ('products','unit_cost','Unit cost','number',false,50),
  ('products','currency','Currency','text',false,60),
  ('products','active','Active','boolean',false,70);

-- EXPENSES (matches public/templates/expenses_template.csv)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal) values
  ('expenses','expense_date','Expense date','date',true,10),
  ('expenses','reference_number','Reference #','text',false,20),
  ('expenses','vendor','Vendor','text',false,30),
  ('expenses','branch_code','Branch code','text',false,40),
  ('expenses','cost_center_code','Cost center code','text',false,50),
  ('expenses','category','Category','text',true,60),
  ('expenses','amount','Amount','number',true,70),
  ('expenses','vat_rate','VAT rate','number',false,80),
  ('expenses','tax_amount','Tax amount','number',false,90),
  ('expenses','total_amount','Total amount','number',false,100),
  ('expenses','payment_method','Payment method','text',false,110),
  ('expenses','notes','Notes','text',false,120),
  ('expenses','currency','Currency','text',false,130);

-- LABOR (matches public/templates/labor_template.csv)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal) values
  ('labor','work_date','Work date','date',true,10),
  ('labor','employee_id','Employee ID','text',false,20),
  ('labor','employee_name','Employee name','text',false,30),
  ('labor','role','Role','text',false,40),
  ('labor','branch_code','Branch code','text',false,50),
  ('labor','hours','Hours','number',true,60),
  ('labor','hourly_rate','Hourly rate','number',false,70),
  ('labor','cost','Cost','number',true,80),
  ('labor','currency','Currency','text',false,90);

-- RPC used by the Edge Function + UI to fetch the canonical contract.
create or replace function public.get_import_contract(p_entity public.import_entity)
returns table(canonical_key text, display_name text, data_type text, is_required boolean, ordinal int)
language sql
stable
as $$
  select canonical_key, display_name, data_type, is_required, ordinal
  from public.import_contract_fields
  where entity_type = p_entity
  order by is_required desc, ordinal asc, canonical_key asc;
$$;

revoke all on function public.get_import_contract(public.import_entity) from public;
grant execute on function public.get_import_contract(public.import_entity) to authenticated, service_role;

-- Force PostgREST schema cache reload
select pg_notify('pgrst', 'reload schema');

commit;
