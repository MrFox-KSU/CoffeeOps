


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "auth";


ALTER SCHEMA "auth" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "postgres";


CREATE TYPE "auth"."aal_level" AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."code_challenge_method" AS ENUM (
    's256',
    'plain'
);


ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_status" AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_type" AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_authorization_status" AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE "auth"."oauth_authorization_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_client_type" AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE "auth"."oauth_client_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_registration_type" AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE "auth"."oauth_registration_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_response_type" AS ENUM (
    'code'
);


ALTER TYPE "auth"."oauth_response_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."one_time_token_type" AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE "auth"."one_time_token_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "public"."import_entity" AS ENUM (
    'sales',
    'expenses',
    'products',
    'labor',
    'unknown'
);


ALTER TYPE "public"."import_entity" OWNER TO "postgres";


CREATE TYPE "public"."import_job_status" AS ENUM (
    'uploaded',
    'parsed',
    'validated',
    'imported',
    'failed'
);


ALTER TYPE "public"."import_job_status" OWNER TO "postgres";


CREATE TYPE "public"."org_role" AS ENUM (
    'super_admin',
    'admin',
    'analyst',
    'viewer'
);


ALTER TYPE "public"."org_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "auth"."email"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION "auth"."email"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."email"() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';



CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION "auth"."jwt"() OWNER TO "supabase_auth_admin";


CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION "auth"."role"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."role"() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';



CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION "auth"."uid"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."uid"() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';



CREATE OR REPLACE FUNCTION "public"."allocate_expense_to_cost_centers"("p_expense_id" "uuid", "p_allocations" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_exp public.expenses;
  v_sum numeric := 0;
  v_item jsonb;
  v_code text;
  v_amount numeric;
  v_prev jsonb;
begin
  select * into v_exp from public.expenses where id=p_expense_id;
  if not found then raise exception 'Expense not found'; end if;

  if not public.is_org_member(v_exp.org_id) then
    raise exception 'Forbidden';
  end if;

  if jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'allocations must be a JSON array';
  end if;

  -- validate + sum
  for v_item in select * from jsonb_array_elements(p_allocations)
  loop
    v_code := nullif(trim(v_item->>'cost_center_code'),'');
    if v_code is null then raise exception 'Missing cost_center_code'; end if;
    v_amount := (v_item->>'amount')::numeric;
    if v_amount is null then raise exception 'Invalid amount for %', v_code; end if;
    if v_amount < 0 then raise exception 'Negative amount not allowed'; end if;
    v_sum := v_sum + v_amount;
  end loop;

  if abs(v_sum - v_exp.amount) > 0.01 then
    raise exception 'Allocation sum % must equal expense amount %', v_sum, v_exp.amount;
  end if;

  -- capture previous
  select coalesce(
    jsonb_agg(jsonb_build_object('cost_center_code', cost_center_code, 'amount', amount) order by cost_center_code),
    '[]'::jsonb
  ) into v_prev
  from public.expense_allocations
  where expense_id=p_expense_id;

  -- replace allocations
  delete from public.expense_allocations where expense_id=p_expense_id;

  insert into public.expense_allocations(expense_id, org_id, cost_center_code, amount, created_by)
  select
    p_expense_id,
    v_exp.org_id,
    nullif(trim(x->>'cost_center_code'), ''),
    (x->>'amount')::numeric,
    auth.uid()
  from jsonb_array_elements(p_allocations) x;

  insert into public.expense_allocation_audit(expense_id, org_id, changed_by, previous_allocations, new_allocations)
  values(p_expense_id, v_exp.org_id, auth.uid(), v_prev, p_allocations);

  return jsonb_build_object('ok', true, 'allocated_amount', v_sum);
end $$;


ALTER FUNCTION "public"."allocate_expense_to_cost_centers"("p_expense_id" "uuid", "p_allocations" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_unit_economics_to_sales_job"("p_job_id" "uuid", "p_wac_days" integer DEFAULT 30) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
  if not found then raise exception 'Job not found'; end if;
  if v_job.entity_type <> 'sales' then raise exception 'Only sales jobs supported'; end if;

  v_org := v_job.org_id;
  if not public.is_org_member(v_org) then raise exception 'Forbidden'; end if;

  insert into public.org_cost_engine_settings(org_id)
  values (v_org)
  on conflict (org_id) do nothing;

  for v_day in
    select distinct invoice_date
    from public.sales_invoices
    where org_id = v_org and source_import_job_id = p_job_id
  loop
    v_days_recomputed := v_days_recomputed + 1;

    for v_sku in
      select distinct si.sku
      from public.sales_items si
      join public.sales_invoices inv on inv.id = si.invoice_id
      where si.org_id = v_org and inv.invoice_date = v_day and si.sku is not null
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

    -- Overhead allocation (OVERHEAD + UNALLOCATED already handled inside overhead_daily())
    overhead_amt := public.overhead_daily(v_org, v_day);

    select coalesce(sum(si.net_sales),0) into day_net
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = v_org and inv.invoice_date = v_day;

    if day_net <> 0 then
      update public.sales_items si
      set
        cogs_overhead = round(overhead_amt * (si.net_sales / day_net), 4),
        cogs_total = round(si.cogs_material + si.cogs_packaging + si.cogs_labor + (overhead_amt * (si.net_sales / day_net)), 4)
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


ALTER FUNCTION "public"."apply_unit_economics_to_sales_job"("p_job_id" "uuid", "p_wac_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_allocate_expense"("p_expense_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  alloc jsonb;
begin
  alloc := public.suggest_expense_allocations(p_expense_id);
  perform public.allocate_expense_to_cost_centers(p_expense_id, alloc);
  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION "public"."auto_allocate_expense"("p_expense_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_allocate_expenses_for_job"("p_job_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."auto_allocate_expenses_for_job"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."compute_unit_cogs"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date", "p_wac_days" integer DEFAULT 30) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  w int := greatest(1, least(p_wac_days, 365));
  rv_id uuid;
  yield_qty numeric;
  mat_batch numeric := 0;
  mat_unit numeric := 0;
  pack_unit numeric := 0;
  labor_unit numeric := 0;

  missing jsonb := '[]'::jsonb;
  status text := 'ok';
  model text := 'wac30_recipe_labor_pack_oh_v1';

  rec record;
  cost numeric;
  base_uom text;
  qty_base numeric;
  loaded_rate numeric;
begin
  rv_id := public.select_recipe_version_id(p_org_id, p_sku, p_as_of);

  if rv_id is null then
    -- fallback to products.unit_cost as material
    select coalesce(p.unit_cost,0) into mat_unit
    from public.products p
    where p.org_id=p_org_id and p.sku=p_sku;

    status := 'fallback';
    missing := missing || jsonb_build_array('missing_recipe');
  else
    select rv.yield_qty into yield_qty from public.recipe_versions rv where rv.id=rv_id;

    for rec in
      select ri.qty, ri.uom, ri.loss_pct, i.id as ingredient_id, i.base_uom, i.ingredient_code
      from public.recipe_items ri
      join public.ingredients i on i.id = ri.ingredient_id
      where ri.recipe_version_id = rv_id
    loop
      cost := public.wac_unit_cost(p_org_id, rec.ingredient_id, p_as_of, w);
      if cost is null then
        status := 'missing_inputs';
        missing := missing || jsonb_build_array('ingredient_cost:' || rec.ingredient_code);
        continue;
      end if;

      qty_base := public.to_base_qty(rec.qty, rec.uom, rec.base_uom) * (1 + rec.loss_pct);
      mat_batch := mat_batch + (qty_base * cost);
    end loop;

    mat_unit := case when yield_qty is null or yield_qty = 0 then 0 else (mat_batch / yield_qty) end;
  end if;

  -- Packaging per unit
  for rec in
    select pi.qty, pi.uom, i.id as ingredient_id, i.base_uom, i.ingredient_code
    from public.product_packaging_items pi
    join public.ingredients i on i.id = pi.ingredient_id
    where pi.org_id = p_org_id and pi.sku = p_sku
  loop
    cost := public.wac_unit_cost(p_org_id, rec.ingredient_id, p_as_of, w);
    if cost is null then
      if status = 'ok' then status := 'missing_inputs'; end if;
      missing := missing || jsonb_build_array('packaging_cost:' || rec.ingredient_code);
      continue;
    end if;

    qty_base := public.to_base_qty(rec.qty, rec.uom, rec.base_uom);
    pack_unit := pack_unit + (qty_base * cost);
  end loop;

  -- Labor per unit
  for rec in
    select pls.role_code, pls.seconds_per_unit
    from public.product_labor_specs pls
    where pls.org_id = p_org_id and pls.sku = p_sku
  loop
    loaded_rate := public.select_loaded_hourly_rate(p_org_id, rec.role_code, p_as_of);
    if loaded_rate is null then
      if status = 'ok' then status := 'missing_inputs'; end if;
      missing := missing || jsonb_build_array('labor_rate:' || rec.role_code);
      continue;
    end if;

    labor_unit := labor_unit + ((rec.seconds_per_unit::numeric / 3600) * loaded_rate);
  end loop;

  return jsonb_build_object(
    'sku', p_sku,
    'as_of', p_as_of,
    'wac_days', w,
    'recipe_version_id', rv_id,
    'material_unit', round(mat_unit, 6),
    'packaging_unit', round(pack_unit, 6),
    'labor_unit', round(labor_unit, 6),
    'status', status,
    'missing', missing,
    'model', model
  );
end $$;


ALTER FUNCTION "public"."compute_unit_cogs"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date", "p_wac_days" integer) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."import_jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "entity_type" "public"."import_entity" NOT NULL,
    "status" "public"."import_job_status" DEFAULT 'uploaded'::"public"."import_job_status" NOT NULL,
    "original_filename" "text" NOT NULL,
    "storage_bucket" "text" DEFAULT 'imports'::"text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "file_size" bigint,
    "content_type" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "summary" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "import_jobs_original_filename_check" CHECK ((("char_length"("original_filename") >= 1) AND ("char_length"("original_filename") <= 512))),
    CONSTRAINT "import_jobs_storage_bucket_check" CHECK (("storage_bucket" = 'imports'::"text")),
    CONSTRAINT "import_jobs_storage_path_check" CHECK ((("char_length"("storage_path") >= 3) AND ("char_length"("storage_path") <= 1024)))
);


ALTER TABLE "public"."import_jobs" OWNER TO "postgres";


COMMENT ON TABLE "public"."import_jobs" IS 'One row per uploaded file. Drives the Import Center workflow.';



CREATE OR REPLACE FUNCTION "public"."create_import_job"("p_job_id" "uuid", "p_org_id" "uuid", "p_entity_type" "public"."import_entity", "p_original_filename" "text", "p_storage_path" "text", "p_file_size" bigint, "p_content_type" "text", "p_metadata" "jsonb") RETURNS "public"."import_jobs"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  v_row public.import_jobs;
  v_expected_prefix text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  v_expected_prefix := p_org_id::text || '/';
  if position(v_expected_prefix in p_storage_path) <> 1 then
    raise exception 'storage_path_must_start_with_org_id';
  end if;

  insert into public.import_jobs(
    id,
    org_id,
    created_by,
    entity_type,
    status,
    original_filename,
    storage_bucket,
    storage_path,
    file_size,
    content_type,
    metadata
  )
  values (
    p_job_id,
    p_org_id,
    auth.uid(),
    p_entity_type,
    'uploaded',
    p_original_filename,
    'imports',
    p_storage_path,
    p_file_size,
    p_content_type,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning * into v_row;

  return v_row;
end;
$$;


ALTER FUNCTION "public"."create_import_job"("p_job_id" "uuid", "p_org_id" "uuid", "p_entity_type" "public"."import_entity", "p_original_filename" "text", "p_storage_path" "text", "p_file_size" bigint, "p_content_type" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_org"("p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  v_name := trim(coalesce(p_name, ''));
  if char_length(v_name) < 2 then
    raise exception 'invalid_org_name';
  end if;

  insert into public.orgs(name, created_by)
  values (v_name, auth.uid())
  returning id into v_org_id;

  insert into public.org_members(org_id, user_id, role)
  values (v_org_id, auth.uid(), 'super_admin');

  return v_org_id;
end;
$$;


ALTER FUNCTION "public"."create_org"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."default_org_member_role"() RETURNS "public"."org_role"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_catalog'
    AS $$
  with ev as (
    select e.enumlabel, e.enumsortorder
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'org_role'
  )
  select
    coalesce(
      (
        select enumlabel::public.org_role
        from ev
        order by
          case enumlabel
            when 'viewer' then 1
            when 'read_only' then 2
            when 'analyst' then 3
            when 'user' then 4
            when 'member' then 5
            else 100
          end,
          enumsortorder
        limit 1
      ),
      (
        select enumlabel::public.org_role
        from ev
        where enumlabel not in ('super_admin','admin','owner')
        order by enumsortorder
        limit 1
      ),
      (
        select enumlabel::public.org_role
        from ev
        order by enumsortorder
        limit 1
      )
    );
$$;


ALTER FUNCTION "public"."default_org_member_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_first_org_member_super_admin"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  member_count int;
begin
  select count(*) into member_count
  from public.org_members
  where org_id = new.org_id;

  if member_count = 0 then
    new.role := 'super_admin';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_first_org_member_super_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expense_source_hash"("p" "jsonb") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'extensions', 'public'
    AS $$
  select encode(digest(convert_to(coalesce(p::text,''), 'utf8'), 'sha256'), 'hex');
$$;


ALTER FUNCTION "public"."expense_source_hash"("p" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_benchmark_points"("p_org_id" "uuid", "p_days" integer DEFAULT 30) RETURNS TABLE("plot_id" "text", "plot_title" "text", "x_label" "text", "y_label" "text", "series" "text", "branch_id" "uuid", "label" "text", "x" numeric, "y" numeric, "n" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'Forbidden';
  end if;

  return query
  select *
  from public.get_benchmark_points_core(p_org_id, p_days);
end $$;


ALTER FUNCTION "public"."get_benchmark_points"("p_org_id" "uuid", "p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_benchmark_points_core"("p_org_id" "uuid", "p_days" integer DEFAULT 30) RETURNS TABLE("plot_id" "text", "plot_title" "text", "x_label" "text", "y_label" "text", "series" "text", "branch_id" "uuid", "label" "text", "x" numeric, "y" numeric, "n" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
with
lim as (
  select
    greatest(7, least(p_days, 365))::int as days,
    coalesce(t.max_benchmark_plots, 4)::int as max_plots,
    (t.global_benchmark_enabled or public.is_platform_admin()) as global_enabled,
    public.org_anchor_date(p_org_id) as anchor
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
),
w as (
  select
    (anchor - (days - 1))::date as start_day,
    anchor::date as end_day,
    max_plots,
    global_enabled
  from lim
),
m as (
  select
    inv.org_id,
    inv.branch_id,
    coalesce(b.name, b.code, 'Unknown') as branch_name,
    sum(si.net_sales) as net_sales,
    count(distinct inv.external_invoice_number) as invoices,
    sum(si.quantity) as units_sold,
    sum(si.cogs_total) as cogs_total,
    sum(si.cogs_labor) as cogs_labor,
    sum(si.cogs_overhead) as cogs_overhead
  from public.sales_items si
  join public.sales_invoices inv on inv.id = si.invoice_id
  left join public.branches b on b.id = inv.branch_id
  cross join w
  where inv.invoice_date between w.start_day and w.end_day
    and inv.branch_id is not null
  group by inv.org_id, inv.branch_id, branch_name
),
mx as (
  select
    m.*,
    (m.net_sales - m.cogs_total) as gross_profit,
    case when m.net_sales=0 then null else ((m.net_sales - m.cogs_total)/m.net_sales) end as gross_margin,
    case when m.invoices=0 then null else (m.net_sales/m.invoices) end as avg_ticket,
    case when m.net_sales=0 then null else (m.cogs_labor/m.net_sales) end as labor_pct,
    case when m.net_sales=0 then null else (m.cogs_overhead/m.net_sales) end as overhead_pct,
    case when m.units_sold=0 then null else (m.cogs_total/m.units_sold) end as cogs_per_unit
  from m
),
oc as (select count(*)::int as other_cnt from mx where mx.org_id <> p_org_id),
privacy as (select (other_cnt >= 10) as allow_others from oc),
bcnt as (select greatest(1, least(20, floor((select other_cnt from oc)/5.0)::int)) as b),

p1_self as (
  select 'sales_vs_margin'::text plot_id,'Net Sales vs Gross Margin'::text plot_title,'Net Sales'::text x_label,'Gross Margin %'::text y_label,
    'self'::text series, mx.branch_id branch_id, mx.branch_name::text label,
    mx.net_sales::numeric x, mx.gross_margin::numeric y, null::int n, 1 plot_order
  from mx where mx.org_id=p_org_id
),
p1_oth as (
  select 'sales_vs_margin'::text plot_id,'Net Sales vs Gross Margin'::text plot_title,'Net Sales'::text x_label,'Gross Margin %'::text y_label,
    'others'::text series, null::uuid branch_id, 'Others'::text label,
    avg(s.xv)::numeric x, avg(s.yv)::numeric y, count(*)::int n, 1 plot_order
  from (
    select ntile((select b from bcnt)) over(order by mx.net_sales) as bucket,
      mx.net_sales::numeric as xv,
      mx.gross_margin::numeric as yv
    from mx where mx.org_id<>p_org_id and mx.net_sales is not null and mx.gross_margin is not null
  ) s
  group by s.bucket
),

p2_self as (
  select 'invoices_vs_ticket','Invoices vs Avg Ticket','Invoices','Avg Ticket',
    'self', mx.branch_id, mx.branch_name,
    mx.invoices::numeric, mx.avg_ticket::numeric, null::int, 2
  from mx where mx.org_id=p_org_id
),
p2_oth as (
  select 'invoices_vs_ticket','Invoices vs Avg Ticket','Invoices','Avg Ticket',
    'others', null::uuid, 'Others',
    avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 2
  from (
    select ntile((select b from bcnt)) over(order by mx.invoices) as bucket,
      mx.invoices::numeric as xv,
      mx.avg_ticket::numeric as yv
    from mx where mx.org_id<>p_org_id and mx.invoices is not null and mx.avg_ticket is not null
  ) s
  group by s.bucket
),

p3_self as (
  select 'labor_pct_vs_margin','Labor % vs Gross Margin','Labor %','Gross Margin %',
    'self', mx.branch_id, mx.branch_name,
    mx.labor_pct::numeric, mx.gross_margin::numeric, null::int, 3
  from mx where mx.org_id=p_org_id
),
p3_oth as (
  select 'labor_pct_vs_margin','Labor % vs Gross Margin','Labor %','Gross Margin %',
    'others', null::uuid, 'Others',
    avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 3
  from (
    select ntile((select b from bcnt)) over(order by mx.labor_pct) as bucket,
      mx.labor_pct::numeric as xv,
      mx.gross_margin::numeric as yv
    from mx where mx.org_id<>p_org_id and mx.labor_pct is not null and mx.gross_margin is not null
  ) s
  group by s.bucket
),

p4_self as (
  select 'overhead_pct_vs_margin','Overhead % vs Gross Margin','Overhead %','Gross Margin %',
    'self', mx.branch_id, mx.branch_name,
    mx.overhead_pct::numeric, mx.gross_margin::numeric, null::int, 4
  from mx where mx.org_id=p_org_id
),
p4_oth as (
  select 'overhead_pct_vs_margin','Overhead % vs Gross Margin','Overhead %','Gross Margin %',
    'others', null::uuid, 'Others',
    avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 4
  from (
    select ntile((select b from bcnt)) over(order by mx.overhead_pct) as bucket,
      mx.overhead_pct::numeric as xv,
      mx.gross_margin::numeric as yv
    from mx where mx.org_id<>p_org_id and mx.overhead_pct is not null and mx.gross_margin is not null
  ) s
  group by s.bucket
),

p5_self as (
  select 'sales_vs_gross_profit','Net Sales vs Gross Profit','Net Sales','Gross Profit',
    'self', mx.branch_id, mx.branch_name,
    mx.net_sales::numeric, mx.gross_profit::numeric, null::int, 5
  from mx where mx.org_id=p_org_id
),
p5_oth as (
  select 'sales_vs_gross_profit','Net Sales vs Gross Profit','Net Sales','Gross Profit',
    'others', null::uuid, 'Others',
    avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 5
  from (
    select ntile((select b from bcnt)) over(order by mx.net_sales) as bucket,
      mx.net_sales::numeric as xv,
      mx.gross_profit::numeric as yv
    from mx where mx.org_id<>p_org_id and mx.net_sales is not null and mx.gross_profit is not null
  ) s
  group by s.bucket
),

p6_self as (
  select 'ticket_vs_cogs_unit','Avg Ticket vs COGS/Unit','Avg Ticket','COGS/Unit',
    'self', mx.branch_id, mx.branch_name,
    mx.avg_ticket::numeric, mx.cogs_per_unit::numeric, null::int, 6
  from mx where mx.org_id=p_org_id
),
p6_oth as (
  select 'ticket_vs_cogs_unit','Avg Ticket vs COGS/Unit','Avg Ticket','COGS/Unit',
    'others', null::uuid, 'Others',
    avg(s.xv)::numeric, avg(s.yv)::numeric, count(*)::int, 6
  from (
    select ntile((select b from bcnt)) over(order by mx.avg_ticket) as bucket,
      mx.avg_ticket::numeric as xv,
      mx.cogs_per_unit::numeric as yv
    from mx where mx.org_id<>p_org_id and mx.avg_ticket is not null and mx.cogs_per_unit is not null
  ) s
  group by s.bucket
),

points as (
  select * from p1_self union all select * from p1_oth
  union all select * from p2_self union all select * from p2_oth
  union all select * from p3_self union all select * from p3_oth
  union all select * from p4_self union all select * from p4_oth
  union all select * from p5_self union all select * from p5_oth
  union all select * from p6_self union all select * from p6_oth
),
filtered as (
  select
    points.*,
    w.max_plots,
    w.global_enabled,
    (select allow_others from privacy) as allow_others
  from points
  cross join w
)
select
  f.plot_id, f.plot_title, f.x_label, f.y_label,
  f.series, f.branch_id, f.label, f.x, f.y, f.n
from filtered f
where f.plot_order <= f.max_plots
  and (f.series='self' or (f.global_enabled and f.allow_others))
order by f.plot_order asc, f.series asc, f.label asc;
$$;


ALTER FUNCTION "public"."get_benchmark_points_core"("p_org_id" "uuid", "p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer DEFAULT 30, "p_cogs_mode" "text" DEFAULT 'unit_cost'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
declare
  a date;
  d int := greatest(1, least(p_days, 3650));
  cur_start date;
  cur_end date;
  prev_start date;
  prev_end date;

  cur_net numeric := 0;
  cur_cogs numeric := 0;
  cur_gp numeric := 0;
  cur_exp numeric := 0;
  cur_inv bigint := 0;

  prev_net numeric := 0;
  prev_cogs numeric := 0;
  prev_gp numeric := 0;
  prev_exp numeric := 0;
  prev_inv bigint := 0;

  mode text := coalesce(nullif(p_cogs_mode,''),'unit_cost');
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'Forbidden';
  end if;

  a := public.org_anchor_date(p_org_id);
  cur_end := a;
  cur_start := a - (d - 1);

  prev_end := cur_start - 1;
  prev_start := prev_end - (d - 1);

  -- current period sales
  with lines as (
    select
      si.org_id,
      inv.invoice_date,
      si.net_sales,
      si.quantity,
      si.sku
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = p_org_id
      and inv.invoice_date between cur_start and cur_end
  ),
  c as (
    select
      sum(net_sales) as net_sales,
      sum(
        case when mode='unit_cost'
          then (quantity * coalesce(p.unit_cost,0))
          else 0
        end
      ) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
  )
  select coalesce(net_sales,0), coalesce(cogs,0) into cur_net, cur_cogs
  from c;

  select count(distinct inv.external_invoice_number) into cur_inv
  from public.sales_invoices inv
  where inv.org_id=p_org_id and inv.invoice_date between cur_start and cur_end;

  cur_gp := cur_net - cur_cogs;

  -- current expenses (pre-tax amount)
  select coalesce(sum(amount),0) into cur_exp
  from public.expenses
  where org_id=p_org_id and expense_date between cur_start and cur_end;

  -- previous period sales
  with lines as (
    select
      si.org_id,
      inv.invoice_date,
      si.net_sales,
      si.quantity,
      si.sku
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    where si.org_id = p_org_id
      and inv.invoice_date between prev_start and prev_end
  ),
  c as (
    select
      sum(net_sales) as net_sales,
      sum(
        case when mode='unit_cost'
          then (quantity * coalesce(p.unit_cost,0))
          else 0
        end
      ) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
  )
  select coalesce(net_sales,0), coalesce(cogs,0) into prev_net, prev_cogs
  from c;

  select count(distinct inv.external_invoice_number) into prev_inv
  from public.sales_invoices inv
  where inv.org_id=p_org_id and inv.invoice_date between prev_start and prev_end;

  prev_gp := prev_net - prev_cogs;

  select coalesce(sum(amount),0) into prev_exp
  from public.expenses
  where org_id=p_org_id and expense_date between prev_start and prev_end;

  return jsonb_build_object(
    'anchor_date', a,
    'days', d,
    'cogs_mode', mode,

    'net_sales', cur_net,
    'cogs', cur_cogs,
    'gross_profit', cur_gp,
    'gross_margin', case when cur_net=0 then null else (cur_gp/cur_net) end,
    'expenses', cur_exp,
    'net_profit', cur_gp - cur_exp,
    'invoices', cur_inv,

    'prev_net_sales', prev_net,
    'prev_cogs', prev_cogs,
    'prev_gross_profit', prev_gp,
    'prev_expenses', prev_exp,
    'prev_net_profit', prev_gp - prev_exp,
    'prev_invoices', prev_inv
  );
end $$;


ALTER FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer DEFAULT 30, "p_cogs_mode" "text" DEFAULT 'engine'::"text", "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  a date;
  d int := greatest(1, least(p_days, 3650));
  cur_start date;
  cur_end date;
  mode text := coalesce(nullif(p_cogs_mode,''),'engine');

  net_sales numeric := 0;
  cogs numeric := 0;
  invoices bigint := 0;
begin
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  a := public.org_anchor_date(p_org_id);
  cur_end := a;
  cur_start := a - (d - 1);

  select coalesce(sum(si.net_sales),0)
    into net_sales
  from public.sales_items si
  join public.sales_invoices inv on inv.id=si.invoice_id
  where inv.org_id=p_org_id
    and inv.invoice_date between cur_start and cur_end
    and (p_branch_id is null or inv.branch_id = p_branch_id);

  select count(distinct inv.external_invoice_number) into invoices
  from public.sales_invoices inv
  where inv.org_id=p_org_id
    and inv.invoice_date between cur_start and cur_end
    and (p_branch_id is null or inv.branch_id = p_branch_id);

  if mode='engine' then
    select coalesce(sum(si.cogs_total),0) into cogs
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    where inv.org_id=p_org_id
      and inv.invoice_date between cur_start and cur_end
      and (p_branch_id is null or inv.branch_id = p_branch_id);
  elsif mode='unit_cost' then
    select coalesce(sum(si.quantity * coalesce(p.unit_cost,0)),0) into cogs
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    left join public.products p on p.org_id=inv.org_id and p.sku=si.sku
    where inv.org_id=p_org_id
      and inv.invoice_date between cur_start and cur_end
      and (p_branch_id is null or inv.branch_id = p_branch_id);
  else
    cogs := 0;
  end if;

  return jsonb_build_object(
    'anchor_date', a,
    'days', d,
    'cogs_mode', mode,
    'branch_id', p_branch_id,
    'net_sales', net_sales,
    'cogs', cogs,
    'gross_profit', (net_sales - cogs),
    'gross_margin', case when net_sales=0 then null else ((net_sales - cogs)/net_sales) end,
    'invoices', invoices
  );
end $$;


ALTER FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer DEFAULT 12, "p_cogs_mode" "text" DEFAULT 'unit_cost'::"text") RETURNS TABLE("month" "date", "net_sales" numeric, "gross_profit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_months, 60)) as m,
      coalesce(nullif(p_cogs_mode,''),'unit_cost') as mode
  ),
  w as (
    select
      date_trunc('month', a)::date as end_month,
      (date_trunc('month', a)::date - ((m-1) * interval '1 month'))::date as start_month,
      mode
    from params
  ),
  lines as (
    select
      si.org_id,
      date_trunc('month', inv.invoice_date)::date as month,
      si.net_sales,
      si.quantity,
      si.sku,
      w.mode
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    cross join w w
    where si.org_id=p_org_id
      and inv.invoice_date >= w.start_month
      and inv.invoice_date < (w.end_month + interval '1 month')
  ),
  agg as (
    select
      l.month,
      sum(l.net_sales) as net_sales,
      sum(case when l.mode='unit_cost' then (l.quantity * coalesce(p.unit_cost,0)) else 0 end) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
    group by l.month
  )
  select month, net_sales, (net_sales - cogs) as gross_profit
  from agg
  order by month asc;
$$;


ALTER FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer DEFAULT 12, "p_cogs_mode" "text" DEFAULT 'engine'::"text", "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("month" "date", "net_sales" numeric, "gross_profit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_months, 60)) as m,
      coalesce(nullif(p_cogs_mode,''),'engine') as mode
  ),
  win as (
    select
      date_trunc('month', a)::date as end_m,
      (date_trunc('month', a) - ((m-1) || ' months')::interval)::date as start_m,
      mode
    from params
  ),
  lines as (
    select
      date_trunc('month', inv.invoice_date)::date as month,
      sum(si.net_sales) as net_sales,
      sum(
        case
          when win.mode='engine' then si.cogs_total
          when win.mode='unit_cost' then (si.quantity * coalesce(p.unit_cost,0))
          else 0
        end
      ) as cogs
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    left join public.products p on p.org_id=inv.org_id and p.sku=si.sku
    cross join win
    where inv.org_id=p_org_id
      and inv.invoice_date >= win.start_m
      and inv.invoice_date <= (select a from params)
      and (p_branch_id is null or inv.branch_id = p_branch_id)
    group by 1
  )
  select
    month,
    net_sales,
    (net_sales - cogs) as gross_profit
  from lines
  order by month asc;
$$;


ALTER FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_expense_allocations"("p_expense_id" "uuid") RETURNS TABLE("cost_center_code" "text", "amount" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select a.cost_center_code, a.amount
  from public.expense_allocations a
  where a.expense_id = p_expense_id
  order by a.cost_center_code asc;
$$;


ALTER FUNCTION "public"."get_expense_allocations"("p_expense_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_expenses_cost_center_daily"("p_org_id" "uuid", "p_limit" integer DEFAULT 90) RETURNS TABLE("day" "date", "cost_center_code" "text", "amount" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'analytics'
    AS $$
  select day::date, cost_center_code, amount
  from analytics.v_expenses_cost_center_daily
  where org_id = p_org_id
  order by day desc, cost_center_code asc
  limit greatest(1, least(p_limit, 3650));
$$;


ALTER FUNCTION "public"."get_expenses_cost_center_daily"("p_org_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer DEFAULT 60) RETURNS TABLE("day" "date", "amount" numeric, "tax_amount" numeric, "total_amount" numeric, "expense_rows" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'analytics'
    AS $$
  select
    day::date,
    amount,
    tax_amount,
    total_amount,
    expense_rows
  from analytics.v_expenses_daily
  where org_id = p_org_id
  order by day desc
  limit greatest(1, least(p_limit, 3650));
$$;


ALTER FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer DEFAULT 60, "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("day" "date", "amount" numeric, "tax_amount" numeric, "total_amount" numeric, "expense_rows" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with a as (select public.org_anchor_date(p_org_id) as anchor),
  w as (
    select (anchor - (greatest(1, least(p_limit, 3650)) - 1))::date as start_day, anchor as end_day
    from a
  )
  select
    e.expense_date as day,
    sum(e.amount) as amount,
    sum(coalesce(e.tax_amount,0)) as tax_amount,
    sum(coalesce(e.total_amount, (e.amount + coalesce(e.tax_amount,0)))) as total_amount,
    count(*)::int as expense_rows
  from public.expenses e
  cross join w
  where e.org_id = p_org_id
    and e.expense_date between w.start_day and w.end_day
    and (p_branch_id is null or e.branch_id = p_branch_id)
  group by e.expense_date
  order by e.expense_date desc;
$$;


ALTER FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_forecast_outputs"("p_run_id" "uuid") RETURNS TABLE("day" "date", "p50_net_sales" numeric, "p80_low" numeric, "p80_high" numeric, "p95_low" numeric, "p95_high" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select o.day, o.p50_net_sales, o.p80_low, o.p80_high, o.p95_low, o.p95_high
  from public.forecast_outputs o
  where o.run_id = p_run_id
  order by o.day asc;
$$;


ALTER FUNCTION "public"."get_forecast_outputs"("p_run_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_import_contract"("p_entity" "public"."import_entity") RETURNS TABLE("canonical_key" "text", "display_name" "text", "data_type" "text", "is_required" boolean, "ordinal" integer)
    LANGUAGE "sql" STABLE
    AS $$
  select canonical_key, display_name, data_type, is_required, ordinal
  from public.import_contract_fields
  where entity_type = p_entity
  order by is_required desc, ordinal asc, canonical_key asc;
$$;


ALTER FUNCTION "public"."get_import_contract"("p_entity" "public"."import_entity") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_import_job"("p_job_id" "uuid") RETURNS "public"."import_jobs"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select *
  from public.import_jobs
  where id = p_job_id
  limit 1;
$$;


ALTER FUNCTION "public"."get_import_job"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_org_entitlements"("p_org_id" "uuid") RETURNS TABLE("max_branches" integer, "max_benchmark_plots" integer, "global_benchmark_enabled" boolean, "tier_code" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select t.max_branches, t.max_benchmark_plots, t.global_benchmark_enabled, t.tier_code
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = p_org_id
    and (public.is_platform_admin() or public.is_org_member(p_org_id));
$$;


ALTER FUNCTION "public"."get_org_entitlements"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_platform_support_email"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select support_email
  from public.platform_settings
  where id=1;
$$;


ALTER FUNCTION "public"."get_platform_support_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer DEFAULT 60) RETURNS TABLE("day" "date", "net_sales" numeric, "tax_amount" numeric, "total_amount" numeric, "invoices" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'analytics'
    AS $$
  select
    day::date,
    net_sales,
    tax_amount,
    total_amount,
    invoices
  from analytics.v_sales_daily
  where org_id = p_org_id
  order by day desc
  limit greatest(1, least(p_limit, 3650));
$$;


ALTER FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer DEFAULT 60, "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("day" "date", "net_sales" numeric, "tax_amount" numeric, "total_amount" numeric, "invoices" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with a as (select public.org_anchor_date(p_org_id) as anchor),
  w as (
    select (anchor - (greatest(1, least(p_limit, 3650)) - 1))::date as start_day, anchor as end_day
    from a
  )
  select
    inv.invoice_date as day,
    sum(si.net_sales) as net_sales,
    sum(coalesce(si.tax_amount,0)) as tax_amount,
    sum(coalesce(si.total_amount,0)) as total_amount,
    count(distinct inv.external_invoice_number)::int as invoices
  from public.sales_items si
  join public.sales_invoices inv on inv.id = si.invoice_id
  cross join w
  where inv.org_id = p_org_id
    and inv.invoice_date between w.start_day and w.end_day
    and (p_branch_id is null or inv.branch_id = p_branch_id)
  group by inv.invoice_date
  order by inv.invoice_date desc;
$$;


ALTER FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sales_daily_range"("p_org_id" "uuid", "p_start" "date", "p_end" "date") RETURNS TABLE("day" "date", "net_sales" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    inv.invoice_date as day,
    sum(si.net_sales) as net_sales
  from public.sales_items si
  join public.sales_invoices inv on inv.id = si.invoice_id
  where inv.org_id = p_org_id
    and inv.invoice_date between p_start and p_end
  group by inv.invoice_date
  order by inv.invoice_date asc;
$$;


ALTER FUNCTION "public"."get_sales_daily_range"("p_org_id" "uuid", "p_start" "date", "p_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_top_categories_30d"("p_org_id" "uuid", "p_limit" integer DEFAULT 10, "p_cogs_mode" "text" DEFAULT 'unit_cost'::"text") RETURNS TABLE("category" "text", "net_sales" numeric, "cogs" numeric, "gross_profit" numeric, "gross_margin" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_limit, 50)) as lim,
      coalesce(nullif(p_cogs_mode,''),'unit_cost') as mode
  ),
  w as (
    select (a - interval '29 days')::date as start_day, a as end_day, lim, mode
    from params
  ),
  lines as (
    select
      si.org_id,
      inv.invoice_date,
      coalesce(nullif(si.category,''),'Uncategorized') as category,
      si.net_sales,
      si.quantity,
      si.sku,
      w.mode
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    cross join w
    where si.org_id=p_org_id and inv.invoice_date between w.start_day and w.end_day
  ),
  agg as (
    select
      l.category,
      sum(l.net_sales) as net_sales,
      sum(case when l.mode='unit_cost' then (l.quantity * coalesce(p.unit_cost,0)) else 0 end) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
    group by l.category
  )
  select
    category,
    net_sales,
    cogs,
    (net_sales - cogs) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs)/net_sales) end as gross_margin
  from agg
  order by gross_profit desc nulls last
  limit (select lim from w);
$$;


ALTER FUNCTION "public"."get_top_categories_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_top_products_30d"("p_org_id" "uuid", "p_limit" integer DEFAULT 10, "p_cogs_mode" "text" DEFAULT 'unit_cost'::"text") RETURNS TABLE("sku" "text", "product_name" "text", "category" "text", "net_sales" numeric, "cogs" numeric, "gross_profit" numeric, "gross_margin" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select
      public.org_anchor_date(p_org_id) as a,
      greatest(1, least(p_limit, 50)) as lim,
      coalesce(nullif(p_cogs_mode,''),'unit_cost') as mode
  ),
  w as (
    select (a - interval '29 days')::date as start_day, a as end_day, lim, mode
    from params
  ),
  lines as (
    select
      si.org_id,
      inv.invoice_date,
      si.sku,
      si.product_name,
      si.category,
      si.net_sales,
      si.quantity,
      w.mode
    from public.sales_items si
    join public.sales_invoices inv on inv.id=si.invoice_id
    cross join w
    where si.org_id=p_org_id and inv.invoice_date between w.start_day and w.end_day
  ),
  agg as (
    select
      l.sku,
      max(l.product_name) as product_name,
      max(l.category) as category,
      sum(l.net_sales) as net_sales,
      sum(case when l.mode='unit_cost' then (l.quantity * coalesce(p.unit_cost,0)) else 0 end) as cogs
    from lines l
    left join public.products p on p.org_id=l.org_id and p.sku=l.sku
    group by l.sku
  )
  select
    sku,
    product_name,
    category,
    net_sales,
    cogs,
    (net_sales - cogs) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs)/net_sales) end as gross_margin
  from agg
  order by gross_profit desc nulls last
  limit (select lim from w);
$$;


ALTER FUNCTION "public"."get_top_products_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer DEFAULT 30) RETURNS TABLE("sku" "text", "product_name" "text", "units_sold" numeric, "net_sales" numeric, "cogs_material" numeric, "cogs_packaging" numeric, "cogs_labor" numeric, "cogs_overhead" numeric, "cogs_total" numeric, "gross_profit" numeric, "gross_margin" numeric, "cogs_per_unit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select public.org_anchor_date(p_org_id) as a, greatest(1, least(p_days, 3650)) as d
  ),
  w as (
    select (a - (d-1))::date as start_day, a as end_day from params
  ),
  lines as (
    select
      si.sku,
      max(coalesce(si.product_name, p.product_name, si.sku)) as product_name,
      sum(si.quantity) as units_sold,
      sum(si.net_sales) as net_sales,
      sum(si.cogs_material) as cogs_material,
      sum(si.cogs_packaging) as cogs_packaging,
      sum(si.cogs_labor) as cogs_labor,
      sum(si.cogs_overhead) as cogs_overhead,
      sum(si.cogs_total) as cogs_total
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    left join public.products p on p.org_id = inv.org_id and p.sku = si.sku
    cross join w
    where inv.org_id = p_org_id
      and inv.invoice_date between w.start_day and w.end_day
      and si.sku is not null
    group by si.sku
  )
  select
    sku,
    product_name,
    units_sold,
    net_sales,
    cogs_material,
    cogs_packaging,
    cogs_labor,
    cogs_overhead,
    cogs_total,
    (net_sales - cogs_total) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs_total)/net_sales) end as gross_margin,
    case when units_sold=0 then null else (cogs_total/units_sold) end as cogs_per_unit
  from lines
  order by gross_profit desc nulls last;
$$;


ALTER FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer DEFAULT 30, "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("sku" "text", "product_name" "text", "units_sold" numeric, "net_sales" numeric, "cogs_total" numeric, "gross_profit" numeric, "gross_margin" numeric, "cogs_per_unit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with params as (
    select public.org_anchor_date(p_org_id) as a, greatest(1, least(p_days, 3650)) as d
  ),
  w as (
    select (a - (d-1))::date as start_day, a as end_day from params
  ),
  agg as (
    select
      si.sku,
      max(coalesce(si.product_name, p.product_name, si.sku)) as product_name,
      sum(si.quantity) as units_sold,
      sum(si.net_sales) as net_sales,
      sum(si.cogs_total) as cogs_total
    from public.sales_items si
    join public.sales_invoices inv on inv.id = si.invoice_id
    left join public.products p on p.org_id = inv.org_id and p.sku = si.sku
    cross join w
    where inv.org_id = p_org_id
      and inv.invoice_date between w.start_day and w.end_day
      and (p_branch_id is null or inv.branch_id = p_branch_id)
      and si.sku is not null
    group by si.sku
  )
  select
    sku,
    product_name,
    units_sold,
    net_sales,
    cogs_total,
    (net_sales - cogs_total) as gross_profit,
    case when net_sales=0 then null else ((net_sales - cogs_total)/net_sales) end as gross_margin,
    case when units_sold=0 then null else (cogs_total/units_sold) end as cogs_per_unit
  from agg
  order by gross_profit desc nulls last;
$$;


ALTER FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer, "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles(user_id, email, full_name)
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data->>'full_name','')), '')
  )
  on conflict (user_id) do update
    set email = excluded.email,
        full_name = excluded.full_name,
        updated_at = now();

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."import_expenses_from_staging"("p_job_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_job public.import_jobs;
  v_org uuid;
  v_bad int;
  v_rows int;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;
  if v_job.entity_type <> 'expenses' then raise exception 'Only expenses supported'; end if;
  if v_job.status <> 'validated' then raise exception 'Job must be validated'; end if;

  v_org := v_job.org_id;

  if not public.is_org_member(v_org) then
    raise exception 'Forbidden';
  end if;

  select count(*) into v_bad from public.import_job_rows where job_id=p_job_id and is_valid=false;
  if v_bad > 0 then raise exception 'Cannot import: % invalid rows', v_bad; end if;

  -- Ensure branch exists for branch_code, if provided
  insert into public.branches(org_id, name, code)
  select distinct
    v_org,
    upper(trim(b.branch_code)) as name,
    upper(trim(b.branch_code)) as code
  from (
    select distinct nullif(trim(r.parsed->>'branch_code'), '') as branch_code
    from public.import_job_rows r
    where r.job_id=p_job_id and r.is_valid=true
  ) b
  where b.branch_code is not null
  on conflict (org_id, code) do update set name = excluded.name;

  with src as (
    select
      v_org as org_id,
      (r.parsed->>'expense_date')::date as expense_date,
      nullif(trim(r.parsed->>'reference_number'), '') as reference_number,
      nullif(trim(r.parsed->>'vendor'), '') as vendor,
      upper(nullif(trim(r.parsed->>'branch_code'), '')) as branch_code,
      nullif(trim(r.parsed->>'cost_center_code'), '') as cost_center_code,
      nullif(trim(r.parsed->>'category'), '') as category,
      (r.parsed->>'amount')::numeric as amount,
      nullif(trim(r.parsed->>'vat_rate'), '')::numeric as vat_rate,
      nullif(trim(r.parsed->>'tax_amount'), '')::numeric as tax_amount,
      nullif(trim(r.parsed->>'total_amount'), '')::numeric as total_amount,
      nullif(trim(r.parsed->>'payment_method'), '') as payment_method,
      nullif(trim(r.parsed->>'notes'), '') as notes,
      upper(nullif(trim(r.parsed->>'currency'), '')) as currency,
      r.parsed as parsed,
      p_job_id as source_import_job_id
    from public.import_job_rows r
    where r.job_id=p_job_id and r.is_valid=true
  ),
  src2 as (
    select
      s.*,
      b.id as branch_id,
      public.expense_source_hash(s.parsed) as source_hash
    from src s
    left join public.branches b
      on b.org_id=s.org_id and b.code=s.branch_code
  )
  insert into public.expenses(
    org_id, branch_id, expense_date, reference_number, vendor, cost_center_code, category,
    amount, vat_rate, tax_amount, total_amount, payment_method, notes, currency,
    source_import_job_id, source_hash
  )
  select
    org_id, branch_id, expense_date, reference_number, vendor, cost_center_code, category,
    amount, vat_rate, tax_amount, total_amount, payment_method, notes, currency,
    source_import_job_id, source_hash
  from src2
  on conflict (org_id, source_hash) do update set
    branch_id = excluded.branch_id,
    expense_date = excluded.expense_date,
    reference_number = excluded.reference_number,
    vendor = excluded.vendor,
    cost_center_code = excluded.cost_center_code,
    category = excluded.category,
    amount = excluded.amount,
    vat_rate = excluded.vat_rate,
    tax_amount = excluded.tax_amount,
    total_amount = excluded.total_amount,
    payment_method = excluded.payment_method,
    notes = excluded.notes,
    currency = excluded.currency,
    source_import_job_id = excluded.source_import_job_id,
    updated_at = now();

  get diagnostics v_rows = row_count;

  update public.import_jobs
  set status='imported',
      summary = jsonb_set(coalesce(summary,'{}'::jsonb), '{imported_rows}', to_jsonb(v_rows), true),
      updated_at = now()
  where id=p_job_id;

  return jsonb_build_object('ok', true, 'imported_rows', v_rows);
end $$;


ALTER FUNCTION "public"."import_expenses_from_staging"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."import_products_from_staging"("p_job_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."import_products_from_staging"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."import_sales_from_staging"("p_job_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
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


ALTER FUNCTION "public"."import_sales_from_staging"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_org_member"("p_org_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    public.is_platform_admin()
    or exists (
      select 1
      from public.org_members m
      where m.org_id = p_org_id
        and m.user_id = auth.uid()
        and m.status = 'approved'
    );
$$;


ALTER FUNCTION "public"."is_org_member"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_org_super_admin"("p_org_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    public.is_platform_admin()
    or exists (
      select 1
      from public.org_members m
      where m.org_id = p_org_id
        and m.user_id = auth.uid()
        and m.status='approved'
        and m.role='super_admin'
    );
$$;


ALTER FUNCTION "public"."is_org_super_admin"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_platform_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid());
$$;


ALTER FUNCTION "public"."is_platform_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_branches_for_org"("p_org_id" "uuid") RETURNS TABLE("branch_id" "uuid", "code" "text", "name" "text", "is_default" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select b.id, b.code, b.name, b.is_default
  from public.branches b
  where b.org_id = p_org_id
    and public.is_org_member(p_org_id)
  order by b.is_default desc, b.name asc;
$$;


ALTER FUNCTION "public"."list_branches_for_org"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_cost_center_codes"("p_org_id" "uuid") RETURNS TABLE("cost_center_code" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select distinct cost_center_code
  from (
    select nullif(trim(e.cost_center_code),'') as cost_center_code
    from public.expenses e
    where e.org_id = p_org_id
    union all
    select nullif(trim(a.cost_center_code),'') as cost_center_code
    from public.expense_allocations a
    where a.org_id = p_org_id
    union all
    select 'UNALLOCATED'::text
  ) x
  where cost_center_code is not null
  order by cost_center_code asc;
$$;


ALTER FUNCTION "public"."list_cost_center_codes"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "uuid", "expense_date" "date", "vendor" "text", "category" "text", "amount" numeric, "allocated_amount" numeric, "allocation_status" "text", "reference_number" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with alloc as (
    select expense_id, sum(amount) as allocated_amount
    from public.expense_allocations
    where org_id = p_org_id
    group by expense_id
  )
  select
    e.id,
    e.expense_date,
    e.vendor,
    e.category,
    e.amount,
    coalesce(a.allocated_amount, 0) as allocated_amount,
    case
      when coalesce(a.allocated_amount,0) = 0 then 'unallocated'
      when abs(coalesce(a.allocated_amount,0) - e.amount) <= 0.01 then 'allocated'
      else 'partial'
    end as allocation_status,
    e.reference_number
  from public.expenses e
  left join alloc a on a.expense_id = e.id
  where e.org_id = p_org_id
  order by e.expense_date desc, e.created_at desc
  limit greatest(1, least(p_limit, 500));
$$;


ALTER FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer DEFAULT 200, "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("expense_id" "uuid", "expense_date" "date", "vendor" "text", "category" "text", "amount" numeric, "allocated_amount" numeric, "unallocated_amount" numeric, "allocation_status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with base as (
    select
      e.id as expense_id,
      e.expense_date,
      e.vendor,
      e.category,
      e.amount
    from public.expenses e
    where e.org_id = p_org_id
      and (p_branch_id is null or e.branch_id = p_branch_id)
    order by e.expense_date desc, e.created_at desc
    limit greatest(1, least(p_limit, 2000))
  ),
  alloc as (
    select a.expense_id, coalesce(sum(a.amount),0) as allocated_amount
    from public.expense_allocations a
    join base b on b.expense_id = a.expense_id
    group by a.expense_id
  )
  select
    b.expense_id,
    b.expense_date,
    b.vendor,
    b.category,
    b.amount,
    coalesce(al.allocated_amount,0) as allocated_amount,
    (b.amount - coalesce(al.allocated_amount,0)) as unallocated_amount,
    case
      when coalesce(al.allocated_amount,0) = 0 then 'unallocated'
      when (b.amount - coalesce(al.allocated_amount,0)) = 0 then 'allocated'
      else 'partial'
    end as allocation_status
  from base b
  left join alloc al on al.expense_id = b.expense_id;
$$;


ALTER FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer DEFAULT 20) RETURNS TABLE("id" "uuid", "created_at" timestamp with time zone, "status" "text", "horizon_days" integer, "history_days" integer, "anchor_date" "date", "model" "text", "message" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select r.id, r.created_at, r.status, r.horizon_days, r.history_days, r.anchor_date, r.model, r.message
  from public.forecast_runs r
  where r.org_id = p_org_id
  order by r.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;


ALTER FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer DEFAULT 20, "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "created_at" timestamp with time zone, "status" "text", "horizon_days" integer, "history_days" integer, "anchor_date" "date", "model" "text", "message" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    fr.id,
    fr.created_at,
    fr.status,
    fr.horizon_days,
    fr.history_days,
    fr.anchor_date,
    fr.model,
    fr.message
  from public.forecast_runs fr
  where fr.org_id = p_org_id
    and (
      (p_branch_id is null and fr.branch_id is null)
      or (p_branch_id is not null and fr.branch_id = p_branch_id)
    )
  order by fr.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;


ALTER FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."import_job_rows" (
    "id" bigint NOT NULL,
    "job_id" "uuid" NOT NULL,
    "row_number" integer NOT NULL,
    "raw" "jsonb" NOT NULL,
    "is_valid" boolean DEFAULT true NOT NULL,
    "errors" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "parsed" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "import_job_rows_row_index_positive" CHECK (("row_number" > 0)),
    CONSTRAINT "import_job_rows_row_number_check" CHECK (("row_number" >= 1))
);


ALTER TABLE "public"."import_job_rows" OWNER TO "postgres";


COMMENT ON TABLE "public"."import_job_rows" IS 'Staged rows + row-level validation results for a specific import job.';



CREATE OR REPLACE FUNCTION "public"."list_import_job_rows"("p_job_id" "uuid", "p_limit" integer DEFAULT 200) RETURNS SETOF "public"."import_job_rows"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select *
  from public.import_job_rows
  where job_id = p_job_id
  order by row_number asc
  limit greatest(1, least(p_limit, 1000));
$$;


ALTER FUNCTION "public"."list_import_job_rows"("p_job_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_import_jobs"("p_org_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS SETOF "public"."import_jobs"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select *
  from public.import_jobs
  where org_id = p_org_id
  order by created_at desc
  limit greatest(1, least(p_limit, 200));
$$;


ALTER FUNCTION "public"."list_import_jobs"("p_org_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_listed_orgs"("p_limit" integer DEFAULT 50) RETURNS TABLE("org_id" "uuid", "name" "text", "support_email" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    o.id,
    o.name,
    coalesce(o.support_email, (select support_email from public.platform_settings where id=1)) as support_email
  from public.orgs o
  where o.is_listed = true
  order by o.name asc
  limit greatest(1, least(p_limit, 500));
$$;


ALTER FUNCTION "public"."list_listed_orgs"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_my_orgs"() RETURNS TABLE("id" "uuid", "name" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select o.id, o.name, o.created_at
  from public.orgs o
  join public.org_members m on m.org_id = o.id
  where m.user_id = auth.uid()
  order by o.created_at asc;
$$;


ALTER FUNCTION "public"."list_my_orgs"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_orgs_for_dropdown"() RETURNS TABLE("org_id" "uuid", "name" "text", "subscription_tier_code" "text", "support_email" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  -- platform admin sees all orgs
  select o.id, o.name, o.subscription_tier_code, coalesce(o.support_email, (select support_email from public.platform_settings where id=1))
  from public.orgs o
  where public.is_platform_admin()

  union all

  -- normal users: only approved memberships
  select o.id, o.name, o.subscription_tier_code, coalesce(o.support_email, (select support_email from public.platform_settings where id=1))
  from public.orgs o
  join public.org_members m on m.org_id = o.id
  where not public.is_platform_admin()
    and m.user_id = auth.uid()
    and m.status = 'approved'
  order by name asc;
$$;


ALTER FUNCTION "public"."list_orgs_for_dropdown"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."norm_dim"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select nullif(regexp_replace(lower(trim(p)), '[^a-z0-9]+', '_', 'g'), '');
$$;


ALTER FUNCTION "public"."norm_dim"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."org_anchor_date"("p_org_id" "uuid") RETURNS "date"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    (select greatest(
      coalesce((select max(invoice_date) from public.sales_invoices where org_id=p_org_id), '1900-01-01'::date),
      coalesce((select max(expense_date) from public.expenses where org_id=p_org_id), '1900-01-01'::date)
    )),
    current_date
  );
$$;


ALTER FUNCTION "public"."org_anchor_date"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."org_bootstrap_defaults"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- Default branch
  insert into public.branches(org_id, name, is_default)
  values (new.id, 'Main', true)
  on conflict do nothing;

  -- System cost centers
  insert into public.cost_centers(org_id, name, code, is_system)
  values
    (new.id, 'General Overhead', 'GENERAL_OVERHEAD', true),
    (new.id, 'Unassigned', 'UNASSIGNED', true)
  on conflict (org_id, code) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."org_bootstrap_defaults"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."overhead_daily"("p_org_id" "uuid", "p_day" "date") RETURNS numeric
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with overhead_alloc as (
    select coalesce(sum(a.amount),0) as amt
    from public.expense_allocations a
    join public.expenses e on e.id = a.expense_id
    where e.org_id = p_org_id
      and e.expense_date = p_day
      and upper(a.cost_center_code) = 'OVERHEAD'
  ),
  unallocated as (
    select coalesce(sum(e.amount),0) as amt
    from public.expenses e
    where e.org_id = p_org_id
      and e.expense_date = p_day
      and not exists (select 1 from public.expense_allocations a where a.expense_id = e.id)
  )
  select (select amt from overhead_alloc) + (select amt from unallocated);
$$;


ALTER FUNCTION "public"."overhead_daily"("p_org_id" "uuid", "p_day" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_add_admin"("p_user_id" "uuid", "p_email" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  insert into public.platform_admins(user_id, email)
  values (p_user_id, p_email)
  on conflict (user_id) do update set email = excluded.email;

  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION "public"."platform_add_admin"("p_user_id" "uuid", "p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_add_member"("p_org_id" "uuid", "p_user_email" "text" DEFAULT NULL::"text", "p_user_id" "uuid" DEFAULT NULL::"uuid", "p_is_admin" boolean DEFAULT false, "p_status" "text" DEFAULT 'pending'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare
  v_user uuid;
  v_role public.org_role;
  v_status text := coalesce(nullif(p_status,''),'pending');
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if v_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Invalid status %', v_status;
  end if;

  v_user := p_user_id;
  if v_user is null then
    v_user := public.platform_find_user_id(p_user_email);
  end if;

  if p_is_admin then
    v_role := public.safe_org_role('admin');
    if v_role is null then
      raise exception 'org_role enum has no label "admin"';
    end if;
  else
    v_role := public.default_org_member_role();
  end if;

  insert into public.org_members(org_id, user_id, role, status, approved_at, approved_by)
  values (
    p_org_id,
    v_user,
    v_role,
    v_status,
    case when v_status='approved' then now() else null end,
    case when v_status='approved' then auth.uid() else null end
  )
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        status = excluded.status,
        approved_at = excluded.approved_at,
        approved_by = excluded.approved_by;

  return jsonb_build_object('ok', true, 'org_id', p_org_id, 'user_id', v_user, 'status', v_status, 'role', v_role::text);
end $$;


ALTER FUNCTION "public"."platform_add_member"("p_org_id" "uuid", "p_user_email" "text", "p_user_id" "uuid", "p_is_admin" boolean, "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_create_org"("p_name" "text", "p_tier_code" "text" DEFAULT 'free'::"text", "p_is_listed" boolean DEFAULT false, "p_owner_email" "text" DEFAULT NULL::"text", "p_owner_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare
  v_org uuid;
  v_owner uuid;
  v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_name is null or length(trim(p_name))=0 then
    raise exception 'Org name required';
  end if;

  v_owner := p_owner_user_id;
  if v_owner is null and p_owner_email is not null and length(trim(p_owner_email))>0 then
    v_owner := public.platform_find_user_id(p_owner_email);
  end if;

  insert into public.orgs(name, subscription_tier_code, is_listed)
  values (trim(p_name), coalesce(nullif(p_tier_code,''),'free'), coalesce(p_is_listed,false))
  returning id into v_org;

  -- Assign owner membership if provided (approved)
  if v_owner is not null then
    v_role := coalesce(
      public.safe_org_role('super_admin'),
      public.safe_org_role('admin'),
      public.default_org_member_role()
    );

    insert into public.org_members(org_id, user_id, role, status, approved_at, approved_by)
    values (v_org, v_owner, v_role, 'approved', now(), auth.uid())
    on conflict (org_id, user_id) do update
      set status='approved',
          role=excluded.role,
          approved_at=now(),
          approved_by=auth.uid();
  end if;

  return jsonb_build_object('ok', true, 'org_id', v_org, 'owner_user_id', v_owner);
end $$;


ALTER FUNCTION "public"."platform_create_org"("p_name" "text", "p_tier_code" "text", "p_is_listed" boolean, "p_owner_email" "text", "p_owner_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_find_user_id"("p_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare v uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_email is null or length(trim(p_email))=0 then
    return null;
  end if;

  select u.id into v
  from auth.users u
  where lower(u.email) = lower(trim(p_email))
  order by u.created_at asc
  limit 1;

  if v is null then
    raise exception 'User not found for email=%', p_email;
  end if;

  return v;
end $$;


ALTER FUNCTION "public"."platform_find_user_id"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_list_org_members"("p_org_id" "uuid") RETURNS TABLE("user_id" "uuid", "email" "text", "role" "text", "status" "text", "requested_at" timestamp with time zone, "approved_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
  select
    m.user_id,
    coalesce(p.email, u.email) as email,
    m.role::text as role,
    m.status,
    m.created_at as requested_at,
    m.approved_at
  from public.org_members m
  left join public.profiles p on p.user_id = m.user_id
  left join auth.users u on u.id = m.user_id
  where public.is_platform_admin()
    and m.org_id = p_org_id
  order by m.created_at asc;
$$;


ALTER FUNCTION "public"."platform_list_org_members"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_list_orgs"("p_limit" integer DEFAULT 200) RETURNS TABLE("org_id" "uuid", "name" "text", "subscription_tier_code" "text", "is_listed" boolean, "branch_count" integer, "support_email" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    o.id,
    o.name,
    o.subscription_tier_code,
    o.is_listed,
    (select count(*) from public.branches b where b.org_id = o.id)::int as branch_count,
    coalesce(o.support_email, (select support_email from public.platform_settings where id=1)) as support_email,
    o.created_at
  from public.orgs o
  where public.is_platform_admin()
  order by o.created_at desc
  limit greatest(1, least(p_limit, 2000));
$$;


ALTER FUNCTION "public"."platform_list_orgs"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_list_pending_members"("p_limit" integer DEFAULT 100) RETURNS TABLE("org_id" "uuid", "org_name" "text", "user_id" "uuid", "user_email" "text", "role" "text", "requested_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    o.id,
    o.name,
    m.user_id,
    p.email,
    m.role,
    m.created_at as requested_at
  from public.org_members m
  join public.orgs o on o.id = m.org_id
  left join public.profiles p on p.user_id = m.user_id
  where public.is_platform_admin()
    and m.status = 'pending'
  order by m.created_at asc
  limit greatest(1, least(p_limit, 500));
$$;


ALTER FUNCTION "public"."platform_list_pending_members"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_remove_member"("p_org_id" "uuid", "p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  delete from public.org_members
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION "public"."platform_remove_member"("p_org_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_set_member_admin"("p_org_id" "uuid", "p_user_id" "uuid", "p_is_admin" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_is_admin then
    v_role := public.safe_org_role('admin');
    if v_role is null then
      raise exception 'org_role enum has no label "admin"';
    end if;
  else
    v_role := public.default_org_member_role();
  end if;

  update public.org_members
  set role = v_role
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true, 'role', v_role::text);
end $$;


ALTER FUNCTION "public"."platform_set_member_admin"("p_org_id" "uuid", "p_user_id" "uuid", "p_is_admin" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_set_member_status"("p_org_id" "uuid", "p_user_id" "uuid", "p_status" "text", "p_role" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role public.org_role;
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  if p_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Invalid status: %', p_status;
  end if;

  if p_status = 'approved' then
    v_role := coalesce(public.safe_org_role(p_role), public.default_org_member_role());
  else
    v_role := public.safe_org_role(p_role);
  end if;

  update public.org_members
  set
    status = p_status,
    role = coalesce(v_role, role)
  where org_id = p_org_id and user_id = p_user_id;

  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION "public"."platform_set_member_status"("p_org_id" "uuid", "p_user_id" "uuid", "p_status" "text", "p_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_set_org_tier"("p_org_id" "uuid", "p_tier_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  update public.orgs
  set subscription_tier_code = p_tier_code
  where id = p_org_id;

  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION "public"."platform_set_org_tier"("p_org_id" "uuid", "p_tier_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."platform_update_org"("p_org_id" "uuid", "p_tier_code" "text", "p_is_listed" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_platform_admin() then
    raise exception 'Forbidden';
  end if;

  update public.orgs
  set
    subscription_tier_code = p_tier_code,
    is_listed = p_is_listed
  where id = p_org_id;

  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION "public"."platform_update_org"("p_org_id" "uuid", "p_tier_code" "text", "p_is_listed" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."preview_expense_allocation"("p_expense_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_exp public.expenses;
  v_alloc numeric;
begin
  select * into v_exp from public.expenses where id=p_expense_id;
  if not found then raise exception 'Expense not found'; end if;

  if not public.is_org_member(v_exp.org_id) then raise exception 'Forbidden'; end if;

  select coalesce(sum(amount),0) into v_alloc
  from public.expense_allocations
  where expense_id=p_expense_id;

  return jsonb_build_object(
    'expense_id', p_expense_id,
    'expense_amount', v_exp.amount,
    'allocated_amount', v_alloc,
    'unallocated_amount', greatest(v_exp.amount - v_alloc, 0),
    'status', case
      when v_alloc = 0 then 'unallocated'
      when abs(v_alloc - v_exp.amount) <= 0.01 then 'allocated'
      else 'partial'
    end
  );
end $$;


ALTER FUNCTION "public"."preview_expense_allocation"("p_expense_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_org_access"("p_org_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user uuid := auth.uid();
  v_role public.org_role;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  v_role := public.default_org_member_role();

  insert into public.org_members(org_id, user_id, role, status)
  values (p_org_id, v_user, v_role, 'pending')
  on conflict (org_id, user_id) do update
    set status = 'pending',
        role = excluded.role;

  return jsonb_build_object('ok', true, 'org_id', p_org_id);
end $$;


ALTER FUNCTION "public"."request_org_access"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."safe_org_role"("p" "text") RETURNS "public"."org_role"
    LANGUAGE "plpgsql" IMMUTABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_catalog'
    AS $$
declare v public.org_role;
begin
  if p is null or length(trim(p)) = 0 then
    return null;
  end if;

  if exists (
    select 1
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    where t.typname = 'org_role'
      and e.enumlabel = p
  ) then
    execute format('select %L::public.org_role', p) into v;
    return v;
  end if;

  return null;
end $$;


ALTER FUNCTION "public"."safe_org_role"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_import_job_mapping"("p_job_id" "uuid", "p_mapping" "jsonb") RETURNS "public"."import_jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_job public.import_jobs;
  v_org_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select org_id into v_org_id
  from public.import_jobs
  where id = p_job_id;

  if v_org_id is null then
    raise exception 'not_found';
  end if;

  if not public.is_org_member(v_org_id) then
    raise exception 'not_authorized';
  end if;

  update public.import_jobs
  set metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{mapping}', coalesce(p_mapping, '{}'::jsonb), true),
      updated_at = now()
  where id = p_job_id
  returning * into v_job;

  return v_job;
end;
$$;


ALTER FUNCTION "public"."save_import_job_mapping"("p_job_id" "uuid", "p_mapping" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seed_cost_engine_demo"("p_org_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  a date;
  beans uuid; milk uuid; cup uuid; lid uuid;
  rv_esp uuid; rv_lat uuid;
begin
  if not public.is_org_member(p_org_id) then raise exception 'Forbidden'; end if;

  -- Align seed dates to your real sales/expense dates
  a := public.org_anchor_date(p_org_id);

  insert into public.ingredients(org_id, ingredient_code, name, kind, base_uom)
  values
    (p_org_id,'BEANS','Coffee Beans','material','g'),
    (p_org_id,'MILK','Milk','material','ml'),
    (p_org_id,'CUP12','Cup 12oz','packaging','unit'),
    (p_org_id,'LID','Lid','packaging','unit')
  on conflict (org_id, ingredient_code) do update
    set name=excluded.name, kind=excluded.kind, base_uom=excluded.base_uom;

  select id into beans from public.ingredients where org_id=p_org_id and ingredient_code='BEANS';
  select id into milk  from public.ingredients where org_id=p_org_id and ingredient_code='MILK';
  select id into cup   from public.ingredients where org_id=p_org_id and ingredient_code='CUP12';
  select id into lid   from public.ingredients where org_id=p_org_id and ingredient_code='LID';

  delete from public.ingredient_receipts where org_id=p_org_id and vendor='SeedVendor';

  insert into public.ingredient_receipts(org_id, ingredient_id, receipt_date, qty_base, total_cost, currency, vendor)
  select p_org_id, ing_id, (a - (n||' days')::interval)::date, qty_base, total_cost, 'SAR', 'SeedVendor'
  from (
    select beans as ing_id, 10000::numeric as qty_base, 1200::numeric as total_cost
    union all select milk, 20000, 900
    union all select cup, 500, 250
    union all select lid, 500, 180
  ) base
  cross join generate_series(0,60,15) n;

  insert into public.recipe_versions(org_id, sku, effective_start, yield_qty, notes)
  values
    (p_org_id,'ESP-SGL', (a - interval '365 days')::date, 10, 'DEMO'),
    (p_org_id,'LAT-LRG', (a - interval '365 days')::date, 10, 'DEMO')
  on conflict (org_id, sku, effective_start) do update
    set yield_qty=excluded.yield_qty, notes=excluded.notes;

  select id into rv_esp from public.recipe_versions where org_id=p_org_id and sku='ESP-SGL' order by effective_start desc limit 1;
  select id into rv_lat from public.recipe_versions where org_id=p_org_id and sku='LAT-LRG' order by effective_start desc limit 1;

  insert into public.recipe_items(recipe_version_id, ingredient_id, qty, uom, loss_pct)
  values
    (rv_esp, beans, 180, 'g', 0.02),
    (rv_lat, beans, 160, 'g', 0.02)
  on conflict (recipe_version_id, ingredient_id) do update set qty=excluded.qty, loss_pct=excluded.loss_pct;

  insert into public.recipe_items(recipe_version_id, ingredient_id, qty, uom, loss_pct)
  values (rv_lat, milk, 2500, 'ml', 0.01)
  on conflict (recipe_version_id, ingredient_id) do update set qty=excluded.qty, loss_pct=excluded.loss_pct;

  insert into public.product_packaging_items(org_id, sku, ingredient_id, qty, uom)
  values
    (p_org_id,'ESP-SGL', cup, 1, 'unit'),
    (p_org_id,'ESP-SGL', lid, 1, 'unit'),
    (p_org_id,'LAT-LRG', cup, 1, 'unit'),
    (p_org_id,'LAT-LRG', lid, 1, 'unit')
  on conflict (org_id, sku, ingredient_id) do update set qty=excluded.qty;

  insert into public.labor_rates(org_id, role_code, effective_start, hourly_rate, burden_pct)
  values (p_org_id,'BARISTA', (a - interval '365 days')::date, 22.0, 0.25)
  on conflict (org_id, role_code, effective_start) do update
    set hourly_rate=excluded.hourly_rate, burden_pct=excluded.burden_pct;

  insert into public.product_labor_specs(org_id, sku, role_code, seconds_per_unit)
  values
    (p_org_id,'ESP-SGL','BARISTA', 35),
    (p_org_id,'LAT-LRG','BARISTA', 75)
  on conflict (org_id, sku, role_code) do update set seconds_per_unit=excluded.seconds_per_unit;

  insert into public.org_cost_engine_settings(org_id) values (p_org_id)
  on conflict (org_id) do nothing;

  return jsonb_build_object('ok', true, 'seeded', true, 'anchor_date', a);
end $$;


ALTER FUNCTION "public"."seed_cost_engine_demo"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."select_loaded_hourly_rate"("p_org_id" "uuid", "p_role_code" "text", "p_as_of" "date") RETURNS numeric
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select lr.hourly_rate * (1 + lr.burden_pct)
  from public.labor_rates lr
  where lr.org_id = p_org_id
    and lr.role_code = p_role_code
    and lr.effective_start <= p_as_of
  order by lr.effective_start desc
  limit 1;
$$;


ALTER FUNCTION "public"."select_loaded_hourly_rate"("p_org_id" "uuid", "p_role_code" "text", "p_as_of" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."select_recipe_version_id"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select rv.id
  from public.recipe_versions rv
  where rv.org_id = p_org_id
    and rv.sku = p_sku
    and rv.effective_start <= p_as_of
    and (rv.effective_end is null or rv.effective_end > p_as_of)
  order by rv.effective_start desc
  limit 1;
$$;


ALTER FUNCTION "public"."select_recipe_version_id"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end $$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_import_job"("p_job_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_job public.import_jobs;
  v_res jsonb;
  v_cost jsonb;
  w int;
begin
  select * into v_job from public.import_jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;

  if v_job.entity_type='products' then
    return public.import_products_from_staging(p_job_id);
  elsif v_job.entity_type='sales' then
    v_res := public.import_sales_from_staging(p_job_id);

    select coalesce(s.wac_days,30) into w
    from public.org_cost_engine_settings s
    where s.org_id = v_job.org_id;

    v_cost := public.apply_unit_economics_to_sales_job(p_job_id, w);
    return v_res || jsonb_build_object('unit_economics', v_cost);
  elsif v_job.entity_type='expenses' then
    v_res := public.import_expenses_from_staging(p_job_id);
    perform public.auto_allocate_expenses_for_job(p_job_id);
    return v_res;
  else
    raise exception 'Import not implemented for entity_type=% yet', v_job.entity_type;
  end if;
end $$;


ALTER FUNCTION "public"."start_import_job"("p_job_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."suggest_expense_allocations"("p_expense_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."suggest_expense_allocations"("p_expense_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."to_base_qty"("p_qty" numeric, "p_uom" "text", "p_base_uom" "text") RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
declare u text := lower(trim(p_uom));
declare b text := lower(trim(p_base_uom));
begin
  if p_qty is null then return null; end if;
  if u = b then return p_qty; end if;

  if b='g' then
    if u='kg' then return p_qty * 1000;
    elsif u='mg' then return p_qty / 1000;
    end if;
  elsif b='ml' then
    if u='l' then return p_qty * 1000;
    end if;
  elsif b='unit' then
    if u in ('pcs','piece','pieces','unit') then return p_qty;
    end if;
  end if;

  raise exception 'Unsupported uom conversion: qty=% uom=% base=%', p_qty, p_uom, p_base_uom;
end $$;


ALTER FUNCTION "public"."to_base_qty"("p_qty" numeric, "p_uom" "text", "p_base_uom" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_enforce_branch_limit"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_max int;
  v_cnt int;
begin
  if public.is_platform_admin() then
    return new;
  end if;

  select t.max_branches into v_max
  from public.orgs o
  join public.subscription_tiers t on t.tier_code = o.subscription_tier_code
  where o.id = new.org_id;

  if v_max is null then
    v_max := 1;
  end if;

  select count(*) into v_cnt
  from public.branches
  where org_id = new.org_id;

  if v_cnt >= v_max then
    raise exception 'Branch limit exceeded (max_branches=%)', v_max;
  end if;

  return new;
end $$;


ALTER FUNCTION "public"."trg_enforce_branch_limit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_org_members_status_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status then
      if not public.is_platform_admin() then
        raise exception 'Only platform admin can approve/reject/suspend members';
      end if;

      if new.status = 'approved' then
        new.approved_at := now();
        new.approved_by := auth.uid();
      end if;
    end if;
  end if;

  return new;
end $$;


ALTER FUNCTION "public"."trg_org_members_status_guard"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end $$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."wac_unit_cost"("p_org_id" "uuid", "p_ingredient_id" "uuid", "p_as_of" "date", "p_window_days" integer DEFAULT 30) RETURNS numeric
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  w int := greatest(1, least(p_window_days, 365));
  ws date := p_as_of - (w - 1);
  sum_qty numeric;
  sum_cost numeric;
  last_qty numeric;
  last_cost numeric;
begin
  select coalesce(sum(qty_base),0), coalesce(sum(total_cost),0)
    into sum_qty, sum_cost
  from public.ingredient_receipts
  where org_id=p_org_id and ingredient_id=p_ingredient_id
    and receipt_date between ws and p_as_of;

  if sum_qty > 0 then
    return sum_cost / sum_qty;
  end if;

  select qty_base, total_cost
    into last_qty, last_cost
  from public.ingredient_receipts
  where org_id=p_org_id and ingredient_id=p_ingredient_id
    and receipt_date <= p_as_of
  order by receipt_date desc
  limit 1;

  if last_qty is not null and last_qty > 0 then
    return last_cost / last_qty;
  end if;

  return null;
end $$;


ALTER FUNCTION "public"."wac_unit_cost"("p_org_id" "uuid", "p_ingredient_id" "uuid", "p_as_of" "date", "p_window_days" integer) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expense_allocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "expense_id" "uuid" NOT NULL,
    "org_id" "uuid" NOT NULL,
    "cost_center_code" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "expense_allocations_amount_check" CHECK (("amount" >= (0)::numeric))
);


ALTER TABLE "public"."expense_allocations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "branch_id" "uuid",
    "expense_date" "date" NOT NULL,
    "reference_number" "text",
    "vendor" "text",
    "cost_center_code" "text",
    "category" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "vat_rate" numeric,
    "tax_amount" numeric,
    "total_amount" numeric,
    "payment_method" "text",
    "notes" "text",
    "currency" "text",
    "source_import_job_id" "uuid",
    "source_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."expenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "branch_id" "uuid",
    "invoice_date" "date" NOT NULL,
    "external_invoice_number" "text" NOT NULL,
    "invoice_type" "text",
    "channel" "text",
    "payment_method" "text",
    "currency" "text",
    "source_import_job_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sales_invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "line_number" integer NOT NULL,
    "sku" "text",
    "product_name" "text" NOT NULL,
    "category" "text",
    "quantity" numeric DEFAULT 1 NOT NULL,
    "unit_price" numeric,
    "discount_rate" numeric,
    "net_sales" numeric NOT NULL,
    "vat_rate" numeric,
    "tax_amount" numeric,
    "total_amount" numeric,
    "currency" "text",
    "source_import_job_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cogs_material" numeric DEFAULT 0 NOT NULL,
    "cogs_packaging" numeric DEFAULT 0 NOT NULL,
    "cogs_labor" numeric DEFAULT 0 NOT NULL,
    "cogs_overhead" numeric DEFAULT 0 NOT NULL,
    "cogs_total" numeric DEFAULT 0 NOT NULL,
    "cogs_model" "text" DEFAULT 'none'::"text" NOT NULL,
    "cogs_status" "text" DEFAULT 'uncomputed'::"text" NOT NULL,
    "cogs_missing" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "recipe_version_id" "uuid",
    CONSTRAINT "sales_items_line_number_check" CHECK (("line_number" >= 1))
);


ALTER TABLE "public"."sales_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "auth"."audit_log_entries" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "payload" json,
    "created_at" timestamp with time zone,
    "ip_address" character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE "auth"."audit_log_entries" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."audit_log_entries" IS 'Auth: Audit trail for user actions.';



CREATE TABLE IF NOT EXISTS "auth"."custom_oauth_providers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "provider_type" "text" NOT NULL,
    "identifier" "text" NOT NULL,
    "name" "text" NOT NULL,
    "client_id" "text" NOT NULL,
    "client_secret" "text" NOT NULL,
    "acceptable_client_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "scopes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "pkce_enabled" boolean DEFAULT true NOT NULL,
    "attribute_mapping" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "authorization_params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "email_optional" boolean DEFAULT false NOT NULL,
    "issuer" "text",
    "discovery_url" "text",
    "skip_nonce_check" boolean DEFAULT false NOT NULL,
    "cached_discovery" "jsonb",
    "discovery_cached_at" timestamp with time zone,
    "authorization_url" "text",
    "token_url" "text",
    "userinfo_url" "text",
    "jwks_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "custom_oauth_providers_authorization_url_https" CHECK ((("authorization_url" IS NULL) OR ("authorization_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_authorization_url_length" CHECK ((("authorization_url" IS NULL) OR ("char_length"("authorization_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_client_id_length" CHECK ((("char_length"("client_id") >= 1) AND ("char_length"("client_id") <= 512))),
    CONSTRAINT "custom_oauth_providers_discovery_url_length" CHECK ((("discovery_url" IS NULL) OR ("char_length"("discovery_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_identifier_format" CHECK (("identifier" ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::"text")),
    CONSTRAINT "custom_oauth_providers_issuer_length" CHECK ((("issuer" IS NULL) OR (("char_length"("issuer") >= 1) AND ("char_length"("issuer") <= 2048)))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_https" CHECK ((("jwks_uri" IS NULL) OR ("jwks_uri" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_length" CHECK ((("jwks_uri" IS NULL) OR ("char_length"("jwks_uri") <= 2048))),
    CONSTRAINT "custom_oauth_providers_name_length" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 100))),
    CONSTRAINT "custom_oauth_providers_oauth2_requires_endpoints" CHECK ((("provider_type" <> 'oauth2'::"text") OR (("authorization_url" IS NOT NULL) AND ("token_url" IS NOT NULL) AND ("userinfo_url" IS NOT NULL)))),
    CONSTRAINT "custom_oauth_providers_oidc_discovery_url_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("discovery_url" IS NULL) OR ("discovery_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_issuer_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NULL) OR ("issuer" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_requires_issuer" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NOT NULL))),
    CONSTRAINT "custom_oauth_providers_provider_type_check" CHECK (("provider_type" = ANY (ARRAY['oauth2'::"text", 'oidc'::"text"]))),
    CONSTRAINT "custom_oauth_providers_token_url_https" CHECK ((("token_url" IS NULL) OR ("token_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_token_url_length" CHECK ((("token_url" IS NULL) OR ("char_length"("token_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_https" CHECK ((("userinfo_url" IS NULL) OR ("userinfo_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_length" CHECK ((("userinfo_url" IS NULL) OR ("char_length"("userinfo_url") <= 2048)))
);


ALTER TABLE "auth"."custom_oauth_providers" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."flow_state" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "auth_code" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "code_challenge" "text",
    "provider_type" "text" NOT NULL,
    "provider_access_token" "text",
    "provider_refresh_token" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "authentication_method" "text" NOT NULL,
    "auth_code_issued_at" timestamp with time zone,
    "invite_token" "text",
    "referrer" "text",
    "oauth_client_state_id" "uuid",
    "linking_target_id" "uuid",
    "email_optional" boolean DEFAULT false NOT NULL
);


ALTER TABLE "auth"."flow_state" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."flow_state" IS 'Stores metadata for all OAuth/SSO login flows';



CREATE TABLE IF NOT EXISTS "auth"."identities" (
    "provider_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "identity_data" "jsonb" NOT NULL,
    "provider" "text" NOT NULL,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" "text" GENERATED ALWAYS AS ("lower"(("identity_data" ->> 'email'::"text"))) STORED,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "auth"."identities" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."identities" IS 'Auth: Stores identities associated to a user.';



COMMENT ON COLUMN "auth"."identities"."email" IS 'Auth: Email is a generated column that references the optional email property in the identity_data';



CREATE TABLE IF NOT EXISTS "auth"."instances" (
    "id" "uuid" NOT NULL,
    "uuid" "uuid",
    "raw_base_config" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "auth"."instances" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."instances" IS 'Auth: Manages users across multiple sites.';



CREATE TABLE IF NOT EXISTS "auth"."mfa_amr_claims" (
    "session_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "authentication_method" "text" NOT NULL,
    "id" "uuid" NOT NULL
);


ALTER TABLE "auth"."mfa_amr_claims" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_amr_claims" IS 'auth: stores authenticator method reference claims for multi factor authentication';



CREATE TABLE IF NOT EXISTS "auth"."mfa_challenges" (
    "id" "uuid" NOT NULL,
    "factor_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "verified_at" timestamp with time zone,
    "ip_address" "inet" NOT NULL,
    "otp_code" "text",
    "web_authn_session_data" "jsonb"
);


ALTER TABLE "auth"."mfa_challenges" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_challenges" IS 'auth: stores metadata about challenge requests made';



CREATE TABLE IF NOT EXISTS "auth"."mfa_factors" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "friendly_name" "text",
    "factor_type" "auth"."factor_type" NOT NULL,
    "status" "auth"."factor_status" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "secret" "text",
    "phone" "text",
    "last_challenged_at" timestamp with time zone,
    "web_authn_credential" "jsonb",
    "web_authn_aaguid" "uuid",
    "last_webauthn_challenge_data" "jsonb"
);


ALTER TABLE "auth"."mfa_factors" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_factors" IS 'auth: stores metadata about factors';



COMMENT ON COLUMN "auth"."mfa_factors"."last_webauthn_challenge_data" IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';



CREATE TABLE IF NOT EXISTS "auth"."oauth_authorizations" (
    "id" "uuid" NOT NULL,
    "authorization_id" "text" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "redirect_uri" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "state" "text",
    "resource" "text",
    "code_challenge" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "response_type" "auth"."oauth_response_type" DEFAULT 'code'::"auth"."oauth_response_type" NOT NULL,
    "status" "auth"."oauth_authorization_status" DEFAULT 'pending'::"auth"."oauth_authorization_status" NOT NULL,
    "authorization_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '00:03:00'::interval) NOT NULL,
    "approved_at" timestamp with time zone,
    "nonce" "text",
    CONSTRAINT "oauth_authorizations_authorization_code_length" CHECK (("char_length"("authorization_code") <= 255)),
    CONSTRAINT "oauth_authorizations_code_challenge_length" CHECK (("char_length"("code_challenge") <= 128)),
    CONSTRAINT "oauth_authorizations_expires_at_future" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "oauth_authorizations_nonce_length" CHECK (("char_length"("nonce") <= 255)),
    CONSTRAINT "oauth_authorizations_redirect_uri_length" CHECK (("char_length"("redirect_uri") <= 2048)),
    CONSTRAINT "oauth_authorizations_resource_length" CHECK (("char_length"("resource") <= 2048)),
    CONSTRAINT "oauth_authorizations_scope_length" CHECK (("char_length"("scope") <= 4096)),
    CONSTRAINT "oauth_authorizations_state_length" CHECK (("char_length"("state") <= 4096))
);


ALTER TABLE "auth"."oauth_authorizations" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_client_states" (
    "id" "uuid" NOT NULL,
    "provider_type" "text" NOT NULL,
    "code_verifier" "text",
    "created_at" timestamp with time zone NOT NULL
);


ALTER TABLE "auth"."oauth_client_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."oauth_client_states" IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';



CREATE TABLE IF NOT EXISTS "auth"."oauth_clients" (
    "id" "uuid" NOT NULL,
    "client_secret_hash" "text",
    "registration_type" "auth"."oauth_registration_type" NOT NULL,
    "redirect_uris" "text" NOT NULL,
    "grant_types" "text" NOT NULL,
    "client_name" "text",
    "client_uri" "text",
    "logo_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "client_type" "auth"."oauth_client_type" DEFAULT 'confidential'::"auth"."oauth_client_type" NOT NULL,
    "token_endpoint_auth_method" "text" NOT NULL,
    CONSTRAINT "oauth_clients_client_name_length" CHECK (("char_length"("client_name") <= 1024)),
    CONSTRAINT "oauth_clients_client_uri_length" CHECK (("char_length"("client_uri") <= 2048)),
    CONSTRAINT "oauth_clients_logo_uri_length" CHECK (("char_length"("logo_uri") <= 2048)),
    CONSTRAINT "oauth_clients_token_endpoint_auth_method_check" CHECK (("token_endpoint_auth_method" = ANY (ARRAY['client_secret_basic'::"text", 'client_secret_post'::"text", 'none'::"text"])))
);


ALTER TABLE "auth"."oauth_clients" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_consents" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "scopes" "text" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "oauth_consents_revoked_after_granted" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "granted_at"))),
    CONSTRAINT "oauth_consents_scopes_length" CHECK (("char_length"("scopes") <= 2048)),
    CONSTRAINT "oauth_consents_scopes_not_empty" CHECK (("char_length"(TRIM(BOTH FROM "scopes")) > 0))
);


ALTER TABLE "auth"."oauth_consents" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."one_time_tokens" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_type" "auth"."one_time_token_type" NOT NULL,
    "token_hash" "text" NOT NULL,
    "relates_to" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "one_time_tokens_token_hash_check" CHECK (("char_length"("token_hash") > 0))
);


ALTER TABLE "auth"."one_time_tokens" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
    "instance_id" "uuid",
    "id" bigint NOT NULL,
    "token" character varying(255),
    "user_id" character varying(255),
    "revoked" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "parent" character varying(255),
    "session_id" "uuid"
);


ALTER TABLE "auth"."refresh_tokens" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."refresh_tokens" IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';



CREATE SEQUENCE IF NOT EXISTS "auth"."refresh_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNER TO "supabase_auth_admin";


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNED BY "auth"."refresh_tokens"."id";



CREATE TABLE IF NOT EXISTS "auth"."saml_providers" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "entity_id" "text" NOT NULL,
    "metadata_xml" "text" NOT NULL,
    "metadata_url" "text",
    "attribute_mapping" "jsonb",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "name_id_format" "text",
    CONSTRAINT "entity_id not empty" CHECK (("char_length"("entity_id") > 0)),
    CONSTRAINT "metadata_url not empty" CHECK ((("metadata_url" = NULL::"text") OR ("char_length"("metadata_url") > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK (("char_length"("metadata_xml") > 0))
);


ALTER TABLE "auth"."saml_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_providers" IS 'Auth: Manages SAML Identity Provider connections.';



CREATE TABLE IF NOT EXISTS "auth"."saml_relay_states" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "request_id" "text" NOT NULL,
    "for_email" "text",
    "redirect_to" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "flow_state_id" "uuid",
    CONSTRAINT "request_id not empty" CHECK (("char_length"("request_id") > 0))
);


ALTER TABLE "auth"."saml_relay_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_relay_states" IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';



CREATE TABLE IF NOT EXISTS "auth"."schema_migrations" (
    "version" character varying(255) NOT NULL
);


ALTER TABLE "auth"."schema_migrations" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."schema_migrations" IS 'Auth: Manages updates to the auth system.';



CREATE TABLE IF NOT EXISTS "auth"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "factor_id" "uuid",
    "aal" "auth"."aal_level",
    "not_after" timestamp with time zone,
    "refreshed_at" timestamp without time zone,
    "user_agent" "text",
    "ip" "inet",
    "tag" "text",
    "oauth_client_id" "uuid",
    "refresh_token_hmac_key" "text",
    "refresh_token_counter" bigint,
    "scopes" "text",
    CONSTRAINT "sessions_scopes_length" CHECK (("char_length"("scopes") <= 4096))
);


ALTER TABLE "auth"."sessions" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sessions" IS 'Auth: Stores session data associated to a user.';



COMMENT ON COLUMN "auth"."sessions"."not_after" IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_hmac_key" IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_counter" IS 'Holds the ID (counter) of the last issued refresh token.';



CREATE TABLE IF NOT EXISTS "auth"."sso_domains" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "domain" "text" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK (("char_length"("domain") > 0))
);


ALTER TABLE "auth"."sso_domains" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_domains" IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';



CREATE TABLE IF NOT EXISTS "auth"."sso_providers" (
    "id" "uuid" NOT NULL,
    "resource_id" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "disabled" boolean,
    CONSTRAINT "resource_id not empty" CHECK ((("resource_id" = NULL::"text") OR ("char_length"("resource_id") > 0)))
);


ALTER TABLE "auth"."sso_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_providers" IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';



COMMENT ON COLUMN "auth"."sso_providers"."resource_id" IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';



CREATE TABLE IF NOT EXISTS "auth"."users" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" "jsonb",
    "raw_user_meta_data" "jsonb",
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" "text" DEFAULT NULL::character varying,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" "text" DEFAULT ''::character varying,
    "phone_change_token" character varying(255) DEFAULT ''::character varying,
    "phone_change_sent_at" timestamp with time zone,
    "confirmed_at" timestamp with time zone GENERATED ALWAYS AS (LEAST("email_confirmed_at", "phone_confirmed_at")) STORED,
    "email_change_token_current" character varying(255) DEFAULT ''::character varying,
    "email_change_confirm_status" smallint DEFAULT 0,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255) DEFAULT ''::character varying,
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "is_anonymous" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_email_change_confirm_status_check" CHECK ((("email_change_confirm_status" >= 0) AND ("email_change_confirm_status" <= 2)))
);


ALTER TABLE "auth"."users" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."users" IS 'Auth: Stores user login data within a secure schema.';



COMMENT ON COLUMN "auth"."users"."is_sso_user" IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';



CREATE TABLE IF NOT EXISTS "public"."branches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "code" "text",
    CONSTRAINT "branches_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120)))
);


ALTER TABLE "public"."branches" OWNER TO "postgres";


COMMENT ON TABLE "public"."branches" IS 'Physical branches/locations of the org.';



CREATE TABLE IF NOT EXISTS "public"."cost_centers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "code" "text" NOT NULL,
    "is_system" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cost_centers_code_check" CHECK ((("char_length"("code") >= 1) AND ("char_length"("code") <= 64))),
    CONSTRAINT "cost_centers_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120)))
);


ALTER TABLE "public"."cost_centers" OWNER TO "postgres";


COMMENT ON TABLE "public"."cost_centers" IS 'Cost centers used for overhead allocation.';



CREATE TABLE IF NOT EXISTS "public"."expense_allocation_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "expense_id" "uuid" NOT NULL,
    "org_id" "uuid" NOT NULL,
    "changed_by" "uuid",
    "previous_allocations" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "new_allocations" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."expense_allocation_audit" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."forecast_outputs" (
    "id" bigint NOT NULL,
    "run_id" "uuid" NOT NULL,
    "org_id" "uuid" NOT NULL,
    "day" "date" NOT NULL,
    "p50_net_sales" numeric NOT NULL,
    "p80_low" numeric NOT NULL,
    "p80_high" numeric NOT NULL,
    "p95_low" numeric NOT NULL,
    "p95_high" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."forecast_outputs" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."forecast_outputs_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."forecast_outputs_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."forecast_outputs_id_seq" OWNED BY "public"."forecast_outputs"."id";



CREATE TABLE IF NOT EXISTS "public"."forecast_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "model" "text" DEFAULT 'hsar_ridge_v1'::"text" NOT NULL,
    "horizon_days" integer DEFAULT 30 NOT NULL,
    "history_days" integer DEFAULT 365 NOT NULL,
    "anchor_date" "date" NOT NULL,
    "status" "text" NOT NULL,
    "metrics" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone,
    "branch_id" "uuid",
    CONSTRAINT "forecast_runs_history_days_check" CHECK ((("history_days" >= 30) AND ("history_days" <= 3650))),
    CONSTRAINT "forecast_runs_horizon_days_check" CHECK ((("horizon_days" >= 1) AND ("horizon_days" <= 365))),
    CONSTRAINT "forecast_runs_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'running'::"text", 'succeeded'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."forecast_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."import_contract_fields" (
    "entity_type" "public"."import_entity" NOT NULL,
    "canonical_key" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "is_required" boolean DEFAULT false NOT NULL,
    "ordinal" integer DEFAULT 1000 NOT NULL,
    CONSTRAINT "import_contract_fields_data_type_check" CHECK (("data_type" = ANY (ARRAY['text'::"text", 'number'::"text", 'date'::"text", 'boolean'::"text"])))
);


ALTER TABLE "public"."import_contract_fields" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."import_job_rows_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."import_job_rows_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."import_job_rows_id_seq" OWNED BY "public"."import_job_rows"."id";



CREATE TABLE IF NOT EXISTS "public"."ingredient_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "ingredient_id" "uuid" NOT NULL,
    "receipt_date" "date" NOT NULL,
    "qty_base" numeric NOT NULL,
    "total_cost" numeric NOT NULL,
    "currency" "text",
    "vendor" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ingredient_receipts_qty_base_check" CHECK (("qty_base" > (0)::numeric)),
    CONSTRAINT "ingredient_receipts_total_cost_check" CHECK (("total_cost" >= (0)::numeric))
);


ALTER TABLE "public"."ingredient_receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ingredients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "ingredient_code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "base_uom" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ingredients_base_uom_check" CHECK (("base_uom" = ANY (ARRAY['g'::"text", 'ml'::"text", 'unit'::"text"]))),
    CONSTRAINT "ingredients_kind_check" CHECK (("kind" = ANY (ARRAY['material'::"text", 'packaging'::"text"])))
);


ALTER TABLE "public"."ingredients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."labor_rates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "role_code" "text" NOT NULL,
    "effective_start" "date" NOT NULL,
    "hourly_rate" numeric NOT NULL,
    "burden_pct" numeric DEFAULT 0.25 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "labor_rates_burden_pct_check" CHECK ((("burden_pct" >= (0)::numeric) AND ("burden_pct" <= (2)::numeric))),
    CONSTRAINT "labor_rates_hourly_rate_check" CHECK (("hourly_rate" >= (0)::numeric))
);


ALTER TABLE "public"."labor_rates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."labor_roles" (
    "role_code" "text" NOT NULL,
    "name" "text" NOT NULL
);


ALTER TABLE "public"."labor_roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."org_cost_engine_settings" (
    "org_id" "uuid" NOT NULL,
    "wac_days" integer DEFAULT 30 NOT NULL,
    "overhead_codes" "text"[] DEFAULT ARRAY['OVERHEAD'::"text"] NOT NULL,
    "treat_unallocated_as_overhead" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "org_cost_engine_settings_wac_days_check" CHECK ((("wac_days" >= 1) AND ("wac_days" <= 365)))
);


ALTER TABLE "public"."org_cost_engine_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."org_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."org_role" DEFAULT 'viewer'::"public"."org_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "approved_at" timestamp with time zone,
    "approved_by" "uuid",
    CONSTRAINT "org_members_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'suspended'::"text"])))
);


ALTER TABLE "public"."org_members" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_members" IS 'Users who can access an org (drives RLS).';



CREATE TABLE IF NOT EXISTS "public"."orgs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "subscription_tier_code" "text" DEFAULT 'free'::"text" NOT NULL,
    "support_email" "text",
    "is_listed" boolean DEFAULT false NOT NULL,
    CONSTRAINT "orgs_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 120)))
);


ALTER TABLE "public"."orgs" OWNER TO "postgres";


COMMENT ON TABLE "public"."orgs" IS 'Organizations. All operational data is scoped to an org.';



CREATE TABLE IF NOT EXISTS "public"."platform_admins" (
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."platform_admins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."platform_settings" (
    "id" integer DEFAULT 1 NOT NULL,
    "support_email" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."platform_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_labor_specs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "sku" "text" NOT NULL,
    "role_code" "text" NOT NULL,
    "seconds_per_unit" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_labor_specs_seconds_per_unit_check" CHECK (("seconds_per_unit" >= 0))
);


ALTER TABLE "public"."product_labor_specs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_packaging_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "sku" "text" NOT NULL,
    "ingredient_id" "uuid" NOT NULL,
    "qty" numeric NOT NULL,
    "uom" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_packaging_items_qty_check" CHECK (("qty" >= (0)::numeric))
);


ALTER TABLE "public"."product_packaging_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "sku" "text" NOT NULL,
    "product_name" "text" NOT NULL,
    "category" "text",
    "default_price" numeric,
    "unit_cost" numeric,
    "currency" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "user_id" "uuid" NOT NULL,
    "email" "text",
    "full_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."profiles" IS 'App-level user profile. Populated by trigger on auth.users.';



CREATE TABLE IF NOT EXISTS "public"."recipe_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipe_version_id" "uuid" NOT NULL,
    "ingredient_id" "uuid" NOT NULL,
    "qty" numeric NOT NULL,
    "uom" "text" NOT NULL,
    "loss_pct" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "recipe_items_loss_pct_check" CHECK ((("loss_pct" >= (0)::numeric) AND ("loss_pct" <= (1)::numeric))),
    CONSTRAINT "recipe_items_qty_check" CHECK (("qty" >= (0)::numeric))
);


ALTER TABLE "public"."recipe_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."recipe_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "sku" "text" NOT NULL,
    "effective_start" "date" NOT NULL,
    "effective_end" "date",
    "yield_qty" numeric NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "recipe_versions_yield_qty_check" CHECK (("yield_qty" > (0)::numeric))
);


ALTER TABLE "public"."recipe_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscription_tiers" (
    "tier_code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "max_branches" integer NOT NULL,
    "max_benchmark_plots" integer NOT NULL,
    "global_benchmark_enabled" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "subscription_tiers_max_benchmark_plots_check" CHECK ((("max_benchmark_plots" >= 1) AND ("max_benchmark_plots" <= 6))),
    CONSTRAINT "subscription_tiers_max_branches_check" CHECK (("max_branches" >= 1))
);


ALTER TABLE "public"."subscription_tiers" OWNER TO "postgres";


ALTER TABLE ONLY "auth"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"auth"."refresh_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."forecast_outputs" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."forecast_outputs_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."import_job_rows" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."import_job_rows_id_seq"'::"regclass");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "amr_id_pk" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."audit_log_entries"
    ADD CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_identifier_key" UNIQUE ("identifier");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."flow_state"
    ADD CONSTRAINT "flow_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_provider_id_provider_unique" UNIQUE ("provider_id", "provider");



ALTER TABLE ONLY "auth"."instances"
    ADD CONSTRAINT "instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE ("session_id", "authentication_method");



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_last_challenged_at_key" UNIQUE ("last_challenged_at");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_code_key" UNIQUE ("authorization_code");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_id_key" UNIQUE ("authorization_id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_client_states"
    ADD CONSTRAINT "oauth_client_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_clients"
    ADD CONSTRAINT "oauth_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_client_unique" UNIQUE ("user_id", "client_id");



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_entity_id_key" UNIQUE ("entity_id");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_providers"
    ADD CONSTRAINT "sso_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_org_id_code_key" UNIQUE ("org_id", "code");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_org_id_name_key" UNIQUE ("org_id", "name");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cost_centers"
    ADD CONSTRAINT "cost_centers_org_id_code_key" UNIQUE ("org_id", "code");



ALTER TABLE ONLY "public"."cost_centers"
    ADD CONSTRAINT "cost_centers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expense_allocation_audit"
    ADD CONSTRAINT "expense_allocation_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expense_allocations"
    ADD CONSTRAINT "expense_allocations_expense_id_cost_center_code_key" UNIQUE ("expense_id", "cost_center_code");



ALTER TABLE ONLY "public"."expense_allocations"
    ADD CONSTRAINT "expense_allocations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_org_reference_number_key" UNIQUE ("org_id", "reference_number");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_org_source_hash_key" UNIQUE ("org_id", "source_hash");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forecast_outputs"
    ADD CONSTRAINT "forecast_outputs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."forecast_outputs"
    ADD CONSTRAINT "forecast_outputs_run_id_day_key" UNIQUE ("run_id", "day");



ALTER TABLE ONLY "public"."forecast_runs"
    ADD CONSTRAINT "forecast_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_contract_fields"
    ADD CONSTRAINT "import_contract_fields_pkey" PRIMARY KEY ("entity_type", "canonical_key");



ALTER TABLE ONLY "public"."import_job_rows"
    ADD CONSTRAINT "import_job_rows_job_id_row_number_key" UNIQUE ("job_id", "row_number");



ALTER TABLE ONLY "public"."import_job_rows"
    ADD CONSTRAINT "import_job_rows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_jobs"
    ADD CONSTRAINT "import_jobs_org_id_storage_path_key" UNIQUE ("org_id", "storage_path");



ALTER TABLE ONLY "public"."import_jobs"
    ADD CONSTRAINT "import_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ingredient_receipts"
    ADD CONSTRAINT "ingredient_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ingredients"
    ADD CONSTRAINT "ingredients_org_id_ingredient_code_key" UNIQUE ("org_id", "ingredient_code");



ALTER TABLE ONLY "public"."ingredients"
    ADD CONSTRAINT "ingredients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."labor_rates"
    ADD CONSTRAINT "labor_rates_org_id_role_code_effective_start_key" UNIQUE ("org_id", "role_code", "effective_start");



ALTER TABLE ONLY "public"."labor_rates"
    ADD CONSTRAINT "labor_rates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."labor_roles"
    ADD CONSTRAINT "labor_roles_pkey" PRIMARY KEY ("role_code");



ALTER TABLE ONLY "public"."org_cost_engine_settings"
    ADD CONSTRAINT "org_cost_engine_settings_pkey" PRIMARY KEY ("org_id");



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_org_id_user_id_key" UNIQUE ("org_id", "user_id");



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platform_admins"
    ADD CONSTRAINT "platform_admins_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."platform_settings"
    ADD CONSTRAINT "platform_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_labor_specs"
    ADD CONSTRAINT "product_labor_specs_org_id_sku_role_code_key" UNIQUE ("org_id", "sku", "role_code");



ALTER TABLE ONLY "public"."product_labor_specs"
    ADD CONSTRAINT "product_labor_specs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_packaging_items"
    ADD CONSTRAINT "product_packaging_items_org_id_sku_ingredient_id_key" UNIQUE ("org_id", "sku", "ingredient_id");



ALTER TABLE ONLY "public"."product_packaging_items"
    ADD CONSTRAINT "product_packaging_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_org_id_sku_key" UNIQUE ("org_id", "sku");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."recipe_items"
    ADD CONSTRAINT "recipe_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."recipe_items"
    ADD CONSTRAINT "recipe_items_recipe_version_id_ingredient_id_key" UNIQUE ("recipe_version_id", "ingredient_id");



ALTER TABLE ONLY "public"."recipe_versions"
    ADD CONSTRAINT "recipe_versions_org_id_sku_effective_start_key" UNIQUE ("org_id", "sku", "effective_start");



ALTER TABLE ONLY "public"."recipe_versions"
    ADD CONSTRAINT "recipe_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_org_id_external_invoice_number_key" UNIQUE ("org_id", "external_invoice_number");



ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_items"
    ADD CONSTRAINT "sales_items_invoice_id_line_number_key" UNIQUE ("invoice_id", "line_number");



ALTER TABLE ONLY "public"."sales_items"
    ADD CONSTRAINT "sales_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscription_tiers"
    ADD CONSTRAINT "subscription_tiers_pkey" PRIMARY KEY ("tier_code");



CREATE INDEX "audit_logs_instance_id_idx" ON "auth"."audit_log_entries" USING "btree" ("instance_id");



CREATE UNIQUE INDEX "confirmation_token_idx" ON "auth"."users" USING "btree" ("confirmation_token") WHERE (("confirmation_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "custom_oauth_providers_created_at_idx" ON "auth"."custom_oauth_providers" USING "btree" ("created_at");



CREATE INDEX "custom_oauth_providers_enabled_idx" ON "auth"."custom_oauth_providers" USING "btree" ("enabled");



CREATE INDEX "custom_oauth_providers_identifier_idx" ON "auth"."custom_oauth_providers" USING "btree" ("identifier");



CREATE INDEX "custom_oauth_providers_provider_type_idx" ON "auth"."custom_oauth_providers" USING "btree" ("provider_type");



CREATE UNIQUE INDEX "email_change_token_current_idx" ON "auth"."users" USING "btree" ("email_change_token_current") WHERE (("email_change_token_current")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_new_idx" ON "auth"."users" USING "btree" ("email_change_token_new") WHERE (("email_change_token_new")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "factor_id_created_at_idx" ON "auth"."mfa_factors" USING "btree" ("user_id", "created_at");



CREATE INDEX "flow_state_created_at_idx" ON "auth"."flow_state" USING "btree" ("created_at" DESC);



CREATE INDEX "identities_email_idx" ON "auth"."identities" USING "btree" ("email" "text_pattern_ops");



COMMENT ON INDEX "auth"."identities_email_idx" IS 'Auth: Ensures indexed queries on the email column';



CREATE INDEX "identities_user_id_idx" ON "auth"."identities" USING "btree" ("user_id");



CREATE INDEX "idx_auth_code" ON "auth"."flow_state" USING "btree" ("auth_code");



CREATE INDEX "idx_oauth_client_states_created_at" ON "auth"."oauth_client_states" USING "btree" ("created_at");



CREATE INDEX "idx_user_id_auth_method" ON "auth"."flow_state" USING "btree" ("user_id", "authentication_method");



CREATE INDEX "mfa_challenge_created_at_idx" ON "auth"."mfa_challenges" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "mfa_factors_user_friendly_name_unique" ON "auth"."mfa_factors" USING "btree" ("friendly_name", "user_id") WHERE (TRIM(BOTH FROM "friendly_name") <> ''::"text");



CREATE INDEX "mfa_factors_user_id_idx" ON "auth"."mfa_factors" USING "btree" ("user_id");



CREATE INDEX "oauth_auth_pending_exp_idx" ON "auth"."oauth_authorizations" USING "btree" ("expires_at") WHERE ("status" = 'pending'::"auth"."oauth_authorization_status");



CREATE INDEX "oauth_clients_deleted_at_idx" ON "auth"."oauth_clients" USING "btree" ("deleted_at");



CREATE INDEX "oauth_consents_active_client_idx" ON "auth"."oauth_consents" USING "btree" ("client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_active_user_client_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_user_order_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "granted_at" DESC);



CREATE INDEX "one_time_tokens_relates_to_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("relates_to");



CREATE INDEX "one_time_tokens_token_hash_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("token_hash");



CREATE UNIQUE INDEX "one_time_tokens_user_id_token_type_key" ON "auth"."one_time_tokens" USING "btree" ("user_id", "token_type");



CREATE UNIQUE INDEX "reauthentication_token_idx" ON "auth"."users" USING "btree" ("reauthentication_token") WHERE (("reauthentication_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "recovery_token_idx" ON "auth"."users" USING "btree" ("recovery_token") WHERE (("recovery_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "refresh_tokens_instance_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id");



CREATE INDEX "refresh_tokens_instance_id_user_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id", "user_id");



CREATE INDEX "refresh_tokens_parent_idx" ON "auth"."refresh_tokens" USING "btree" ("parent");



CREATE INDEX "refresh_tokens_session_id_revoked_idx" ON "auth"."refresh_tokens" USING "btree" ("session_id", "revoked");



CREATE INDEX "refresh_tokens_updated_at_idx" ON "auth"."refresh_tokens" USING "btree" ("updated_at" DESC);



CREATE INDEX "saml_providers_sso_provider_id_idx" ON "auth"."saml_providers" USING "btree" ("sso_provider_id");



CREATE INDEX "saml_relay_states_created_at_idx" ON "auth"."saml_relay_states" USING "btree" ("created_at" DESC);



CREATE INDEX "saml_relay_states_for_email_idx" ON "auth"."saml_relay_states" USING "btree" ("for_email");



CREATE INDEX "saml_relay_states_sso_provider_id_idx" ON "auth"."saml_relay_states" USING "btree" ("sso_provider_id");



CREATE INDEX "sessions_not_after_idx" ON "auth"."sessions" USING "btree" ("not_after" DESC);



CREATE INDEX "sessions_oauth_client_id_idx" ON "auth"."sessions" USING "btree" ("oauth_client_id");



CREATE INDEX "sessions_user_id_idx" ON "auth"."sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "sso_domains_domain_idx" ON "auth"."sso_domains" USING "btree" ("lower"("domain"));



CREATE INDEX "sso_domains_sso_provider_id_idx" ON "auth"."sso_domains" USING "btree" ("sso_provider_id");



CREATE UNIQUE INDEX "sso_providers_resource_id_idx" ON "auth"."sso_providers" USING "btree" ("lower"("resource_id"));



CREATE INDEX "sso_providers_resource_id_pattern_idx" ON "auth"."sso_providers" USING "btree" ("resource_id" "text_pattern_ops");



CREATE UNIQUE INDEX "unique_phone_factor_per_user" ON "auth"."mfa_factors" USING "btree" ("user_id", "phone");



CREATE INDEX "user_id_created_at_idx" ON "auth"."sessions" USING "btree" ("user_id", "created_at");



CREATE UNIQUE INDEX "users_email_partial_key" ON "auth"."users" USING "btree" ("email") WHERE ("is_sso_user" = false);



COMMENT ON INDEX "auth"."users_email_partial_key" IS 'Auth: A partial unique index that applies only when is_sso_user is false';



CREATE INDEX "users_instance_id_email_idx" ON "auth"."users" USING "btree" ("instance_id", "lower"(("email")::"text"));



CREATE INDEX "users_instance_id_idx" ON "auth"."users" USING "btree" ("instance_id");



CREATE INDEX "users_is_anonymous_idx" ON "auth"."users" USING "btree" ("is_anonymous");



CREATE UNIQUE INDEX "branches_one_default_per_org" ON "public"."branches" USING "btree" ("org_id") WHERE "is_default";



CREATE UNIQUE INDEX "branches_org_id_code_uidx" ON "public"."branches" USING "btree" ("org_id", "code") WHERE ("code" IS NOT NULL);



CREATE INDEX "branches_org_id_idx" ON "public"."branches" USING "btree" ("org_id");



CREATE INDEX "cost_centers_org_id_idx" ON "public"."cost_centers" USING "btree" ("org_id");



CREATE INDEX "expense_allocation_audit_expense_id_idx" ON "public"."expense_allocation_audit" USING "btree" ("expense_id");



CREATE INDEX "expense_allocations_expense_id_idx" ON "public"."expense_allocations" USING "btree" ("expense_id");



CREATE INDEX "expense_allocations_org_id_idx" ON "public"."expense_allocations" USING "btree" ("org_id");



CREATE INDEX "expenses_org_branch_date_idx" ON "public"."expenses" USING "btree" ("org_id", "branch_id", "expense_date");



CREATE INDEX "expenses_org_date_idx" ON "public"."expenses" USING "btree" ("org_id", "expense_date" DESC);



CREATE INDEX "forecast_outputs_run_day_idx" ON "public"."forecast_outputs" USING "btree" ("run_id", "day");



CREATE INDEX "forecast_runs_org_branch_created_idx" ON "public"."forecast_runs" USING "btree" ("org_id", "branch_id", "created_at" DESC);



CREATE INDEX "forecast_runs_org_created_idx" ON "public"."forecast_runs" USING "btree" ("org_id", "created_at" DESC);



CREATE INDEX "import_job_rows_job_id_idx" ON "public"."import_job_rows" USING "btree" ("job_id");



CREATE UNIQUE INDEX "import_job_rows_job_id_row_number_uidx" ON "public"."import_job_rows" USING "btree" ("job_id", "row_number");



CREATE INDEX "import_jobs_org_id_created_at_idx" ON "public"."import_jobs" USING "btree" ("org_id", "created_at" DESC);



CREATE INDEX "import_jobs_org_id_status_idx" ON "public"."import_jobs" USING "btree" ("org_id", "status");



CREATE INDEX "ingredient_receipts_org_ing_date_idx" ON "public"."ingredient_receipts" USING "btree" ("org_id", "ingredient_id", "receipt_date");



CREATE INDEX "ingredients_org_idx" ON "public"."ingredients" USING "btree" ("org_id");



CREATE INDEX "labor_rates_org_role_idx" ON "public"."labor_rates" USING "btree" ("org_id", "role_code", "effective_start" DESC);



CREATE INDEX "org_members_org_id_idx" ON "public"."org_members" USING "btree" ("org_id");



CREATE INDEX "org_members_user_id_idx" ON "public"."org_members" USING "btree" ("user_id");



CREATE INDEX "packaging_org_sku_idx" ON "public"."product_packaging_items" USING "btree" ("org_id", "sku");



CREATE INDEX "product_labor_org_sku_idx" ON "public"."product_labor_specs" USING "btree" ("org_id", "sku");



CREATE INDEX "products_org_id_idx" ON "public"."products" USING "btree" ("org_id");



CREATE INDEX "recipe_items_version_idx" ON "public"."recipe_items" USING "btree" ("recipe_version_id");



CREATE INDEX "recipe_versions_org_sku_idx" ON "public"."recipe_versions" USING "btree" ("org_id", "sku");



CREATE INDEX "sales_invoices_org_date_idx" ON "public"."sales_invoices" USING "btree" ("org_id", "invoice_date" DESC);



CREATE INDEX "sales_items_invoice_id_idx" ON "public"."sales_items" USING "btree" ("invoice_id");



CREATE INDEX "sales_items_org_id_idx" ON "public"."sales_items" USING "btree" ("org_id");



CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();



CREATE OR REPLACE TRIGGER "trg_enforce_branch_limit" BEFORE INSERT ON "public"."branches" FOR EACH ROW EXECUTE FUNCTION "public"."trg_enforce_branch_limit"();



CREATE OR REPLACE TRIGGER "trg_expense_allocations_set_updated_at" BEFORE UPDATE ON "public"."expense_allocations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_expenses_set_updated_at" BEFORE UPDATE ON "public"."expenses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_first_member_super_admin" BEFORE INSERT ON "public"."org_members" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_first_org_member_super_admin"();



CREATE OR REPLACE TRIGGER "trg_import_jobs_set_updated_at" BEFORE UPDATE ON "public"."import_jobs" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_ingredients_set_updated_at" BEFORE UPDATE ON "public"."ingredients" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_org_bootstrap_defaults" AFTER INSERT ON "public"."orgs" FOR EACH ROW EXECUTE FUNCTION "public"."org_bootstrap_defaults"();



CREATE OR REPLACE TRIGGER "trg_org_members_status_guard" BEFORE UPDATE ON "public"."org_members" FOR EACH ROW EXECUTE FUNCTION "public"."trg_org_members_status_guard"();



CREATE OR REPLACE TRIGGER "trg_platform_settings_set_updated_at" BEFORE UPDATE ON "public"."platform_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_products_set_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_profiles_set_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_sales_invoices_set_updated_at" BEFORE UPDATE ON "public"."sales_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_sales_items_set_updated_at" BEFORE UPDATE ON "public"."sales_items" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_subscription_tiers_set_updated_at" BEFORE UPDATE ON "public"."subscription_tiers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY ("factor_id") REFERENCES "auth"."mfa_factors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY ("flow_state_id") REFERENCES "auth"."flow_state"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_oauth_client_id_fkey" FOREIGN KEY ("oauth_client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cost_centers"
    ADD CONSTRAINT "cost_centers_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_allocation_audit"
    ADD CONSTRAINT "expense_allocation_audit_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_allocation_audit"
    ADD CONSTRAINT "expense_allocation_audit_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_allocations"
    ADD CONSTRAINT "expense_allocations_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_allocations"
    ADD CONSTRAINT "expense_allocations_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_source_import_job_id_fkey" FOREIGN KEY ("source_import_job_id") REFERENCES "public"."import_jobs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."forecast_outputs"
    ADD CONSTRAINT "forecast_outputs_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."forecast_outputs"
    ADD CONSTRAINT "forecast_outputs_run_id_fkey" FOREIGN KEY ("run_id") REFERENCES "public"."forecast_runs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."forecast_runs"
    ADD CONSTRAINT "forecast_runs_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."import_job_rows"
    ADD CONSTRAINT "import_job_rows_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "public"."import_jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."import_jobs"
    ADD CONSTRAINT "import_jobs_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."import_jobs"
    ADD CONSTRAINT "import_jobs_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ingredient_receipts"
    ADD CONSTRAINT "ingredient_receipts_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "public"."ingredients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ingredient_receipts"
    ADD CONSTRAINT "ingredient_receipts_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ingredients"
    ADD CONSTRAINT "ingredients_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."labor_rates"
    ADD CONSTRAINT "labor_rates_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."labor_rates"
    ADD CONSTRAINT "labor_rates_role_code_fkey" FOREIGN KEY ("role_code") REFERENCES "public"."labor_roles"("role_code") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."org_cost_engine_settings"
    ADD CONSTRAINT "org_cost_engine_settings_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."org_members"
    ADD CONSTRAINT "org_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_subscription_tier_fkey" FOREIGN KEY ("subscription_tier_code") REFERENCES "public"."subscription_tiers"("tier_code");



ALTER TABLE ONLY "public"."product_labor_specs"
    ADD CONSTRAINT "product_labor_specs_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_labor_specs"
    ADD CONSTRAINT "product_labor_specs_role_code_fkey" FOREIGN KEY ("role_code") REFERENCES "public"."labor_roles"("role_code") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."product_packaging_items"
    ADD CONSTRAINT "product_packaging_items_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "public"."ingredients"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."product_packaging_items"
    ADD CONSTRAINT "product_packaging_items_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recipe_items"
    ADD CONSTRAINT "recipe_items_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "public"."ingredients"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."recipe_items"
    ADD CONSTRAINT "recipe_items_recipe_version_id_fkey" FOREIGN KEY ("recipe_version_id") REFERENCES "public"."recipe_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."recipe_versions"
    ADD CONSTRAINT "recipe_versions_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_source_import_job_id_fkey" FOREIGN KEY ("source_import_job_id") REFERENCES "public"."import_jobs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales_items"
    ADD CONSTRAINT "sales_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."sales_invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_items"
    ADD CONSTRAINT "sales_items_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_items"
    ADD CONSTRAINT "sales_items_recipe_version_id_fkey" FOREIGN KEY ("recipe_version_id") REFERENCES "public"."recipe_versions"("id");



ALTER TABLE ONLY "public"."sales_items"
    ADD CONSTRAINT "sales_items_source_import_job_id_fkey" FOREIGN KEY ("source_import_job_id") REFERENCES "public"."import_jobs"("id") ON DELETE SET NULL;



ALTER TABLE "auth"."audit_log_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."flow_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."instances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_amr_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_challenges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_factors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."one_time_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_relay_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."schema_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branches_select_member" ON "public"."branches" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("org_id"));



ALTER TABLE "public"."cost_centers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cost_centers_select_member" ON "public"."cost_centers" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("org_id"));



ALTER TABLE "public"."expense_allocation_audit" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "expense_allocation_audit_select_member" ON "public"."expense_allocation_audit" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "expense_allocation_audit"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."expense_allocations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "expense_allocations_select_member" ON "public"."expense_allocations" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "expense_allocations"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



CREATE POLICY "expense_allocations_write_member" ON "public"."expense_allocations" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "expense_allocations"."org_id") AND ("m"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "expense_allocations"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "expenses_select_member" ON "public"."expenses" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "expenses"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."forecast_outputs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "forecast_outputs_select_member" ON "public"."forecast_outputs" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "forecast_outputs"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."forecast_runs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "forecast_runs_select_member" ON "public"."forecast_runs" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "forecast_runs"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."import_contract_fields" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_contract_fields_read" ON "public"."import_contract_fields" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."import_job_rows" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_job_rows_delete_member" ON "public"."import_job_rows" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."import_jobs" "j"
  WHERE (("j"."id" = "import_job_rows"."job_id") AND "public"."is_org_member"("j"."org_id")))));



CREATE POLICY "import_job_rows_insert_member" ON "public"."import_job_rows" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."import_jobs" "j"
  WHERE (("j"."id" = "import_job_rows"."job_id") AND "public"."is_org_member"("j"."org_id")))));



CREATE POLICY "import_job_rows_select_member" ON "public"."import_job_rows" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."import_jobs" "j"
  WHERE (("j"."id" = "import_job_rows"."job_id") AND "public"."is_org_member"("j"."org_id")))));



ALTER TABLE "public"."import_jobs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_jobs_insert_member" ON "public"."import_jobs" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_org_member"("org_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "import_jobs_select_member" ON "public"."import_jobs" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("org_id"));



CREATE POLICY "import_jobs_update_member" ON "public"."import_jobs" FOR UPDATE TO "authenticated" USING ("public"."is_org_member"("org_id")) WITH CHECK ("public"."is_org_member"("org_id"));



ALTER TABLE "public"."ingredient_receipts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ingredient_receipts_select_member" ON "public"."ingredient_receipts" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "ingredient_receipts"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."ingredients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ingredients_select_member" ON "public"."ingredients" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "ingredients"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."labor_rates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "labor_rates_select_member" ON "public"."labor_rates" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "labor_rates"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."org_cost_engine_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_cost_engine_settings_select_member" ON "public"."org_cost_engine_settings" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "org_cost_engine_settings"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."org_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_members_select_member" ON "public"."org_members" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("org_id"));



ALTER TABLE "public"."orgs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orgs_select_member" ON "public"."orgs" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("id"));



CREATE POLICY "orgs_update_super_admin" ON "public"."orgs" FOR UPDATE TO "authenticated" USING ("public"."is_org_super_admin"("id")) WITH CHECK ("public"."is_org_super_admin"("id"));



ALTER TABLE "public"."platform_admins" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "platform_admins_select_admin" ON "public"."platform_admins" FOR SELECT TO "authenticated" USING ("public"."is_platform_admin"());



CREATE POLICY "platform_admins_write_admin" ON "public"."platform_admins" TO "authenticated" USING ("public"."is_platform_admin"()) WITH CHECK ("public"."is_platform_admin"());



ALTER TABLE "public"."platform_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "platform_settings_select_auth" ON "public"."platform_settings" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "platform_settings_update_admin" ON "public"."platform_settings" FOR UPDATE TO "authenticated" USING ("public"."is_platform_admin"()) WITH CHECK ("public"."is_platform_admin"());



ALTER TABLE "public"."product_labor_specs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_labor_specs_select_member" ON "public"."product_labor_specs" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "product_labor_specs"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."product_packaging_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_packaging_items_select_member" ON "public"."product_packaging_items" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "product_packaging_items"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_select_member" ON "public"."products" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "products"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_self" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "profiles_update_self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."recipe_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recipe_items_select_member" ON "public"."recipe_items" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."recipe_versions" "rv"
     JOIN "public"."org_members" "m" ON (("m"."org_id" = "rv"."org_id")))
  WHERE (("rv"."id" = "recipe_items"."recipe_version_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."recipe_versions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recipe_versions_select_member" ON "public"."recipe_versions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."org_members" "m"
  WHERE (("m"."org_id" = "recipe_versions"."org_id") AND ("m"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."sales_invoices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_invoices_select_member" ON "public"."sales_invoices" FOR SELECT USING ("public"."is_org_member"("org_id"));



ALTER TABLE "public"."sales_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_items_select_member" ON "public"."sales_items" FOR SELECT USING ("public"."is_org_member"("org_id"));



ALTER TABLE "public"."subscription_tiers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscription_tiers_select_auth" ON "public"."subscription_tiers" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "subscription_tiers_write_admin" ON "public"."subscription_tiers" TO "authenticated" USING ("public"."is_platform_admin"()) WITH CHECK ("public"."is_platform_admin"());



GRANT USAGE ON SCHEMA "auth" TO "anon";
GRANT USAGE ON SCHEMA "auth" TO "authenticated";
GRANT USAGE ON SCHEMA "auth" TO "service_role";
GRANT ALL ON SCHEMA "auth" TO "supabase_auth_admin";
GRANT ALL ON SCHEMA "auth" TO "dashboard_user";
GRANT USAGE ON SCHEMA "auth" TO "postgres";



REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT ALL ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "auth"."email"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."jwt"() TO "postgres";
GRANT ALL ON FUNCTION "auth"."jwt"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."role"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."uid"() TO "dashboard_user";



REVOKE ALL ON FUNCTION "public"."allocate_expense_to_cost_centers"("p_expense_id" "uuid", "p_allocations" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."allocate_expense_to_cost_centers"("p_expense_id" "uuid", "p_allocations" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."allocate_expense_to_cost_centers"("p_expense_id" "uuid", "p_allocations" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."apply_unit_economics_to_sales_job"("p_job_id" "uuid", "p_wac_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_unit_economics_to_sales_job"("p_job_id" "uuid", "p_wac_days" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."apply_unit_economics_to_sales_job"("p_job_id" "uuid", "p_wac_days" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."auto_allocate_expense"("p_expense_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."auto_allocate_expense"("p_expense_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."auto_allocate_expense"("p_expense_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."auto_allocate_expenses_for_job"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."auto_allocate_expenses_for_job"("p_job_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."auto_allocate_expenses_for_job"("p_job_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."compute_unit_cogs"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date", "p_wac_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."compute_unit_cogs"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date", "p_wac_days" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."compute_unit_cogs"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date", "p_wac_days" integer) TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."import_jobs" TO "authenticated";
GRANT ALL ON TABLE "public"."import_jobs" TO "service_role";



GRANT ALL ON FUNCTION "public"."create_import_job"("p_job_id" "uuid", "p_org_id" "uuid", "p_entity_type" "public"."import_entity", "p_original_filename" "text", "p_storage_path" "text", "p_file_size" bigint, "p_content_type" "text", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_import_job"("p_job_id" "uuid", "p_org_id" "uuid", "p_entity_type" "public"."import_entity", "p_original_filename" "text", "p_storage_path" "text", "p_file_size" bigint, "p_content_type" "text", "p_metadata" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_org"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_org"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."default_org_member_role"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."default_org_member_role"() TO "service_role";
GRANT ALL ON FUNCTION "public"."default_org_member_role"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."ensure_first_org_member_super_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."expense_source_hash"("p" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."expense_source_hash"("p" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."expense_source_hash"("p" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_benchmark_points"("p_org_id" "uuid", "p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_benchmark_points"("p_org_id" "uuid", "p_days" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_benchmark_points"("p_org_id" "uuid", "p_days" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_benchmark_points_core"("p_org_id" "uuid", "p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_benchmark_points_core"("p_org_id" "uuid", "p_days" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_benchmark_points_core"("p_org_id" "uuid", "p_days" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_exec_kpis"("p_org_id" "uuid", "p_days" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_exec_monthly"("p_org_id" "uuid", "p_months" integer, "p_cogs_mode" "text", "p_branch_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_expense_allocations"("p_expense_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_expense_allocations"("p_expense_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_expense_allocations"("p_expense_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_expenses_cost_center_daily"("p_org_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_expenses_cost_center_daily"("p_org_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_expenses_cost_center_daily"("p_org_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_expenses_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_forecast_outputs"("p_run_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_forecast_outputs"("p_run_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_forecast_outputs"("p_run_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_import_contract"("p_entity" "public"."import_entity") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_import_contract"("p_entity" "public"."import_entity") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_import_contract"("p_entity" "public"."import_entity") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_import_job"("p_job_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_import_job"("p_job_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_org_entitlements"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_org_entitlements"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_org_entitlements"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_platform_support_email"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_platform_support_email"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_platform_support_email"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_sales_daily"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_sales_daily_range"("p_org_id" "uuid", "p_start" "date", "p_end" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_sales_daily_range"("p_org_id" "uuid", "p_start" "date", "p_end" "date") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_sales_daily_range"("p_org_id" "uuid", "p_start" "date", "p_end" "date") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_top_categories_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_top_categories_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_top_categories_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_top_products_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_top_products_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_top_products_30d"("p_org_id" "uuid", "p_limit" integer, "p_cogs_mode" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer, "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer, "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_unit_economics_by_sku"("p_org_id" "uuid", "p_days" integer, "p_branch_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."import_expenses_from_staging"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."import_expenses_from_staging"("p_job_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."import_expenses_from_staging"("p_job_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."import_products_from_staging"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."import_products_from_staging"("p_job_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."import_products_from_staging"("p_job_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."import_sales_from_staging"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."import_sales_from_staging"("p_job_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."import_sales_from_staging"("p_job_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_org_member"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_org_member"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."is_org_member"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_org_super_admin"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_org_super_admin"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."is_org_super_admin"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_platform_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_platform_admin"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_platform_admin"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_branches_for_org"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_branches_for_org"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_branches_for_org"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_cost_center_codes"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_cost_center_codes"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_cost_center_codes"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_expenses_for_allocation"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."list_forecast_runs"("p_org_id" "uuid", "p_limit" integer, "p_branch_id" "uuid") TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."import_job_rows" TO "authenticated";
GRANT ALL ON TABLE "public"."import_job_rows" TO "service_role";



GRANT ALL ON FUNCTION "public"."list_import_job_rows"("p_job_id" "uuid", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_import_job_rows"("p_job_id" "uuid", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."list_import_jobs"("p_org_id" "uuid", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_import_jobs"("p_org_id" "uuid", "p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_listed_orgs"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_listed_orgs"("p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."list_listed_orgs"("p_limit" integer) TO "authenticated";



GRANT ALL ON FUNCTION "public"."list_my_orgs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_my_orgs"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."list_orgs_for_dropdown"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_orgs_for_dropdown"() TO "service_role";
GRANT ALL ON FUNCTION "public"."list_orgs_for_dropdown"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."norm_dim"("p" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."org_anchor_date"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."org_anchor_date"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."org_anchor_date"("p_org_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."org_bootstrap_defaults"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."overhead_daily"("p_org_id" "uuid", "p_day" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."overhead_daily"("p_org_id" "uuid", "p_day" "date") TO "service_role";
GRANT ALL ON FUNCTION "public"."overhead_daily"("p_org_id" "uuid", "p_day" "date") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_add_admin"("p_user_id" "uuid", "p_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_add_admin"("p_user_id" "uuid", "p_email" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_add_admin"("p_user_id" "uuid", "p_email" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_add_member"("p_org_id" "uuid", "p_user_email" "text", "p_user_id" "uuid", "p_is_admin" boolean, "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_add_member"("p_org_id" "uuid", "p_user_email" "text", "p_user_id" "uuid", "p_is_admin" boolean, "p_status" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_add_member"("p_org_id" "uuid", "p_user_email" "text", "p_user_id" "uuid", "p_is_admin" boolean, "p_status" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_create_org"("p_name" "text", "p_tier_code" "text", "p_is_listed" boolean, "p_owner_email" "text", "p_owner_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_create_org"("p_name" "text", "p_tier_code" "text", "p_is_listed" boolean, "p_owner_email" "text", "p_owner_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_create_org"("p_name" "text", "p_tier_code" "text", "p_is_listed" boolean, "p_owner_email" "text", "p_owner_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_find_user_id"("p_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_find_user_id"("p_email" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_find_user_id"("p_email" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_list_org_members"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_list_org_members"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_list_org_members"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_list_orgs"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_list_orgs"("p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_list_orgs"("p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_list_pending_members"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_list_pending_members"("p_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_list_pending_members"("p_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_remove_member"("p_org_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_remove_member"("p_org_id" "uuid", "p_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_remove_member"("p_org_id" "uuid", "p_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_set_member_admin"("p_org_id" "uuid", "p_user_id" "uuid", "p_is_admin" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_set_member_admin"("p_org_id" "uuid", "p_user_id" "uuid", "p_is_admin" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_set_member_admin"("p_org_id" "uuid", "p_user_id" "uuid", "p_is_admin" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_set_member_status"("p_org_id" "uuid", "p_user_id" "uuid", "p_status" "text", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_set_member_status"("p_org_id" "uuid", "p_user_id" "uuid", "p_status" "text", "p_role" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_set_member_status"("p_org_id" "uuid", "p_user_id" "uuid", "p_status" "text", "p_role" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_set_org_tier"("p_org_id" "uuid", "p_tier_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_set_org_tier"("p_org_id" "uuid", "p_tier_code" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_set_org_tier"("p_org_id" "uuid", "p_tier_code" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."platform_update_org"("p_org_id" "uuid", "p_tier_code" "text", "p_is_listed" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."platform_update_org"("p_org_id" "uuid", "p_tier_code" "text", "p_is_listed" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."platform_update_org"("p_org_id" "uuid", "p_tier_code" "text", "p_is_listed" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."preview_expense_allocation"("p_expense_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."preview_expense_allocation"("p_expense_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."preview_expense_allocation"("p_expense_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."request_org_access"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_org_access"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."request_org_access"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."safe_org_role"("p" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."safe_org_role"("p" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."safe_org_role"("p" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."save_import_job_mapping"("p_job_id" "uuid", "p_mapping" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_import_job_mapping"("p_job_id" "uuid", "p_mapping" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."seed_cost_engine_demo"("p_org_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seed_cost_engine_demo"("p_org_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."seed_cost_engine_demo"("p_org_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."select_loaded_hourly_rate"("p_org_id" "uuid", "p_role_code" "text", "p_as_of" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."select_loaded_hourly_rate"("p_org_id" "uuid", "p_role_code" "text", "p_as_of" "date") TO "service_role";
GRANT ALL ON FUNCTION "public"."select_loaded_hourly_rate"("p_org_id" "uuid", "p_role_code" "text", "p_as_of" "date") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."select_recipe_version_id"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."select_recipe_version_id"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date") TO "service_role";
GRANT ALL ON FUNCTION "public"."select_recipe_version_id"("p_org_id" "uuid", "p_sku" "text", "p_as_of" "date") TO "authenticated";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_import_job"("p_job_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_import_job"("p_job_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."start_import_job"("p_job_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."suggest_expense_allocations"("p_expense_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."suggest_expense_allocations"("p_expense_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."suggest_expense_allocations"("p_expense_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."to_base_qty"("p_qty" numeric, "p_uom" "text", "p_base_uom" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_enforce_branch_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_org_members_status_guard"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."wac_unit_cost"("p_org_id" "uuid", "p_ingredient_id" "uuid", "p_as_of" "date", "p_window_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."wac_unit_cost"("p_org_id" "uuid", "p_ingredient_id" "uuid", "p_as_of" "date", "p_window_days" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."wac_unit_cost"("p_org_id" "uuid", "p_ingredient_id" "uuid", "p_as_of" "date", "p_window_days" integer) TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."expense_allocations" TO "authenticated";
GRANT ALL ON TABLE "public"."expense_allocations" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."expenses" TO "authenticated";
GRANT ALL ON TABLE "public"."expenses" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_invoices" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_items" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_items" TO "service_role";



GRANT ALL ON TABLE "auth"."audit_log_entries" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."audit_log_entries" TO "postgres";
GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "postgres";
GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."flow_state" TO "postgres";
GRANT SELECT ON TABLE "auth"."flow_state" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."flow_state" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."identities" TO "postgres";
GRANT SELECT ON TABLE "auth"."identities" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."identities" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."instances" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."instances" TO "postgres";
GRANT SELECT ON TABLE "auth"."instances" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_amr_claims" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_amr_claims" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_challenges" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_challenges" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_factors" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_factors" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_client_states" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_client_states" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_clients" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_clients" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_consents" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_consents" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."one_time_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."one_time_tokens" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."refresh_tokens" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."refresh_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "dashboard_user";
GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "postgres";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_relay_states" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_relay_states" TO "dashboard_user";



GRANT SELECT ON TABLE "auth"."schema_migrations" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sessions" TO "postgres";
GRANT SELECT ON TABLE "auth"."sessions" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sessions" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_domains" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_domains" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_providers" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."users" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."users" TO "postgres";
GRANT SELECT ON TABLE "auth"."users" TO "postgres" WITH GRANT OPTION;



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."branches" TO "authenticated";
GRANT ALL ON TABLE "public"."branches" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."cost_centers" TO "authenticated";
GRANT ALL ON TABLE "public"."cost_centers" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."expense_allocation_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."expense_allocation_audit" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."forecast_outputs" TO "authenticated";
GRANT ALL ON TABLE "public"."forecast_outputs" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "public"."forecast_outputs_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."forecast_outputs_id_seq" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."forecast_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."forecast_runs" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."import_contract_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."import_contract_fields" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "public"."import_job_rows_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."import_job_rows_id_seq" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ingredient_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."ingredient_receipts" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ingredients" TO "authenticated";
GRANT ALL ON TABLE "public"."ingredients" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."labor_rates" TO "authenticated";
GRANT ALL ON TABLE "public"."labor_rates" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."labor_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."labor_roles" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_cost_engine_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."org_cost_engine_settings" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_members" TO "authenticated";
GRANT ALL ON TABLE "public"."org_members" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."orgs" TO "authenticated";
GRANT ALL ON TABLE "public"."orgs" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."platform_admins" TO "authenticated";
GRANT ALL ON TABLE "public"."platform_admins" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."platform_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."platform_settings" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."product_labor_specs" TO "authenticated";
GRANT ALL ON TABLE "public"."product_labor_specs" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."product_packaging_items" TO "authenticated";
GRANT ALL ON TABLE "public"."product_packaging_items" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."recipe_items" TO "authenticated";
GRANT ALL ON TABLE "public"."recipe_items" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."recipe_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."recipe_versions" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."subscription_tiers" TO "authenticated";
GRANT ALL ON TABLE "public"."subscription_tiers" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,USAGE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";




