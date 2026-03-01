import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import Papa from "https://esm.sh/papaparse@5.4.1";

type ContractRow = { canonical_key: string; data_type: "text"|"number"|"date"|"boolean"; is_required: boolean };

function resp(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-user-jwt, x-client-info, apikey, content-type",
    },
  });
}
const norm = (s: string) => (s ?? "").toString().trim().toLowerCase().replace(/\s+/g, "_");

function toNumber(v: any): number | null {
  const s = String(v ?? "").trim();
  if (!s) return null;
  const n = Number(s.replace(/,/g, ""));
  return Number.isFinite(n) ? n : null;
}
function toISODate(v: any): string | null {
  const s = String(v ?? "").trim();
  if (!s) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const t = Date.parse(s);
  if (Number.isNaN(t)) return null;
  const d = new Date(t);
  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}
function toBool(v: any): boolean | null {
  const s = String(v ?? "").trim().toLowerCase();
  if (!s) return null;
  if (["true","t","1","yes","y"].includes(s)) return true;
  if (["false","f","0","no","n"].includes(s)) return false;
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return resp({ ok: true });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return resp({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);

  // gateway-proof auth
  const userJwt = req.headers.get("x-user-jwt") ?? req.headers.get("X-User-JWT") ?? "";
  if (!userJwt) return resp({ error: "Missing x-user-jwt header (user access token)" }, 401);

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const { data: userData, error: userErr } = await admin.auth.getUser(userJwt);
  if (userErr || !userData?.user) return resp({ error: "Invalid user JWT", details: userErr?.message ?? "unknown" }, 401);

  const body = await req.json().catch(() => ({}));
  const job_id = body?.job_id as string | undefined;
  const limit = Number(body?.limit ?? 200);
  if (!job_id) return resp({ error: "Missing job_id" }, 400);
  const rowLimit = Number.isFinite(limit) ? Math.max(10, Math.min(limit, 2000)) : 200;

  const { data: job, error: jobErr } = await admin
    .from("import_jobs")
    .select("id, org_id, entity_type, storage_bucket, storage_path, metadata")
    .eq("id", job_id)
    .single();
  if (jobErr || !job) return resp({ error: "Job lookup failed", details: jobErr?.message ?? "not found" }, 400);

  const { data: member } = await admin
    .from("org_members")
    .select("org_id")
    .eq("org_id", job.org_id)
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (!member) return resp({ error: "Forbidden: not a member of this org" }, 403);

  // Load contract from DB (single source of truth)
  const { data: contract, error: cErr } = await admin.rpc("get_import_contract", { p_entity: job.entity_type });
  if (cErr) return resp({ error: "Failed loading import contract", details: cErr.message }, 400);
  const fields = (contract ?? []) as ContractRow[];

  const requiredKeys = fields.filter(f => f.is_required).map(f => f.canonical_key);
  const mapping = (job.metadata?.mapping ?? {}) as Record<string, string>;

  const { data: file, error: dlErr } = await admin.storage.from(job.storage_bucket).download(job.storage_path);
  if (dlErr) return resp({ error: "Storage download failed", details: dlErr.message }, 400);

  const csvText = await file.text();
  const parsedCsv = Papa.parse<Record<string, any>>(csvText, { header: true, skipEmptyLines: true });
  if (parsedCsv.errors?.length) return resp({ error: "CSV parse errors", details: parsedCsv.errors.slice(0, 10) }, 400);

  const headers = (parsedCsv.meta?.fields ?? []).filter(Boolean);
  const headersNorm = new Map<string, string>();
  for (const h of headers) headersNorm.set(norm(h), h);

  // Build canonical_key -> actual header
  const effective: Record<string, string> = {};
  for (const f of fields) {
    const k = f.canonical_key;
    const mapped = mapping[k];
    if (mapped && headersNorm.has(norm(mapped))) effective[k] = headersNorm.get(norm(mapped))!;
    else if (headersNorm.has(norm(k))) effective[k] = headersNorm.get(norm(k))!;
  }

  // clear staging
  const { error: delErr } = await admin.from("import_job_rows").delete().eq("job_id", job_id);
  if (delErr) return resp({ error: "Failed clearing staging rows", details: delErr.message }, 400);

  const rows = (parsedCsv.data ?? []).slice(0, rowLimit);
  let validCount = 0, invalidCount = 0;

  const toInsert = rows.map((rawRow, i) => {
    const parsed: Record<string, any> = {};
    for (const f of fields) {
      const src = effective[f.canonical_key];
      if (src) parsed[f.canonical_key] = rawRow[src];
    }

    const errors: string[] = [];

    for (const k of requiredKeys) {
      const v = parsed[k];
      if (v === undefined || v === null || String(v).trim() === "") errors.push(`Missing required field: ${k}`);
    }

    for (const f of fields) {
      const k = f.canonical_key;
      const v = parsed[k];
      if (v === undefined || v === null || String(v).trim() === "") continue;

      if (f.data_type === "number") {
        const n = toNumber(v);
        if (n === null) errors.push(`Invalid number: ${k}`);
        else parsed[k] = n;
      } else if (f.data_type === "date") {
        const d = toISODate(v);
        if (!d) errors.push(`Invalid date: ${k}`);
        else parsed[k] = d;
      } else if (f.data_type === "boolean") {
        const b = toBool(v);
        if (b === null) errors.push(`Invalid boolean: ${k}`);
        else parsed[k] = b;
      } else {
        parsed[k] = String(v).trim();
      }
    }

    const is_valid = errors.length === 0;
    if (is_valid) validCount += 1;
    else invalidCount += 1;

    return { job_id, row_number: i + 1, raw: rawRow, parsed, is_valid, errors };
  });

  const { error: insErr } = await admin.from("import_job_rows").insert(toInsert);
  if (insErr) return resp({ error: "Failed inserting staging rows", details: insErr.message }, 400);

  const status = invalidCount > 0 ? "parsed" : "validated";
  const summary = { preview_rows: toInsert.length, valid_rows: validCount, invalid_rows: invalidCount, headers };

  const nextMetadata = { ...(job.metadata ?? {}), headers, last_parse: new Date().toISOString() };
  const { error: updErr } = await admin.from("import_jobs").update({ status, summary, metadata: nextMetadata }).eq("id", job_id);
  if (updErr) return resp({ error: "Failed updating job", details: updErr.message }, 400);

  return resp({ ok: true, job_id, status, summary });
});
