"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type Row = {
  org_id: string;
  org_name: string;
  user_id: string;
  user_email: string | null;
  role: string | null;
  requested_at: string;
};

export default function ApprovalsPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setErr(null);
    const { data, error } = await supabase.rpc("platform_list_pending_members", { p_limit: 200 });
    if (error) setErr(error.message);
    else setRows((data ?? []) as any);
  }, [supabase]);

  useEffect(() => { load(); }, [load]);

  const setStatus = useCallback(async (r: Row, status: "approved" | "rejected" | "suspended") => {
    setBusy(true);
    setErr(null);
    try {
      const { error } = await supabase.rpc("platform_set_member_status", {
        p_org_id: r.org_id,
        p_user_id: r.user_id,
        p_status: status,
      });
      if (error) throw error;
      await load();
    } catch (e: any) {
      setErr(e?.message ?? "Failed");
    } finally {
      setBusy(false);
    }
  }, [supabase, load]);

  return (
    <div className="container py-4">
      <h1 className="h3 mb-2">Approvals</h1>
      <div className="text-secondary mb-3">Approve pending users across all orgs (platform admin).</div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="card">
        <div className="card-body">
          <div className="table-responsive">
            <table className="table table-light table-sm align-middle mb-0">
              <thead>
                <tr>
                  <th>Org</th>
                  <th>User</th>
                  <th>Requested</th>
                  <th className="text-end">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.org_id + ":" + r.user_id}>
                    <td className="fw-semibold">{r.org_name}</td>
                    <td>{r.user_email ?? r.user_id}</td>
                    <td className="text-secondary">{String(r.requested_at).slice(0,19).replace("T"," ")}</td>
                    <td className="text-end">
                      <button className="btn btn-success btn-sm me-2" disabled={busy} onClick={() => setStatus(r, "approved")}>Approve</button>
                      <button className="btn btn-outline-secondary btn-sm me-2" disabled={busy} onClick={() => setStatus(r, "rejected")}>Reject</button>
                      <button className="btn btn-outline-secondary btn-sm" disabled={busy} onClick={() => setStatus(r, "suspended")}>Suspend</button>
                    </td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={4} className="text-secondary">No pending users.</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}