'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { SetupRequired } from '@/components/SetupRequired';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';
import type { Database } from '@/lib/supabase/types';
import { readCsvHeaders } from '@/lib/import/csv';
import { detectEntity, type ImportEntityType } from '@/lib/import/detect';
import { sanitizeFilename } from '@/lib/import/utils';

type Org = { id: string; name: string };
type ImportJob = Database['public']['Tables']['import_jobs']['Row'];

type EntitySelect = 'auto' | ImportEntityType;

function statusBadge(status: ImportJob['status']) {
  const base = 'badge rounded-pill';
  switch (status) {
    case 'uploaded':
      return <span className={`${base} text-bg-success`}>Uploaded</span>;
    case 'parsed':
      return <span className={`${base} text-bg-info`}>Parsed</span>;
    case 'validated':
      return <span className={`${base} text-bg-primary`}>Validated</span>;
    case 'imported':
      return <span className={`${base} text-bg-success`}>Imported</span>;
    case 'failed':
      return <span className={`${base} text-bg-danger`}>Failed</span>;
    default:
      return <span className={`${base} text-bg-secondary`}>{status}</span>;
  }
}

function formatWhen(ts: string) {
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return ts;
  return d.toLocaleString();
}

export default function ImportCenterPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);

  const [orgs, setOrgs] = useState<Org[]>([]);
  const [currentOrgId, setCurrentOrgId] = useState<string>('');
  // Keep Import Center synced with the global org switcher (DashboardShell)
  useEffect(() => {
    const sync = () => {
      const next = localStorage.getItem("coffeeops.active_org_id") ?? "";
      if (!next) return;
      setCurrentOrgId((prev: string) => (prev === next ? prev : next));
    };
    sync();
    window.addEventListener("coffeeops:scope", sync);
    return () => window.removeEventListener("coffeeops:scope", sync);
  }, []);
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [entitySelect, setEntitySelect] = useState<EntitySelect>('auto');
  const [file, setFile] = useState<File | null>(null);
  const [headers, setHeaders] = useState<string[]>([]);
  const [detection, setDetection] = useState<ReturnType<typeof detectEntity> | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  // Load orgs and select default
  useEffect(() => {
    if (!supabase) return;

    const run = async () => {
      setLoading(true);
      setError(null);

      const { data: userRes, error: userErr } = await supabase.auth.getUser();
      if (userErr) {
        setError(userErr.message);
        setLoading(false);
        return;
      }

      if (!userRes.user) {
        router.replace('/auth/sign-in');
        return;
      }

      const { data: orgRows, error: orgErr } = await supabase
        .rpc('list_orgs_for_dropdown');

      if (orgErr) {
        setError(orgErr.message);
        setLoading(false);
        return;
      }

      const o = ((orgRows ?? []) as any[]).map((r: any) => ({ id: (r.org_id ?? r.id) as string, name: r.name as string }));
      setOrgs(o);
      const savedOrg = localStorage.getItem("coffeeops.active_org_id");
      const nextOrg = (savedOrg && o.some((x: any) => x.id === savedOrg))
        ? savedOrg
        : (o[0]?.id ?? "");

      if (nextOrg) {
        // only set if empty; don't fight the global switcher
        setCurrentOrgId((prev: string) => (prev ? prev : nextOrg));
        if (!savedOrg) {
          localStorage.setItem("coffeeops.active_org_id", nextOrg);
          window.dispatchEvent(new Event("coffeeops:scope"));
        }
      }
const saved = typeof window !== 'undefined' ? window.localStorage.getItem('coffeeops.currentOrgId') : null;
      const defaultOrgId = saved && o.some((x) => x.id === saved) ? saved : o[0]?.id ?? '';
      setCurrentOrgId(defaultOrgId);

      setLoading(false);
    };

    void run();
  }, [router, supabase]);

  // Load jobs for current org
  useEffect(() => {
    if (!supabase) return;
    if (!currentOrgId) return;

    const run = async () => {
      setError(null);

      const { data, error: jobsErr } = await supabase.rpc('list_import_jobs', {
        p_org_id: currentOrgId,
        p_limit: 100
      });

      if (jobsErr) {
        setError(jobsErr.message);
        setJobs([]);
        return;
      }

      setJobs((data ?? []) as ImportJob[]);
    };

    void run();
  }, [currentOrgId, supabase]);

  function onOrgChange(next: string) {
    setCurrentOrgId(next);
    setJobs([]);
    if (typeof window !== 'undefined') {
      window.localStorage.setItem('coffeeops.currentOrgId', next);
    }
  }

  async function onPickFile(next: File | null) {
    setFile(next);
    setHeaders([]);
    setDetection(null);
    setUploadError(null);

    if (!next) return;

    try {
      const h = await readCsvHeaders(next);
      setHeaders(h);
      setDetection(detectEntity(h));
    } catch (e) {
      setUploadError(e instanceof Error ? e.message : 'Failed to read CSV headers');
    }
  }

  async function upload() {
    if (!supabase) return;
    if (!currentOrgId) {
      setUploadError('Create an organization first.');
      return;
    }
    if (!file) {
      setUploadError('Choose a CSV file first.');
      return;
    }

    setUploading(true);
    setUploadError(null);

    try {
      const detected = detection?.entity ?? 'unknown';
      const finalEntity: ImportEntityType = entitySelect === 'auto' ? detected : entitySelect;
      const jobId = crypto.randomUUID();

      const safeName = sanitizeFilename(file.name);
      const storagePath = `${currentOrgId}/${jobId}/${safeName}`;

      // 1) Upload to Storage
      const { error: uploadErr } = await supabase.storage.from('imports').upload(storagePath, file, {
        contentType: file.type || 'text/csv',
        upsert: false
      });

      if (uploadErr) throw uploadErr;

      // 2) Create DB job row via RPC
      const metadata = {
        headers,
        detection: detection,
        entity_selection: {
          mode: entitySelect,
          final: finalEntity
        }
      };

      const { data: job, error: jobErr } = await supabase.rpc('create_import_job', {
        p_job_id: jobId,
        p_org_id: currentOrgId,
        p_entity_type: finalEntity,
        p_original_filename: file.name,
        p_storage_path: storagePath,
        p_file_size: file.size,
        p_content_type: file.type || 'text/csv',
        p_metadata: metadata
      });

      if (jobErr) throw jobErr;

      // Refresh list and route to details
      const { data: refreshed, error: refreshErr } = await supabase.rpc('list_import_jobs', {
        p_org_id: currentOrgId,
        p_limit: 100
      });
      if (!refreshErr) setJobs((refreshed ?? []) as ImportJob[]);

      const jobIdFromDb = (job as ImportJob | null)?.id ?? jobId;
      router.push(`/dashboard/import/${jobIdFromDb}`);
    } catch (e) {
      setUploadError(e instanceof Error ? e.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  }

  if (!supabase) return <SetupRequired />;

  if (loading) {
    return (
      <div className="card panel-light p-4">

      <div className="card panel-light bg-dark border-secondary mb-3">
        <div className="card-body">
          <div className="d-flex align-items-center justify-content-between flex-wrap gap-2">
            <div>
              <div className="h6 mb-1">Download CSV templates</div>
              <div className="small text-secondary">
                Canonical headers (zero mapping). Fill rows then upload.
              </div>
            </div>
            <div className="d-flex flex-wrap gap-2">
              <a className="btn btn-outline-light btn-sm" href="/templates/products_template.csv" download>
                Products
              </a>
              <a className="btn btn-outline-light btn-sm" href="/templates/sales_lines_template.csv" download>
                Sales
              </a>
              <a className="btn btn-outline-light btn-sm" href="/templates/expenses_template.csv" download>
                Expenses
              </a>
              <a className="btn btn-outline-light btn-sm" href="/templates/labor_template.csv" download>
                Labor
              </a>
              <a className="btn btn-outline-info btn-sm" href="/templates/README_IMPORT_TEMPLATES.md" target="_blank" rel="noreferrer">
                Template guide
              </a>
            </div>
          </div>
        </div>
      </div>

        <div className="d-flex justify-content-between align-items-center">
          <div>
            <div className="small-muted">Loading</div>
            <div className="h5 mb-0">Import Centerâ€¦</div>
          </div>
          <div className="spinner-border" role="status" aria-label="loading" />
        </div>
      </div>
    );
  }

  const currentOrg = orgs.find((o) => o.id === currentOrgId) ?? null;

  return (
    <div className="d-flex flex-column gap-3">

      <div className="card panel-light bg-dark border-secondary mb-3">
        <div className="card-body">
          <div className="d-flex align-items-center justify-content-between flex-wrap gap-2">
            <div>
              <div className="h6 mb-1">Download CSV templates</div>
              <div className="small text-secondary">
                Canonical headers (zero mapping). Fill rows then upload.
              </div>
            </div>
            <div className="d-flex flex-wrap gap-2">
              <a className="btn btn-outline-light btn-sm" href="/templates/products_template.csv" download>Products</a>
              <a className="btn btn-outline-light btn-sm" href="/templates/sales_lines_template.csv" download>Sales</a>
              <a className="btn btn-outline-light btn-sm" href="/templates/expenses_template.csv" download>Expenses</a>
              <a className="btn btn-outline-light btn-sm" href="/templates/labor_template.csv" download>Labor</a>
              <a className="btn btn-outline-info btn-sm" href="/templates/README_IMPORT_TEMPLATES.md" target="_blank" rel="noreferrer">Template guide</a>
            </div>
          </div>
        </div>
      </div>

      <div className="d-flex flex-wrap justify-content-between align-items-end gap-2">
        <div>
          <div className="small-muted">Import Center</div>
          <h1 className="h3 mb-0">CSV uploads â†’ Import Jobs</h1>
        </div>
        <div className="d-flex gap-2">
          <Link href="/onboarding/org" className="btn btn-outline-light">
            Create org
          </Link>
        </div>
      </div>

      {error ? (
        <div className="card panel-light p-4">
          <div className="h5 mb-2">Backend not ready</div>
          <p className="text-muted mb-2">
            This page relies on the Iteration 2 migration. If you havenâ€™t run it yet, do this in Supabase SQL Editor:
          </p>
          <div className="text-muted">
            <span className="code-inline">supabase/migrations/0002_iteration2_import_center.sql</span>
          </div>
          <div className="small-muted mt-3">Error: {error}</div>
        </div>
      ) : null}

      {!currentOrg ? (
        <div className="card panel-light p-4">
          <div className="h5 mb-2">No organization found</div>
          <p className="text-muted mb-0">Create an org first (Iteration 1). Then you can start uploading CSV files.</p>
        </div>
      ) : (
        <div className="card panel-light p-4">
          <div className="d-flex flex-wrap justify-content-between align-items-center gap-2">
            <div>
              <div className="small-muted">Active org</div>
              <div className="h5 mb-0">{currentOrg.name}</div>
            </div>
            <div className="d-flex align-items-center gap-2">
              <span className="small-muted">Switch org</span>
              <select
                className="form-select form-select-sm maxw-360"
                value={currentOrgId}
                onChange={(e) => onOrgChange(e.target.value)}
              >
                {orgs.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <hr />

          <div className="row g-3">
            <div className="col-12 col-lg-7">
              <div className="p-3 border rounded-3 border-subtle">
                <div className="d-flex justify-content-between align-items-center mb-2">
                  <div>
                    <div className="small-muted">Step 1</div>
                    <div className="fw-semibold">Upload CSV</div>
                  </div>
                  <span className="badge rounded-pill">v1</span>
                </div>

                <div className="d-flex flex-column gap-2">
                  <input
                    className="form-control"
                    type="file"
                    accept=".csv,text/csv"
                    onChange={(e) => onPickFile(e.target.files?.[0] ?? null)}
                    disabled={uploading}
                  />

                  <div className="d-flex flex-wrap gap-2 align-items-center">
                    <div className="flex-grow-1">
                      <div className="small-muted">Entity type</div>
                      <select
                        className="form-select"
                        value={entitySelect}
                        onChange={(e) => setEntitySelect(e.target.value as EntitySelect)}
                        disabled={uploading}
                      >
                        <option value="auto">Auto-detect</option>
                        <option value="sales">Sales</option>
                        <option value="expenses">Expenses</option>
                        <option value="products">Products / recipes</option>
                        <option value="labor">Labor</option>
                        <option value="unknown">Unknown</option>
                      </select>
                    </div>
                    <div className="d-flex align-items-end">
                      <button className="btn btn-primary" onClick={upload} disabled={!file || uploading || !currentOrgId}>
                        {uploading ? 'Uploadingâ€¦' : 'Upload & Create Job'}
                      </button>
                    </div>
                  </div>

                  {detection ? (
                    <div className="mt-1">
                      <div className="small-muted">Detected</div>
                      <div className="d-flex flex-wrap gap-2 align-items-center">
                        <span className="badge text-bg-secondary">{detection.entity}</span>
                        <span className="badge text-bg-secondary">confidence: {detection.confidence}</span>
                        <span className="badge text-bg-secondary">score: {detection.score}</span>
                      </div>
                      {headers.length ? (
                        <div className="small-muted mt-2">
                          Headers ({headers.length}):{' '}
                          <span className="code-inline">{headers.slice(0, 8).join(', ')}</span>
                          {headers.length > 8 ? <span className="small-muted"> â€¦</span> : null}
                        </div>
                      ) : null}
                    </div>
                  ) : (
                    <div className="small-muted">Pick a CSV file to preview headers and auto-detect its type.</div>
                  )}

                  {uploadError ? (
                    <div className="alert alert-danger mb-0">{uploadError}</div>
                  ) : null}
                </div>
              </div>
            </div>
            <div className="col-12 col-lg-5">
              <div className="card panel-light p-3 no-shadow">
                <div className="small-muted">Pipeline</div>
                <div className="fw-semibold">Job status lifecycle</div>
                <div className="text-muted mt-2">
                  <span className="code-inline">uploaded</span> â†’ <span className="code-inline">parsed</span> â†’{' '}
                  <span className="code-inline">validated</span> â†’ <span className="code-inline">imported</span>
                  <br />
                  Or: <span className="code-inline">failed</span>
                </div>
                <div className="small-muted mt-3">
                  Iteration 4: Sales import v1 is now supported. Upload, parse/validate, then import into canonical tables.
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="card panel-light p-4">
        <div className="d-flex justify-content-between align-items-center">
          <div>
            <div className="small-muted">Import jobs</div>
            <div className="h5 mb-0">Files uploaded for this org</div>
          </div>
          <span className="badge rounded-pill">{jobs.length}</span>
        </div>

        <div className="table-responsive mt-3">
          <table className="table table-sm align-middle mb-0">
            <thead>
              <tr>
                <th>Status</th>
                <th>Entity</th>
                <th>File</th>
                <th>Created</th>
                <th className="text-end">Job</th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((j) => (
                <tr key={j.id}>
                  <td>{statusBadge(j.status)}</td>
                  <td className="fw-semibold">{j.entity_type}</td>
                  <td>
                    <Link className="text-decoration-none" href={`/dashboard/import/${j.id}`}>
                      {j.original_filename}
                    </Link>
                    <div className="small-muted">{j.storage_path}</div>
                  </td>
                  <td>{formatWhen(j.created_at)}</td>
                  <td className="text-end">
                    <Link className="btn btn-sm btn-outline-light" href={`/dashboard/import/${j.id}`}>
                      Open
                    </Link>
                  </td>
                </tr>
              ))}

              {jobs.length === 0 ? (
                <tr>
                  <td colSpan={5} className="text-muted">
                    No import jobs yet. Upload your first CSV above.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
