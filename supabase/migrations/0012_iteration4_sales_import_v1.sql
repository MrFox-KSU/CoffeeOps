-- Iteration 4: Sales import v1
-- - Canonical sales tables
-- - Importer from staging (import_sales_from_staging)
-- - Analytics views used by the UI

begin;



-- Helper: updated_at trigger function (deterministic, idempotent)
create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end $$;


-- 0) Helper normalizer for dimensions (channel/payment_method/invoice_type)
create or replace function public.norm_dim(p text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(lower(trim(p)), '[^a-z0-9]+', '_', 'g'), '');
$$;

-- 1) Branch code support (used by sales/expenses/labor imports)
alter table public.branches
  add column if not exists code text;

-- Default the default branch to MAIN if missing
update public.branches
set code = 'MAIN'
where is_default = true
  and (code is null or length(trim(code)) = 0);

-- Backfill remaining branch codes deterministically from name
update public.branches
set code = upper(regexp_replace(coalesce(name,''), '[^A-Za-z0-9]+', '-', 'g'))
where (code is null or length(trim(code)) = 0)
  and length(coalesce(name,'')) > 0;

-- Uniqueness per org (only when code present)
create unique index if not exists branches_org_id_code_uidx
  on public.branches(org_id, code)
  where code is not null;

-- 2) Canonical sales tables
create table if not exists public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,

  invoice_date date not null,
  external_invoice_number text not null,

  invoice_type text,
  channel text,
  payment_method text,
  currency text,

  source_import_job_id uuid references public.import_jobs(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(org_id, external_invoice_number)
);

create index if not exists sales_invoices_org_date_idx
  on public.sales_invoices(org_id, invoice_date desc);

create table if not exists public.sales_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  invoice_id uuid not null references public.sales_invoices(id) on delete cascade,

  line_number int not null check (line_number >= 1),

  sku text,
  product_name text not null,
  category text,

  quantity numeric not null default 1,
  unit_price numeric,
  discount_rate numeric,

  net_sales numeric not null,
  vat_rate numeric,
  tax_amount numeric,
  total_amount numeric,
  currency text,

  source_import_job_id uuid references public.import_jobs(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(invoice_id, line_number)
);

create index if not exists sales_items_invoice_id_idx
  on public.sales_items(invoice_id);

create index if not exists sales_items_org_id_idx
  on public.sales_items(org_id);

-- updated_at triggers
drop trigger if exists trg_sales_invoices_set_updated_at on public.sales_invoices;
create trigger trg_sales_invoices_set_updated_at
before update on public.sales_invoices
for each row execute function public.update_updated_at_column();

 drop trigger if exists trg_sales_items_set_updated_at on public.sales_items;
create trigger trg_sales_items_set_updated_at
before update on public.sales_items
for each row execute function public.update_updated_at_column();

-- 3) RLS (read for org members)
alter table public.sales_invoices enable row level security;
alter table public.sales_items enable row level security;

drop policy if exists sales_invoices_select_member on public.sales_invoices;
create policy sales_invoices_select_member
on public.sales_invoices
for select
using (public.is_org_member(org_id));

drop policy if exists sales_items_select_member on public.sales_items;
create policy sales_items_select_member
on public.sales_items
for select
using (public.is_org_member(org_id));

-- 4) Importer: from staging -> canonical sales tables
create or replace function public.import_sales_from_staging(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_job public.import_jobs;
  v_org_id uuid;
  v_valid_rows int;
  v_invoice_count int;
  v_line_count int;
begin
  select * into v_job
  from public.import_jobs
  where id = p_job_id;

  if not found then
    raise exception 'import job % not found', p_job_id;
  end if;

  if v_job.entity_type <> 'sales' then
    raise exception 'import_sales_from_staging only supports entity_type=sales (got %)', v_job.entity_type;
  end if;

  v_org_id := v_job.org_id;

  if not public.is_org_member(v_org_id) then
    raise exception 'not authorized for org %', v_org_id;
  end if;

  select count(*) into v_valid_rows
  from public.import_job_rows
  where job_id = p_job_id and is_valid = true;

  if v_valid_rows = 0 then
    return jsonb_build_object(
      'ok', true,
      'job_id', p_job_id,
      'org_id', v_org_id,
      'message', 'No valid staged rows to import.'
    );
  end if;

  -- 4.1) Ensure branch codes exist (best-effort)
  insert into public.branches(org_id, name, code)
  select
    v_org_id,
    upper(trim(b.branch_code)) as name,
    upper(trim(b.branch_code)) as code
  from (
    select distinct nullif(trim(r.parsed->>'branch_code'), '') as branch_code
    from public.import_job_rows r
    where r.job_id = p_job_id and r.is_valid = true
  ) b
  where b.branch_code is not null
  on conflict (org_id, code) do update
    set name = excluded.name;

  -- 4.2) Upsert invoices (dedupe by org_id + external_invoice_number)
  with invoice_src as (
    select
      v_org_id as org_id,
      coalesce(
        nullif(trim(r.parsed->>'external_invoice_number'), ''),
        nullif(trim(r.parsed->>'invoice_number'), '')
      ) as external_invoice_number,
      nullif(trim(r.parsed->>'invoice_date'), '')::date as invoice_date,
      public.norm_dim(r.parsed->>'invoice_type') as invoice_type,
      public.norm_dim(r.parsed->>'channel') as channel,
      public.norm_dim(r.parsed->>'payment_method') as payment_method,
      upper(nullif(trim(r.parsed->>'currency'), '')) as currency,
      upper(nullif(trim(r.parsed->>'branch_code'), '')) as branch_code
    from public.import_job_rows r
    where r.job_id = p_job_id and r.is_valid = true
  ), invoice_agg as (
    select
      org_id,
      external_invoice_number,
      min(invoice_date) as invoice_date,
      max(invoice_type) as invoice_type,
      max(channel) as channel,
      max(payment_method) as payment_method,
      max(currency) as currency,
      max(branch_code) as branch_code
    from invoice_src
    where external_invoice_number is not null and invoice_date is not null
    group by org_id, external_invoice_number
  ), upsert as (
    insert into public.sales_invoices(
      org_id,
      branch_id,
      invoice_date,
      external_invoice_number,
      invoice_type,
      channel,
      payment_method,
      currency,
      source_import_job_id
    )
    select
      ia.org_id,
      coalesce(
        b.id,
        (select id from public.branches where org_id = ia.org_id and is_default = true limit 1)
      ) as branch_id,
      ia.invoice_date,
      ia.external_invoice_number,
      ia.invoice_type,
      ia.channel,
      ia.payment_method,
      ia.currency,
      p_job_id
    from invoice_agg ia
    left join public.branches b
      on b.org_id = ia.org_id and b.code = ia.branch_code
    on conflict (org_id, external_invoice_number) do update set
      branch_id = excluded.branch_id,
      invoice_date = excluded.invoice_date,
      invoice_type = excluded.invoice_type,
      channel = excluded.channel,
      payment_method = excluded.payment_method,
      currency = excluded.currency,
      source_import_job_id = excluded.source_import_job_id,
      updated_at = now()
    returning 1
  )
  select count(*) into v_invoice_count from upsert;

  -- 4.3) Upsert line items (dedupe by invoice_id + line_number)
  with inv as (
    select id as invoice_id, org_id, external_invoice_number, currency
    from public.sales_invoices
    where org_id = v_org_id
      and external_invoice_number in (
        select distinct coalesce(
          nullif(trim(r.parsed->>'external_invoice_number'), ''),
          nullif(trim(r.parsed->>'invoice_number'), '')
        )
        from public.import_job_rows r
        where r.job_id = p_job_id and r.is_valid = true
      )
  ), lines_src as (
    select
      inv.org_id,
      inv.invoice_id,
      coalesce(nullif(trim(r.parsed->>'line_number'), ''), r.row_number::text)::int as line_number,
      nullif(trim(r.parsed->>'sku'), '') as sku,
      coalesce(nullif(trim(r.parsed->>'product_name'), ''), nullif(trim(r.parsed->>'name'), ''), 'Unknown') as product_name,
      nullif(trim(r.parsed->>'category'), '') as category,
      coalesce(nullif(trim(r.parsed->>'quantity'), ''), '1')::numeric as quantity,
      nullif(trim(r.parsed->>'unit_price'), '')::numeric as unit_price,
      nullif(trim(r.parsed->>'discount_rate'), '')::numeric as discount_rate,
      coalesce(
        nullif(trim(r.parsed->>'net_sales'), ''),
        nullif(trim(r.parsed->>'line_total'), ''),
        nullif(trim(r.parsed->>'total_amount'), '')
      )::numeric as net_sales,
      nullif(trim(r.parsed->>'vat_rate'), '')::numeric as vat_rate,
      nullif(trim(r.parsed->>'tax_amount'), '')::numeric as tax_amount,
      nullif(trim(r.parsed->>'total_amount'), '')::numeric as total_amount,
      coalesce(upper(nullif(trim(r.parsed->>'currency'), '')), inv.currency) as currency
    from public.import_job_rows r
    join inv
      on inv.external_invoice_number = coalesce(
        nullif(trim(r.parsed->>'external_invoice_number'), ''),
        nullif(trim(r.parsed->>'invoice_number'), '')
      )
    where r.job_id = p_job_id and r.is_valid = true
  ), upsert as (
    insert into public.sales_items(
      org_id,
      invoice_id,
      line_number,
      sku,
      product_name,
      category,
      quantity,
      unit_price,
      discount_rate,
      net_sales,
      vat_rate,
      tax_amount,
      total_amount,
      currency,
      source_import_job_id
    )
    select
      org_id,
      invoice_id,
      line_number,
      sku,
      product_name,
      category,
      quantity,
      unit_price,
      discount_rate,
      net_sales,
      vat_rate,
      tax_amount,
      total_amount,
      currency,
      p_job_id
    from lines_src
    where net_sales is not null
    on conflict (invoice_id, line_number) do update set
      sku = excluded.sku,
      product_name = excluded.product_name,
      category = excluded.category,
      quantity = excluded.quantity,
      unit_price = excluded.unit_price,
      discount_rate = excluded.discount_rate,
      net_sales = excluded.net_sales,
      vat_rate = excluded.vat_rate,
      tax_amount = excluded.tax_amount,
      total_amount = excluded.total_amount,
      currency = excluded.currency,
      source_import_job_id = excluded.source_import_job_id,
      updated_at = now()
    returning 1
  )
  select count(*) into v_line_count from upsert;

  return jsonb_build_object(
    'ok', true,
    'job_id', p_job_id,
    'org_id', v_org_id,
    'valid_rows', v_valid_rows,
    'invoices_upserted', v_invoice_count,
    'lines_upserted', v_line_count
  );
end;
$$;

revoke all on function public.import_sales_from_staging(uuid) from public;
grant execute on function public.import_sales_from_staging(uuid) to authenticated;

-- 5) Update dispatcher: start_import_job now supports sales + products
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_job public.import_jobs;
  v_result jsonb;
begin
  select * into v_job
  from public.import_jobs
  where id = p_job_id;

  if not found then
    raise exception 'import job % not found', p_job_id;
  end if;

  if not public.is_org_member(v_job.org_id) then
    raise exception 'not authorized for org %', v_job.org_id;
  end if;

  if v_job.status not in ('validated','imported') then
    raise exception 'job % must be validated or imported to start import (status=%)', p_job_id, v_job.status;
  end if;

  case v_job.entity_type
    when 'products' then
      v_result := public.import_products_from_staging(p_job_id);
    when 'sales' then
      v_result := public.import_sales_from_staging(p_job_id);
    else
      raise exception 'entity_type % is not supported for import yet', v_job.entity_type;
  end case;

  update public.import_jobs
  set
    status = 'imported',
    summary = coalesce(summary,'{}'::jsonb) || jsonb_build_object(
      'imported_at', now(),
      'import_result', v_result
    )
  where id = p_job_id;

  return jsonb_build_object(
    'ok', true,
    'job_id', p_job_id,
    'entity_type', v_job.entity_type,
    'status', 'imported',
    'result', v_result
  );
end;
$$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

-- 6) Analytics views (stable names used by UI)
create schema if not exists analytics;

drop view if exists analytics.v_sales_line_financials;
create view analytics.v_sales_line_financials as
select
  i.org_id,
  i.id as invoice_id,
  i.invoice_date,
  i.external_invoice_number,
  i.invoice_type,
  i.channel,
  i.payment_method,
  i.currency as invoice_currency,

  b.id as branch_id,
  b.name as branch_name,
  b.code as branch_code,

  si.id as line_id,
  si.line_number,
  si.sku,
  si.product_name,
  si.category,
  si.quantity,
  si.unit_price,
  si.discount_rate,
  si.net_sales,
  si.vat_rate,
  si.tax_amount,
  si.total_amount,
  coalesce(si.currency, i.currency) as currency,
  si.created_at,
  si.updated_at
from public.sales_items si
join public.sales_invoices i on i.id = si.invoice_id
left join public.branches b on b.id = i.branch_id
where public.is_org_member(i.org_id);

-- Daily rollup

drop view if exists analytics.v_sales_daily;
create view analytics.v_sales_daily as
select
  i.org_id,
  i.invoice_date as day,
  sum(si.net_sales) as net_sales,
  sum(coalesce(si.tax_amount, 0)) as tax_amount,
  sum(coalesce(si.total_amount, si.net_sales + coalesce(si.tax_amount, 0))) as total_amount,
  count(distinct i.id) as invoice_count,
  sum(coalesce(si.quantity, 0)) as units_sold
from public.sales_items si
join public.sales_invoices i on i.id = si.invoice_id
where public.is_org_member(i.org_id)
group by i.org_id, i.invoice_date;

-- KPI rollup

drop view if exists analytics.v_kpi_daily_sales;
create view analytics.v_kpi_daily_sales as
select
  org_id,
  day,
  net_sales,
  tax_amount,
  total_amount,
  invoice_count,
  units_sold,
  case when invoice_count > 0 then net_sales / invoice_count else 0 end as avg_ticket
from analytics.v_sales_daily;

-- Grants
grant usage on schema analytics to authenticated;

grant select on analytics.v_sales_line_financials to authenticated;
grant select on analytics.v_sales_daily to authenticated;
grant select on analytics.v_kpi_daily_sales to authenticated;

-- Force PostgREST schema cache reload
select pg_notify('pgrst', 'reload schema');

commit;
