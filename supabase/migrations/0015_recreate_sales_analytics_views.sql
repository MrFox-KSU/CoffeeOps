begin;

create schema if not exists analytics;

-- Drop dependents first (deterministic)
drop view if exists analytics.v_kpi_daily_sales;
drop view if exists analytics.v_sales_daily;
drop view if exists analytics.v_sales_line_financials;

-- Recreate from canonical tables
create view analytics.v_sales_line_financials as
select
  i.org_id,
  inv.invoice_date as day,
  inv.external_invoice_number,
  inv.invoice_type,
  inv.channel,
  inv.payment_method,
  inv.branch_id,
  i.line_number,
  i.sku,
  i.product_name,
  i.category,
  i.quantity,
  i.unit_price,
  i.discount_rate,
  i.net_sales,
  i.vat_rate,
  i.tax_amount,
  i.total_amount,
  coalesce(i.currency, inv.currency) as currency
from public.sales_items i
join public.sales_invoices inv
  on inv.id = i.invoice_id;

create view analytics.v_sales_daily as
select
  org_id,
  day,
  sum(net_sales) as net_sales,
  sum(tax_amount) as tax_amount,
  sum(total_amount) as total_amount,
  count(distinct external_invoice_number) as invoices
from analytics.v_sales_line_financials
group by org_id, day;

create view analytics.v_kpi_daily_sales as
select *
from analytics.v_sales_daily;

grant usage on schema analytics to authenticated;
grant select on all tables in schema analytics to authenticated;

select pg_notify('pgrst','reload schema');

commit;
