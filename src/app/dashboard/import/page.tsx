"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { detectEntity } from "@/lib/import/detect";

type ImportEntityType = "sales" | "expenses" | "products" | "labor" | "unknown";

export default function ImportCenterPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);

  const [orgId, setOrgId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  const [jobs, setJobs] = useState<any[]>([]);
  const [busy, setBusy] = useState(false);

  const [entitySelect, setEntitySelect] = useState<"auto" | ImportEntityType>("auto");
  const [file, setFile] = useState<File | null>(null);
  const [headers, setHeaders] = useState<string[]>([]);
  const [detected, setDetected] = useState<ImportEntityType>("unknown");

  const readScope = useCallback(() => {
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
    setOrgId(o);
  }, []);

  useEffect(() => {
    readScope();
    const fn = () => readScope();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, [readScope]);

  const loadJobs = useCallback(async () => {
    if (!orgId) return;
    setError(null);

    const { data, error: e } = await supabase.rpc("list_import_jobs", { p_org_id: orgId, p_limit: 100 });
    if (e) setError(e.message);
    else setJobs((data ?? []) as any[]);
  }, [supabase, orgId]);

  useEffect(() => { void loadJobs(); }, [loadJobs]);

  async function readCsvHeaders(f: File): Promise<string[]> {
    const txt = await f.text();
    const firstLine = (txt.split(/\r?\n/)[0] ?? "").trim();
    if (!firstLine) return [];
    return firstLine.split(",").map((x) => x.trim()).filter(Boolean);
  }

  async function onPickFile(f: File | null) {
    setFile(f);
    setHeaders([]);
    setDetected("unknown");
    if (!f) return;

    const h = await readCsvHeaders(f);
    setHeaders(h);

    try {
      const d = detectEntity(h);
      setDetected((d?.entity ?? "unknown") as ImportEntityType);
    } catch {
      setDetected("unknown");
    }
  }

  async function createJob() {
    if (!orgId) {
      setError("No active org selected. Use the org switcher in the top bar.");
      return;
    }
    if (!file) {
      setError("Pick a CSV file first.");
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const jobId =
        (globalThis.crypto && "randomUUID" in globalThis.crypto && (globalThis.crypto as any).randomUUID())
          ? (globalThis.crypto as any).randomUUID()
          : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

      const finalEntity: ImportEntityType = entitySelect === "auto" ? (detected ?? "unknown") : entitySelect;

      const storagePath = `${orgId}/${jobId}/${file.name}`;

      const up = await supabase.storage.from("imports").upload(storagePath, file, {
        contentType: file.type || "text/csv",
        upsert: true,
      });
      if (up.error) throw up.error;

      const meta = {
        headers,
        detection: { entity: detected, mode: entitySelect, final: finalEntity },
      };

      const { data: job, error: e1 } = await supabase.rpc("create_import_job", {
        p_job_id: jobId,
        p_org_id: orgId,
        p_entity_type: finalEntity,
        p_original_filename: file.name,
        p_storage_path: storagePath,
        p_file_size: file.size,
        p_content_type: file.type || "text/csv",
        p_metadata: meta,
      });
      if (e1) throw e1;

      await loadJobs();
      router.push(`/dashboard/import/${job.id}`);
    } catch (e: any) {
      setError(e?.message ?? "Failed to create import job.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Import Center</h1>
          <div className="small text-secondary">
            Active org (from switcher): <span className="code-inline">{orgId || "(none)"}</span>
          </div>
        </div>

        <div className="d-flex align-items-center gap-2 flex-wrap">
          <select className="form-select form-select-sm" style={{ width: 180 }}
            value={entitySelect}
            onChange={(e) => setEntitySelect(e.target.value as any)}
          >
            <option value="auto">Auto-detect</option>
            <option value="products">Products</option>
            <option value="sales">Sales</option>
            <option value="expenses">Expenses</option>
            <option value="labor">Labor</option>
          </select>

          <input
            className="form-control form-control-sm"
            style={{ width: 320 }}
            type="file"
            accept=".csv,text/csv"
            onChange={(e) => onPickFile(e.target.files?.[0] ?? null)}
          />

          <button className="btn btn-primary btn-sm" disabled={busy || !file} onClick={createJob}>
            {busy ? "Uploading..." : "Create import job"}
          </button>
        </div>
      </div>

      {error && <div className="alert alert-danger ws-prewrap">{error}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-5">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Detected</div>

              <div className="small text-secondary">
                Detected entity: <span className="code-inline">{detected}</span>
              </div>
              <div className="small text-secondary">
                Headers: <span className="code-inline">{headers.length ? headers.join(", ") : "(none)"}</span>
              </div>

              <hr className="my-3" />

              <div className="fw-semibold mb-2">Download CSV templates</div>
              <div className="small text-secondary mb-2">Canonical headers (zero mapping). Fill rows then upload.</div>

              <div className="d-flex flex-wrap gap-2">
                <a className="btn btn-outline-secondary btn-sm" href="/templates/products_template.csv" download>Products</a>
                <a className="btn btn-outline-secondary btn-sm" href="/templates/sales_lines_template.csv" download>Sales</a>
                <a className="btn btn-outline-secondary btn-sm" href="/templates/expenses_template.csv" download>Expenses</a>
                <a className="btn btn-outline-secondary btn-sm" href="/templates/labor_template.csv" download>Labor</a>
                <a className="btn btn-outline-info btn-sm" href="/templates/README_IMPORT_TEMPLATES.md" target="_blank" rel="noreferrer">Guide</a>
              </div>
            </div>
          </div>
        </div>

        <div className="col-12 col-lg-7">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Import jobs</div>

              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Created</th>
                      <th>Entity</th>
                      <th>Status</th>
                      <th>File</th>
                      <th className="text-end">Open</th>
                    </tr>
                  </thead>
                  <tbody>
                    {jobs.map((j) => (
                      <tr key={j.id}>
                        <td className="text-secondary">{String(j.created_at).slice(0, 19).replace("T", " ")}</td>
                        <td className="fw-semibold">{j.entity_type}</td>
                        <td className="text-secondary">{j.status}</td>
                        <td className="text-secondary">{j.original_filename}</td>
                        <td className="text-end">
                          <Link className="btn btn-outline-secondary btn-sm" href={`/dashboard/import/${j.id}`}>Open</Link>
                        </td>
                      </tr>
                    ))}
                    {jobs.length === 0 ? (
                      <tr><td colSpan={5} className="text-secondary">No import jobs yet.</td></tr>
                    ) : null}
                  </tbody>
                </table>
              </div>

              <div className="small text-secondary mt-2">Source: public.list_import_jobs()</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

