"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type Row = {
  occurred_at: string;
  actor_email: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  org_id: string | null;
  meta: any;
};

export default function AuditPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [days, setDays] = useState(30);
  const [limit, setLimit] = useState(200);
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const [keepSessions, setKeepSessions] = useState(90);
  const [keepDaily, setKeepDaily] = useState(180);
  const [keepAudit, setKeepAudit] = useState(365);
  const [purgeRes, setPurgeRes] = useState<any>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setErr(null);
    const { data, error } = await supabase.rpc("platform_list_audit", { p_days: days, p_limit: limit });
    if (error) setErr(error.message);
    else setRows((data ?? []) as any);
  }, [supabase, days, limit]);

  useEffect(() => { load(); }, [load]);

  async function purge() {
    setBusy(true);
    setErr(null);
    setPurgeRes(null);
    try {
      const { data, error } = await supabase.rpc("platform_purge_activity", {
        p_keep_sessions_days: keepSessions,
        p_keep_daily_days: keepDaily,
        p_keep_audit_days: keepAudit,
      });
      if (error) throw error;
      setPurgeRes(data);
      await load();
    } catch (e: any) {
      setErr(e?.message ?? "Purge failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-4">
      <h1 className="h3 mb-2">Audit and Retention</h1>
      <div className="text-secondary mb-3">Audit log plus retention purge (platform admin).</div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3 mb-3">
        <div className="col-12 col-lg-7">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Audit log</div>

              <div className="d-flex gap-2 flex-wrap mb-3">
                <input className="form-control form-control-sm" style={{ width: 140 }} type="number" value={days} onChange={(e) => setDays(Number(e.target.value))} />
                <input className="form-control form-control-sm" style={{ width: 140 }} type="number" value={limit} onChange={(e) => setLimit(Number(e.target.value))} />
                <button className="btn btn-outline-secondary btn-sm" onClick={load}>Refresh</button>
              </div>

              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Time</th>
                      <th>Actor</th>
                      <th>Action</th>
                      <th>Entity</th>
                      <th>Org</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r, i) => (
                      <tr key={i}>
                        <td className="text-secondary">{String(r.occurred_at).slice(0,19).replace("T"," ")}</td>
                        <td>{r.actor_email ?? "-"}</td>
                        <td className="fw-semibold">{r.action}</td>
                        <td className="text-secondary">{r.entity}:{r.entity_id ?? "-"}</td>
                        <td className="text-secondary">{r.org_id ?? "-"}</td>
                      </tr>
                    ))}
                    {rows.length === 0 && <tr><td colSpan={5} className="text-secondary">No audit rows.</td></tr>}
                  </tbody>
                </table>
              </div>

              <div className="small text-secondary mt-2">Membership requests appear as org_member_insert.</div>
            </div>
          </div>
        </div>

        <div className="col-12 col-lg-5">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Retention purge</div>

              <div className="mb-2 small text-secondary">Keep sessions (days)</div>
              <input className="form-control mb-2" type="number" value={keepSessions} onChange={(e) => setKeepSessions(Number(e.target.value))} />

              <div className="mb-2 small text-secondary">Keep daily aggregates and page views (days)</div>
              <input className="form-control mb-2" type="number" value={keepDaily} onChange={(e) => setKeepDaily(Number(e.target.value))} />

              <div className="mb-2 small text-secondary">Keep audit log (days)</div>
              <input className="form-control mb-3" type="number" value={keepAudit} onChange={(e) => setKeepAudit(Number(e.target.value))} />

              <button className="btn btn-danger w-100" disabled={busy} onClick={purge}>
                {busy ? "Purging..." : "Run purge"}
              </button>

              {purgeRes ? (
                <pre className="small text-secondary mt-3 ws-prewrap">{JSON.stringify(purgeRes, null, 2)}</pre>
              ) : null}
            </div>
          </div>
        </div>
      </div>

    </div>
  );
}