begin;

-- Fix: avoid PL/pgSQL variable name conflicts with column names (sku/day etc.)
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
  if not found then
    raise exception 'Job not found';
  end if;

  if v_job.entity_type <> 'sales' then
    raise exception 'Only sales jobs supported';
  end if;

  v_org := v_job.org_id;

  if not public.is_org_member(v_org) then
    raise exception 'Forbidden';
  end if;

  -- Ensure settings row exists
  insert into public.org_cost_engine_settings(org_id)
  values (v_org)
  on conflict (org_id) do nothing;

  -- Days affected by this job (invoices imported by this job)
  for v_day in
    select distinct invoice_date
    from public.sales_invoices
    where org_id = v_org
      and source_import_job_id = p_job_id
  loop
    v_days_recomputed := v_days_recomputed + 1;

    -- Compute unit economics per (day, sku)
    for v_sku in
      select distinct si.sku
      from public.sales_items si
      join public.sales_invoices inv on inv.id = si.invoice_id
      where si.org_id = v_org
        and inv.invoice_date = v_day
        and si.sku is not null
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

    -- Lines without sku: deterministic missing marker
    update public.sales_items si
    set
      cogs_material = 0,
      cogs_packaging = 0,
      cogs_labor = 0,
      cogs_model = 'wac30_missing_sku_v1',
      cogs_status = 'missing_inputs',
      cogs_missing = jsonb_build_array('missing_sku')
    from public.sales_invoices inv
    where inv.id = si.invoice_id
      and si.org_id = v_org
      and inv.invoice_date = v_day
      and si.sku is null;

    -- Overhead allocation for the day (OVERHEAD + UNALLOCATED)
    overhead_amt := public.overhead_daily(v_org, v_day);

    select coalesce(sum(si.net_sales),0) into day_net
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = v_org
      and inv.invoice_date = v_day;

    if day_net <> 0 then
      update public.sales_items si
      set
        cogs_overhead = round(overhead_amt * (si.net_sales / day_net), 4),
        cogs_total = round(si.cogs_material + si.cogs_packaging + si.cogs_labor + (overhead_amt * (si.net_sales / day_net)), 4)
      from public.sales_invoices inv
      where inv.id = si.invoice_id
        and si.org_id = v_org
        and inv.invoice_date = v_day;
    else
      update public.sales_items si
      set
        cogs_overhead = 0,
        cogs_total = round(si.cogs_material + si.cogs_packaging + si.cogs_labor, 4),
        cogs_status = case when si.cogs_status='ok' then 'missing_inputs' else si.cogs_status end,
        cogs_missing = (coalesce(si.cogs_missing,'[]'::jsonb) || jsonb_build_array('overhead_unallocatable_day'))
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

select pg_notify('pgrst','reload schema');

commit;
