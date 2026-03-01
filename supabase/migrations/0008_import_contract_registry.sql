begin;

-- Contract registry: single source of truth for canonical fields used by UI + validators + templates
create table if not exists public.import_contract_fields (
  entity_type public.import_entity not null,
  canonical_key text not null,
  display_name text not null,
  data_type text not null check (data_type in ('text','number','date','boolean')),
  is_required boolean not null default false,
  example text,
  ordinal int not null default 1000,
  aliases text[] not null default '{}'::text[],
  primary key (entity_type, canonical_key)
);

comment on table public.import_contract_fields is
'Canonical import contract (source of truth). UI mapping keys, Edge Function validation, and templates must align to this table.';

alter table public.import_contract_fields enable row level security;

-- Readable by authenticated users (contract is global, not org-specific)
drop policy if exists import_contract_fields_read on public.import_contract_fields;
create policy import_contract_fields_read
on public.import_contract_fields
for select
to authenticated
using (true);

-- RPC: fetch contract rows in stable order
create or replace function public.get_import_contract(p_entity public.import_entity)
returns table (
  entity_type public.import_entity,
  canonical_key text,
  display_name text,
  data_type text,
  is_required boolean,
  example text,
  ordinal int,
  aliases text[]
)
language sql
stable
as $$
  select
    entity_type, canonical_key, display_name, data_type, is_required, example, ordinal, aliases
  from public.import_contract_fields
  where entity_type = p_entity
  order by ordinal asc, canonical_key asc;
$$;

revoke all on function public.get_import_contract(public.import_entity) from public;
grant execute on function public.get_import_contract(public.import_entity) to authenticated, service_role;

-- Seed contract (idempotent upsert). This MUST match your frontend canonical keys.
-- PRODUCTS (canonical: sku + product_name)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal, example, aliases)
values
('products','sku','SKU','text',true,10,'ESP-SGL', ARRAY[]::text[]),
('products','product_name','Product name','text',true,20,'Single Espresso', ARRAY['name']),
('products','category','Category','text',false,30,'Espresso', ARRAY[]::text[]),
('products','default_price','Default price','number',false,40,'21.67', ARRAY[]::text[]),
('products','unit_cost','Unit cost','number',false,50,'5.20', ARRAY[]::text[]),
('products','currency','Currency','text',false,60,'SAR', ARRAY[]::text[]),
('products','active','Active','boolean',false,70,'TRUE', ARRAY[]::text[])
on conflict (entity_type, canonical_key) do update
set display_name=excluded.display_name,
    data_type=excluded.data_type,
    is_required=excluded.is_required,
    ordinal=excluded.ordinal,
    example=excluded.example,
    aliases=excluded.aliases;

-- SALES LINES (canonical required: invoice_date, external_invoice_number, net_sales)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal, example, aliases)
values
('sales','invoice_date','Invoice date','date',true,10,'2025-01-15', ARRAY['date']),
('sales','external_invoice_number','Invoice number','text',true,20,'3SC-DTN-20250115-0001', ARRAY['invoice_no','invoice','inv_no']),
('sales','net_sales','Net sales','number',true,30,'21.67', ARRAY['net','amount','subtotal']),
('sales','branch_code','Branch code','text',false,40,'3SC-DTN', ARRAY['branch']),
('sales','invoice_type','Invoice type','text',false,50,'sale', ARRAY[]::text[]),
('sales','channel','Channel','text',false,60,'in_store', ARRAY[]::text[]),
('sales','payment_method','Payment method','text',false,70,'card', ARRAY[]::text[]),
('sales','line_number','Line number','number',false,80,'1', ARRAY[]::text[]),
('sales','sku','SKU','text',false,90,'ESP-SGL', ARRAY[]::text[]),
('sales','product_name','Product name','text',false,100,'Single Espresso', ARRAY['name']),
('sales','category','Category','text',false,110,'Espresso', ARRAY[]::text[]),
('sales','quantity','Quantity','number',false,120,'1', ARRAY[]::text[]),
('sales','unit_price','Unit price','number',false,130,'21.67', ARRAY[]::text[]),
('sales','discount_rate','Discount rate','number',false,140,'0.00', ARRAY[]::text[]),
('sales','vat_rate','VAT rate','number',false,150,'0.15', ARRAY[]::text[]),
('sales','tax_amount','Tax amount','number',false,160,'3.25', ARRAY[]::text[]),
('sales','total_amount','Total amount','number',false,170,'24.92', ARRAY[]::text[]),
('sales','currency','Currency','text',false,180,'SAR', ARRAY[]::text[])
on conflict (entity_type, canonical_key) do update
set display_name=excluded.display_name,
    data_type=excluded.data_type,
    is_required=excluded.is_required,
    ordinal=excluded.ordinal,
    example=excluded.example,
    aliases=excluded.aliases;

-- EXPENSES (canonical required: expense_date, amount, category)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal, example, aliases)
values
('expenses','expense_date','Expense date','date',true,10,'2025-01-31', ARRAY['date']),
('expenses','amount','Amount','number',true,20,'1200.00', ARRAY['net','subtotal']),
('expenses','category','Category','text',true,30,'Utilities', ARRAY[]::text[]),
('expenses','reference_number','Reference number','text',false,40,'EXP-20250131-00001', ARRAY['ref','reference']),
('expenses','vendor','Vendor','text',false,50,'Saudi Electricity Co', ARRAY['supplier']),
('expenses','branch_code','Branch code','text',false,60,'3SC-DTN', ARRAY['branch']),
('expenses','cost_center_code','Cost center','text',false,70,'OVERHEAD', ARRAY['cost_center']),
('expenses','vat_rate','VAT rate','number',false,80,'0.15', ARRAY[]::text[]),
('expenses','tax_amount','Tax amount','number',false,90,'180.00', ARRAY[]::text[]),
('expenses','total_amount','Total amount','number',false,100,'1380.00', ARRAY[]::text[]),
('expenses','payment_method','Payment method','text',false,110,'bank_transfer', ARRAY[]::text[]),
('expenses','notes','Notes','text',false,120,'Monthly electricity bill', ARRAY['note']),
('expenses','currency','Currency','text',false,130,'SAR', ARRAY[]::text[])
on conflict (entity_type, canonical_key) do update
set display_name=excluded.display_name,
    data_type=excluded.data_type,
    is_required=excluded.is_required,
    ordinal=excluded.ordinal,
    example=excluded.example,
    aliases=excluded.aliases;

-- LABOR (canonical required: work_date, hours, cost)
insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal, example, aliases)
values
('labor','work_date','Work date','date',true,10,'2025-01-15', ARRAY['date']),
('labor','hours','Hours','number',true,20,'7.50', ARRAY[]::text[]),
('labor','cost','Cost','number',true,30,'165.00', ARRAY['amount']),
('labor','employee_id','Employee ID','text',false,40,'3SC-DTN-E001', ARRAY[]::text[]),
('labor','employee_name','Employee name','text',false,50,'Employee 001', ARRAY['name']),
('labor','role','Role','text',false,60,'Barista', ARRAY[]::text[]),
('labor','branch_code','Branch code','text',false,70,'3SC-DTN', ARRAY['branch']),
('labor','hourly_rate','Hourly rate','number',false,80,'22.00', ARRAY[]::text[]),
('labor','currency','Currency','text',false,90,'SAR', ARRAY[]::text[])
on conflict (entity_type, canonical_key) do update
set display_name=excluded.display_name,
    data_type=excluded.data_type,
    is_required=excluded.is_required,
    ordinal=excluded.ordinal,
    example=excluded.example,
    aliases=excluded.aliases;

-- Force PostgREST schema cache reload
select pg_notify('pgrst', 'reload schema');

commit;
