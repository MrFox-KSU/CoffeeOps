begin;

-- 1) Canonical products table (aligned to frontend contract keys)
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,

  sku text not null,
  product_name text not null,
  category text null,

  default_price numeric null,
  unit_cost numeric null,

  currency text null,
  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (org_id, sku)
);

create index if not exists products_org_id_idx on public.products(org_id);

-- updated_at trigger (if you have a helper, use it; else inline)
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_products_set_updated_at on public.products;
create trigger trg_products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

-- RLS: users can read products of orgs they belong to
alter table public.products enable row level security;

drop policy if exists products_select_member on public.products;
create policy products_select_member
on public.products
for select
to authenticated
using (
  exists (
    select 1
    from public.org_members m
    where m.org_id = products.org_id
      and m.user_id = auth.uid()
  )
);

-- 2) Importer: products from staging -> canonical
create or replace function public.import_products_from_staging(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_bad_count int;
  v_rows int;
  v_user uuid;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_job
  from public.import_jobs
  where id = p_job_id;

  if not found then
    raise exception 'Job not found';
  end if;

  if v_job.entity_type <> 'products' then
    raise exception 'import_products_from_staging only supports entity_type=products';
  end if;

  -- membership check
  if not exists (
    select 1 from public.org_members m
    where m.org_id = v_job.org_id
      and m.user_id = v_user
  ) then
    raise exception 'Forbidden: not a member of this org';
  end if;

  -- only allow validated jobs
  if v_job.status <> 'validated' then
    raise exception 'Job must be validated before import (status=%)', v_job.status;
  end if;

  select count(*) into v_bad_count
  from public.import_job_rows
  where job_id = p_job_id
    and is_valid = false;

  if v_bad_count > 0 then
    raise exception 'Cannot import: % invalid staged rows', v_bad_count;
  end if;

  -- Upsert products from parsed JSON (frontend contract keys)
  insert into public.products (
    org_id, sku, product_name, category, default_price, unit_cost, currency, active
  )
  select
    v_job.org_id,
    (r.parsed->>'sku')::text,
    (r.parsed->>'product_name')::text,
    nullif((r.parsed->>'category')::text, ''),
    nullif(r.parsed->>'default_price','')::numeric,
    nullif(r.parsed->>'unit_cost','')::numeric,
    nullif((r.parsed->>'currency')::text,''),
    coalesce(nullif(r.parsed->>'active','')::boolean, true)
  from public.import_job_rows r
  where r.job_id = p_job_id
  on conflict (org_id, sku) do update set
    product_name = excluded.product_name,
    category = excluded.category,
    default_price = excluded.default_price,
    unit_cost = excluded.unit_cost,
    currency = excluded.currency,
    active = excluded.active,
    updated_at = now();

  get diagnostics v_rows = row_count;

  update public.import_jobs
  set status = 'imported',
      summary = jsonb_set(coalesce(summary,'{}'::jsonb), '{imported_rows}', to_jsonb(v_rows), true),
      updated_at = now()
  where id = p_job_id;

  return jsonb_build_object(
    'ok', true,
    'entity_type', v_job.entity_type,
    'imported_rows', v_rows
  );
end $$;

revoke all on function public.import_products_from_staging(uuid) from public;
grant execute on function public.import_products_from_staging(uuid) to authenticated;

-- 3) Dispatcher RPC: Import button can call one function regardless of entity
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
begin
  select * into v_job from public.import_jobs where id = p_job_id;
  if not found then
    raise exception 'Job not found';
  end if;

  if v_job.entity_type = 'products' then
    return public.import_products_from_staging(p_job_id);
  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end $$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
