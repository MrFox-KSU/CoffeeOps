begin;

-- Deterministic: DB import contract is generated from:
-- 1) lib/import/requirements.ts (canonical keys + required + types)
-- 2) public/templates/*_template.csv (complete header sets)

drop function if exists public.get_import_contract(public.import_entity);
drop table if exists public.import_contract_fields cascade;

create table public.import_contract_fields (
  entity_type public.import_entity not null,
  canonical_key text not null,
  display_name text not null,
  data_type text not null check (data_type in ('text','number','date','boolean')),
  is_required boolean not null default false,
  ordinal int not null default 1000,
  primary key (entity_type, canonical_key)
);

alter table public.import_contract_fields enable row level security;
drop policy if exists import_contract_fields_read on public.import_contract_fields;
create policy import_contract_fields_read on public.import_contract_fields
for select to authenticated using (true);

create or replace function public.get_import_contract(p_entity public.import_entity)
returns table(canonical_key text, display_name text, data_type text, is_required boolean, ordinal int)
language sql stable as $$
  select canonical_key, display_name, data_type, is_required, ordinal
  from public.import_contract_fields
  where entity_type = p_entity
  order by ordinal asc;
$$;
revoke all on function public.get_import_contract(public.import_entity) from public;
grant execute on function public.get_import_contract(public.import_entity) to authenticated, service_role;

insert into public.import_contract_fields(entity_type, canonical_key, display_name, data_type, is_required, ordinal) values
('products', 'product_name', 'Product name', 'text', true, 10),
('products', 'sku', 'SKU', 'text', false, 20),
('products', 'category', 'Category', 'text', false, 30),
('products', 'unit_cost', 'Unit cost', 'number', false, 40),
('products', 'default_price', 'Default Price', 'text', false, 50),
('products', 'currency', 'Currency', 'text', false, 60),
('products', 'active', 'Active', 'text', false, 70),
('sales', 'invoice_date', 'Invoice date', 'date', true, 10),
('sales', 'invoice_number', 'Invoice number', 'text', true, 20),
('sales', 'product_name', 'Product / item name', 'text', true, 30),
('sales', 'quantity', 'Quantity', 'number', true, 40),
('sales', 'line_total', 'Line total', 'number', true, 50),
('sales', 'payment_method', 'Payment method', 'text', false, 60),
('sales', 'channel', 'Channel', 'text', false, 70),
('sales', 'branch', 'Branch', 'text', false, 80),
('sales', 'external_invoice_number', 'External Invoice Number', 'text', false, 90),
('sales', 'branch_code', 'Branch Code', 'text', false, 100),
('sales', 'invoice_type', 'Invoice Type', 'text', false, 110),
('sales', 'line_number', 'Line Number', 'text', false, 120),
('sales', 'sku', 'Sku', 'text', false, 130),
('sales', 'category', 'Category', 'text', false, 140),
('sales', 'unit_price', 'Unit Price', 'text', false, 150),
('sales', 'discount_rate', 'Discount Rate', 'text', false, 160),
('sales', 'net_sales', 'Net Sales', 'text', false, 170),
('sales', 'vat_rate', 'Vat Rate', 'text', false, 180),
('sales', 'tax_amount', 'Tax Amount', 'text', false, 190),
('sales', 'total_amount', 'Total Amount', 'text', false, 200),
('sales', 'currency', 'Currency', 'text', false, 210),
('expenses', 'expense_date', 'Expense date', 'date', true, 10),
('expenses', 'amount', 'Amount', 'number', true, 20),
('expenses', 'description', 'Description / vendor', 'text', true, 30),
('expenses', 'category', 'Category', 'text', false, 40),
('expenses', 'cost_center', 'Cost center', 'text', false, 50),
('expenses', 'reference_number', 'Reference number', 'text', false, 60),
('expenses', 'vendor', 'Vendor', 'text', false, 70),
('expenses', 'branch_code', 'Branch Code', 'text', false, 80),
('expenses', 'cost_center_code', 'Cost Center Code', 'text', false, 90),
('expenses', 'vat_rate', 'Vat Rate', 'text', false, 100),
('expenses', 'tax_amount', 'Tax Amount', 'text', false, 110),
('expenses', 'total_amount', 'Total Amount', 'text', false, 120),
('expenses', 'payment_method', 'Payment Method', 'text', false, 130),
('expenses', 'notes', 'Notes', 'text', false, 140),
('expenses', 'currency', 'Currency', 'text', false, 150),
('labor', 'shift_date', 'Shift date', 'date', true, 10),
('labor', 'employee_name', 'Employee name', 'text', true, 20),
('labor', 'hours', 'Hours', 'number', true, 30),
('labor', 'rate', 'Rate / wage', 'number', false, 40),
('labor', 'branch', 'Branch', 'text', false, 50),
('labor', 'work_date', 'Work Date', 'text', false, 60),
('labor', 'employee_id', 'Employee Id', 'text', false, 70),
('labor', 'role', 'Role', 'text', false, 80),
('labor', 'branch_code', 'Branch Code', 'text', false, 90),
('labor', 'hourly_rate', 'Hourly Rate', 'text', false, 100),
('labor', 'cost', 'Cost', 'text', false, 110),
('labor', 'currency', 'Currency', 'text', false, 120);

select pg_notify('pgrst', 'reload schema');
commit;
