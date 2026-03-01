begin;

-- Ensure branches has code column
alter table public.branches
  add column if not exists code text;

-- 1) branches: unique(org_id, code) required for ON CONFLICT (org_id, code)
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.branches'::regclass
      and c.contype = 'u'
      and position('(org_id, code)' in pg_get_constraintdef(c.oid)) > 0
  ) then
    alter table public.branches
      add constraint branches_org_id_code_key unique (org_id, code);
  end if;
end $$;

-- 2) sales_invoices: unique(org_id, external_invoice_number)
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.sales_invoices'::regclass
      and c.contype = 'u'
      and position('(org_id, external_invoice_number)' in pg_get_constraintdef(c.oid)) > 0
  ) then
    alter table public.sales_invoices
      add constraint sales_invoices_org_external_invoice_number_key
      unique (org_id, external_invoice_number);
  end if;
end $$;

-- 3) sales_items: unique(invoice_id, line_number)
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.sales_items'::regclass
      and c.contype = 'u'
      and position('(invoice_id, line_number)' in pg_get_constraintdef(c.oid)) > 0
  ) then
    alter table public.sales_items
      add constraint sales_items_invoice_line_number_key
      unique (invoice_id, line_number);
  end if;
end $$;

select pg_notify('pgrst', 'reload schema');

commit;
