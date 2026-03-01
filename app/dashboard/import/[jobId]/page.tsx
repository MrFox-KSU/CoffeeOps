"use client";

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';
import { SetupRequired } from '@/components/SetupRequired';
import { suggestMapping } from '@/lib/import/mapping';
import { ENTITY_REQUIREMENTS, type FieldRequirement } from '@/lib/import/requirements';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';
import type { Database } from '@/lib/supabase/types';

type ImportJob = Database['public']['Tables']['import_jobs']['Row'];
type ImportJobRow = Database['public']['Tables']['import_job_rows']['Row'];

type Mapping = Record<string, string>;

type ContractRow = {
  canonical_key: string;
  display_name: string;
  data_type: 'text' | 'number' | 'date' | 'boolean' | string;
  is_required: boolean;
  ordinal: number;
};

function toFieldType(t: ContractRow['data_type']): FieldRequirement['type'] {
  if (t === 'number') return 'number';
  if (t === 'date') return 'date';
  if (t === 'boolean') return 'boolean';
  return 'string';
}

function asReqs(contract: ContractRow[], fallbackEntity: keyof typeof ENTITY_REQUIREMENTS): FieldRequirement[] {
  if (contract?.length) {
    return contract.map((c) => ({
      key: c.canonical_key,
      label: c.display_name || c.canonical_key,
      type: toFieldType(c.data_type as any),
      required: !!c.is_required,
    }));
  }
  return ENTITY_REQUIREMENTS[fallbackEntity] ?? [];
}

function renderErrors(errs: any): string {
  if (!errs) return '';
  if (Array.isArray(errs)) {
    return errs
      .map((e) => {
        if (!e) return '';
        if (typeof e === 'string') return e;
        if (typeof e === 'object') return (e.message ?? e.error ?? JSON.stringify(e)) as string;
        return String(e);
      })
      .filter(Boolean)
      .join(' · ');
  }
  if (typeof errs === 'string') return errs;
  return JSON.stringify(errs);
}

export default function ImportJobDetailPage({ params }: { params: { jobId: string } }) {
  const router = useRouter();
  const supabase = getSupabaseBrowserClient();

  const [job, setJob] = useState<ImportJob | null>(null);
  const [rows, setRows] = useState<ImportJobRow[]>([]);
  const [contract, setContract] = useState<ContractRow[]>([]);

  const [mapping, setMapping] = useState<Mapping>({});
  const [mappingDirty, setMappingDirty] = useState(false);

  const [parseResult, setParseResult] = useState<any>(null);
  const [importResult, setImportResult] = useState<any>(null);

  const [busyParse, setBusyParse] = useState(false);
  const [busySave, setBusySave] = useState(false);
  const [busyImport, setBusyImport] = useState(false);
  const [busyRecompute, setBusyRecompute] = useState(false);
  const [recomputeResult, setRecomputeResult] = useState<any>(null);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reqs = useMemo(() => asReqs(contract, ((job?.entity_type ?? 'unknown') as keyof typeof ENTITY_REQUIREMENTS)), [contract, job?.entity_type]);

  const parsedColumns = useMemo(() => {
    const meta: any = job?.metadata ?? {};
    const cols =
      (meta?.parsing?.columns && Array.isArray(meta.parsing.columns) ? meta.parsing.columns : null) ??
      (meta?.headers && Array.isArray(meta.headers) ? meta.headers : null) ??
      [];
    return cols as string[];
  }, [job]);

  const mappingInitKey = (job?.id ?? "") + "|" + (job?.entity_type ?? "") + "|" + parsedColumns.join("|");

const missingRequiredMappings = useMemo(
    () => reqs.filter((r) => r.required && !mapping[r.key]),
    [reqs, mapping]
  );

    // Mapping initialization effect (deterministic: never setState during render)
  useEffect(() => {
    if (!job) return;
    if (mappingDirty) return;

    const meta: any = job.metadata ?? {};
    const saved = meta?.mapping && typeof meta.mapping === 'object' ? (meta.mapping as Mapping) : null;
    const suggested =
      meta?.suggested_mapping && typeof meta.suggested_mapping === 'object' ? (meta.suggested_mapping as Mapping) : null;

    const auto = suggestMapping(reqs, parsedColumns);
    setMapping(saved ?? { ...auto, ...(suggested ?? {}) });
  }, [job, mappingDirty, parsedColumns, reqs]);

async function loadAll() {
    if (!supabase) return;
    setError(null);

    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      router.push('/auth/sign-in');
      return;
    }

    const { data: nextJob, error: jobErr } = await supabase.rpc('get_import_job', {
      p_job_id: params.jobId,
    });

    if (jobErr) {
      setError(jobErr.message);
      return;
    }

    setJob(nextJob as ImportJob);

    const { data: nextRows, error: rowsErr } = await supabase.rpc('list_import_job_rows', {
      p_job_id: params.jobId,
      p_limit: 200,
    });

    if (rowsErr) {
      setError(rowsErr.message);
      return;
    }

    setRows((nextRows as ImportJobRow[]) ?? []);

    // Fetch canonical contract (DB is source of truth)
    try {
      const { data: contractRows, error: cErr } = await supabase.rpc('get_import_contract', {
        p_entity: (nextJob as any).entity_type,
      });
      if (!cErr) setContract((contractRows ?? []) as ContractRow[]);
    } catch {
      // non-fatal
    }
  }

  // Initial load
  useEffect(() => {
    (async () => {
      try {
        setLoading(true);
        await loadAll();
      } finally {
        setLoading(false);
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase, params.jobId]);

  // Initialize mapping once we have job + columns + contract
  useEffect(() => {
    if (!job) return;
    if (mappingDirty) return;

    const meta: any = job.metadata ?? {};
    const saved = meta?.mapping && typeof meta.mapping === 'object' ? (meta.mapping as Mapping) : null;
    const suggested =
      meta?.suggested_mapping && typeof meta.suggested_mapping === 'object'
        ? (meta.suggested_mapping as Mapping)
        : null;

    if (saved) {
      return;
    }

    if (parsedColumns.length && reqs.length) {
      const auto = suggestMapping(reqs, parsedColumns);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [job, parsedColumns.join('|'), reqs.map((r) => r.key).join('|'), mappingDirty]);

  async function parseCsv() {
    if (!supabase || !job) return;
    setError(null);
    setParseResult(null);

    try {
      setBusyParse(true);

      const {
        data: { session },
      } = await supabase.auth.getSession();
      const accessToken = session?.access_token;
      if (!accessToken) throw new Error('No active session');

      const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
      if (!url || !anon) throw new Error('Missing NEXT_PUBLIC_SUPABASE_URL/NEXT_PUBLIC_SUPABASE_ANON_KEY');

      const res = await fetch(`${url}/functions/v1/parse_csv_to_staging`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: anon,
          // IMPORTANT: Edge Function expects the user JWT in this header.
          'x-user-jwt': accessToken,
        },
        body: JSON.stringify({
          job_id: job.id,
          limit: 200,
          mapping: Object.keys(mapping).length ? mapping : null,
          p_entity_type: job.entity_type,
          entity_selection: (job.metadata as any)?.entity_selection ?? null,
        }),
      });

      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(json?.error ? `${json.error}${json.details ? `: ${json.details}` : ''}` : `HTTP ${res.status}`);
      }

      setParseResult(json);
      await loadAll();
    } catch (e: any) {
      setError(e?.message ?? 'Parse failed');
    } finally {
      setBusyParse(false);
    }
  }

  async function saveMappingAndValidate() {
    if (!supabase || !job) return;
    setError(null);

    try {
      setBusySave(true);
      const { error: saveErr } = await supabase.rpc('save_import_job_mapping', {
        p_job_id: job.id,
        p_mapping: mapping,
      });
      if (saveErr) throw saveErr;

      // Re-parse so validations apply against the explicit mapping.
      await parseCsv();
      setMappingDirty(false);
    } catch (e: any) {
      setError(e?.message ?? 'Failed to save mapping');
    } finally {
      setBusySave(false);
    }
  }

  async function importNow() {
    if (!supabase || !job) return;
    setError(null);
    setImportResult(null);

    try {
      setBusyImport(true);
      const { data, error: importErr } = await supabase.rpc('start_import_job', {
        p_job_id: job.id,
      });
      if (importErr) throw importErr;

      setImportResult(data);
      await loadAll();
    } catch (e: any) {
      setError(e?.message ?? 'Import failed');
    } finally {
      setBusyImport(false);
    }
  }

  async function recomputeCogs() {
    if (!supabase || !job) return;

    setBusyRecompute(true);
    setError(null);

    try {
      // Use org setting (deterministic), fallback to 30 if not present
      let wacDays = 30;
      const { data: srow, error: serr } = await supabase
        .from("org_cost_engine_settings")
        .select("wac_days")
        .eq("org_id", job.org_id)
        .maybeSingle();

      if (!serr && srow?.wac_days) wacDays = Number(srow.wac_days);

      const { data, error: e } = await supabase.rpc("apply_unit_economics_to_sales_job", {
        p_job_id: params.jobId,
        p_wac_days: wacDays,
      });

      if (e) throw e;

      setRecomputeResult(data ?? null);
      await loadAll();
    } catch (e: any) {
      setError(e?.message ?? "Failed to recompute COGS");
    } finally {
      setBusyRecompute(false);
    }
  }

  if (!supabase) {
    return <SetupRequired />;
  }

  if (loading) {
    return (
      <div className="container py-4">
        <div className="card panel-light p-4">Loading…</div>
      </div>
    );
  }

  if (!job) {
    return (
      <div className="container py-4">
        <div className="card panel-light p-4">Job not found.</div>
      </div>
    );
  }

  const status = job.status;
  const canImport = status === 'validated' || status === 'imported';

  return (
    <div className="container py-4">
      <div className="d-flex align-items-start justify-content-between flex-wrap gap-3">
        <div>
          <Link href="/dashboard/import" className="text-decoration-none">
            ← Back to Import Center
          </Link>
          <div className="h3 mb-1 mt-2">Import Job</div>
          <div className="text-muted">
            <span className="badge text-bg-secondary me-2">{job.entity_type}</span>
            <span className={`badge ${status === 'validated' ? 'text-bg-success' : 'text-bg-secondary'}`}>{status}</span>
          </div>
        </div>
        <div className="d-flex gap-2 flex-wrap">
          <button className="btn btn-outline-light" onClick={parseCsv} disabled={busyParse}>
            {busyParse ? 'Parsing…' : 'Parse / Validate'}
          </button>
          <button
            className="btn btn-primary"
            onClick={saveMappingAndValidate}
            disabled={busySave || busyParse || missingRequiredMappings.length > 0}
            title={missingRequiredMappings.length ? 'Map all required fields first' : undefined}
          >
            {busySave || busyParse ? 'Saving…' : 'Save mapping'}
          </button>
          <button className="btn btn-success" onClick={importNow} disabled={!canImport || busyImport}>
            {busyImport ? 'Importing…' : status === 'imported' ? 'Re-import (idempotent)' : 'Import'}
          </button>

          {job?.entity_type === 'sales' && job?.status === 'imported' && (
            <button
              className="btn btn-outline-secondary"
              onClick={recomputeCogs}
              disabled={busyRecompute || busyImport || busySave || busyParse}
            >
              {busyRecompute ? 'Recomputing…' : 'Recompute COGS'}
            </button>
          )}

        </div>
      </div>

      {error ? <div className="alert alert-danger mt-3">{error}</div> : null}

      <div className="card panel-light p-3 mt-3">
        <div className="h6 mb-2">File</div>
        <div className="text-muted">{job.original_filename}</div>
        <div className="small text-muted">
          Job ID: <span className="code-inline">{job.id}</span>
        </div>
      </div>

      <div className="card panel-light p-3 mt-3">
        <div className="d-flex align-items-center justify-content-between flex-wrap gap-2">
          <div>
            <div className="h6 mb-1">Column mapping</div>
            <div className="text-muted small">Map canonical fields to CSV columns. Templates are zero-mapping.</div>
          </div>
          {missingRequiredMappings.length ? (
            <div className="small text-warning">
              Missing mappings for: <span className="code-inline">{missingRequiredMappings.map((r) => r.key).join(', ')}</span>
            </div>
          ) : (
            <div className="small text-success">All required fields mapped.</div>
          )}
        </div>

        {reqs.length === 0 ? (
          <div className="text-muted mt-2">No contract for this entity yet.</div>
        ) : (
          <div className="table-responsive mt-3">
            <table className="table table-dark table-hover align-middle">
              <thead>
                <tr>
                  <th>Field</th>
                  <th>Required</th>
                  <th>Type</th>
                  <th>CSV column</th>
                </tr>
              </thead>
              <tbody>
                {reqs.map((r) => (
                  <tr key={r.key}>
                    <td className="fw-semibold">{r.label}</td>
                    <td>{r.required ? <span className="badge text-bg-warning">required</span> : <span className="text-muted">optional</span>}</td>
                    <td className="text-muted">{r.type}</td>
                    <td className="minw-240">
                      <select
                        className="form-select"
                        value={mapping[r.key] ?? ''}
                        onChange={(e) => {
                          setMapping((m) => ({ ...m, [r.key]: e.target.value }));
                          setMappingDirty(true);
                        }}
                      >
                        <option value="">(unmapped)</option>
                        {parsedColumns.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </select>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div className="d-flex gap-2 mt-2 flex-wrap">
          <button
            className="btn btn-outline-light btn-sm"
            onClick={() => {
              const auto = suggestMapping(reqs, parsedColumns);
              setMapping(auto);
              setMappingDirty(true);
            }}
          >
            Re-suggest mapping
          </button>
          <div className="text-muted small align-self-center">
            Saving writes to <span className="code-inline">import_jobs.metadata.mapping</span>.
                {recomputeResult && (
                  <div className="small text-secondary mt-2">
                    Last recompute: <span className="code-inline">{JSON.stringify(recomputeResult)}</span>
                  </div>
                )}

          </div>
        </div>
      </div>

      <div className="card panel-light p-3 mt-3">
        <div className="h6 mb-2">Parse / validate output</div>
        {parseResult ? (
          <pre className="mb-0 small ws-prewrap">
            {JSON.stringify(parseResult, null, 2)}
          </pre>
        ) : (
          <div className="text-muted">Run “Parse / Validate” to populate staged rows and validations.</div>
        )}
      </div>

      <div className="card panel-light p-3 mt-3">
        <div className="h6 mb-2">Import output</div>
        {importResult ? (
          <pre className="mb-0 small ws-prewrap">
            {JSON.stringify(importResult, null, 2)}
          </pre>
        ) : (
          <div className="text-muted">Once status is validated, click “Import”.</div>
        )}
      </div>

      <div className="card panel-light p-3 mt-3">
        <div className="d-flex align-items-center justify-content-between flex-wrap gap-2">
          <div>
            <div className="h6 mb-1">Row preview</div>
            <div className="text-muted small">Up to 200 staged rows.</div>
          </div>
          <div className="text-muted small">Rows: {rows.length}</div>
        </div>

        <div className="table-responsive mt-3">
          <table className="table table-dark table-hover align-middle">
            <thead>
              <tr>
                <th>#</th>
                <th>Valid</th>
                <th>Errors</th>
                <th>Parsed (snippet)</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const parsed = (r as any).parsed ?? {};
                const errText = renderErrors(r.errors);
                return (
                  <tr key={`${r.id}`}
                    className={r.is_valid ? '' : 'table-danger'}
                  >
                    <td className="text-nowrap">{(r as any).row_number ?? '—'}</td>
                    <td>{r.is_valid ? <span className="badge text-bg-success">ok</span> : <span className="badge text-bg-danger">invalid</span>}</td>
                    <td className="text-muted small">{errText || '—'}</td>
                    <td>
                      <pre className="mb-0 small ws-prewrap">
                        {JSON.stringify(parsed, null, 0).slice(0, 300)}
                        {JSON.stringify(parsed, null, 0).length > 300 ? '…' : ''}
                      </pre>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card panel-light p-3 mt-3">
        <div className="h6 mb-2">Job metadata (debug)</div>
        <pre className="mb-0 small ws-prewrap">
          {JSON.stringify(job.metadata, null, 2)}
        </pre>
      </div>
    </div>
  );
}
