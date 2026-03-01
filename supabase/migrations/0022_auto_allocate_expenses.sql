begin;

-- Suggest allocations for an expense (deterministic rules)
create or replace function public.suggest_expense_allocations(p_expense_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  e public.expenses;
  cc text;
  parts text[];
  item text;
  out jsonb := '[]'::jsonb;
  n int;
  i int := 0;
  amt numeric;
  sum_amt numeric := 0;
  code text;
  pct numeric;
begin
  select * into e from public.expenses where id = p_expense_id;
  if not found then raise exception 'Expense not found'; end if;
  if not public.is_org_member(e.org_id) then raise exception 'Forbidden'; end if;

  cc := nullif(trim(coalesce(e.cost_center_code,'')), '');

  -- 1) If cost_center_code supplied, parse it:
  -- a) "OVERHEAD:60,COGS:40"
  -- b) "OVERHEAD,COGS" (split equal)
  if cc is not null then
    if position(':' in cc) > 0 then
      parts := string_to_array(cc, ',');
      n := array_length(parts,1);

      for item in select unnest(parts)
      loop
        i := i + 1;
        code := nullif(trim(split_part(item,':',1)),'');
        pct := nullif(trim(split_part(item,':',2)),'')::numeric;
        if code is null or pct is null then
          raise exception 'Invalid cost_center_code format: %', cc;
        end if;

        if i < n then
          amt := round(e.amount * (pct/100.0), 2);
          sum_amt := sum_amt + amt;
        else
          amt := round(e.amount - sum_amt, 2); -- remainder to last
        end if;

        out := out || jsonb_build_array(jsonb_build_object('cost_center_code', upper(code), 'amount', amt));
      end loop;

      return out;
    end if;

    if cc ~ '[,;|]' then
      cc := replace(replace(cc,'; ',','),';',',');
      cc := replace(cc,'|',',');
      parts := string_to_array(cc, ',');
      parts := array_remove(parts, '');
      n := array_length(parts,1);

      if n is null or n = 0 then
        cc := null;
      else
        for item in select unnest(parts)
        loop
          i := i + 1;
          code := upper(nullif(trim(item),''));
          if code is null then continue; end if;

          if i < n then
            amt := round(e.amount / n, 2);
            sum_amt := sum_amt + amt;
          else
            amt := round(e.amount - sum_amt, 2);
          end if;

          out := out || jsonb_build_array(jsonb_build_object('cost_center_code', code, 'amount', amt));
        end loop;

        return out;
      end if;
    end if;

    -- single code => 100%
    return jsonb_build_array(jsonb_build_object('cost_center_code', upper(cc), 'amount', round(e.amount,2)));
  end if;

  -- 2) Fallback heuristic by category (deterministic)
  if e.category ilike any(array['%coffee%','%bean%','%milk%','%dairy%','%packag%','%pastry%','%ingredients%']) then
    return jsonb_build_array(jsonb_build_object('cost_center_code','COGS','amount', round(e.amount,2)));
  end if;

  return jsonb_build_array(jsonb_build_object('cost_center_code','OVERHEAD','amount', round(e.amount,2)));
end $$;

revoke all on function public.suggest_expense_allocations(uuid) from public;
grant execute on function public.suggest_expense_allocations(uuid) to authenticated;

-- Auto-allocate one expense
create or replace function public.auto_allocate_expense(p_expense_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  alloc jsonb;
begin
  alloc := public.suggest_expense_allocations(p_expense_id);
  perform public.allocate_expense_to_cost_centers(p_expense_id, alloc);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.auto_allocate_expense(uuid) from public;
grant execute on function public.auto_allocate_expense(uuid) to authenticated;

-- Auto-allocate all unallocated expenses from a given import job (so user isn't overwhelmed)
create or replace function public.auto_allocate_expenses_for_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  cnt int := 0;
  ex_id uuid;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;

  if not public.is_org_member(v_job.org_id) then raise exception 'Forbidden'; end if;

  for ex_id in
    select e.id
    from public.expenses e
    where e.source_import_job_id = p_job_id
      and not exists (select 1 from public.expense_allocations a where a.expense_id = e.id)
  loop
    perform public.auto_allocate_expense(ex_id);
    cnt := cnt + 1;
  end loop;

  return jsonb_build_object('ok', true, 'auto_allocated', cnt);
end $$;

revoke all on function public.auto_allocate_expenses_for_job(uuid) from public;
grant execute on function public.auto_allocate_expenses_for_job(uuid) to authenticated;

-- Update dispatcher: after expenses import, auto-allocate expenses from that job
create or replace function public.start_import_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.import_jobs;
  v_result jsonb;
  v_auto jsonb;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;

  if v_job.entity_type='products' then
    return public.import_products_from_staging(p_job_id);
  elsif v_job.entity_type='sales' then
    return public.import_sales_from_staging(p_job_id);
  elsif v_job.entity_type='expenses' then
    v_result := public.import_expenses_from_staging(p_job_id);
    v_auto := public.auto_allocate_expenses_for_job(p_job_id);
    return v_result || jsonb_build_object('auto_allocation', v_auto);
  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end $$;

revoke all on function public.start_import_job(uuid) from public;
grant execute on function public.start_import_job(uuid) to authenticated;

select pg_notify('pgrst','reload schema');

commit;
