"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type UserRow = any;

function fmtTs(s: any) {
  if (!s) return "-";
  try { return String(s).slice(0,19).replace("T"," "); } catch { return String(s); }
}

export default function AdminUsersPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [rows, setRows] = useState<UserRow[]>([]);
  const [q, setQ] = useState("");
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setErr(null);
    const { data, error } = await supabase.rpc("platform_list_users", { p_limit: 500 });
    if (error) setErr(error.message);
    else setRows((data ?? []) as any);
  }, [supabase]);

  useEffect(() => { load(); }, [load]);

  const filtered = rows.filter((r) => {
    const s = String((r.email ?? r.user_id) ?? "").toLowerCase();
    return q.trim() === "" || s.includes(q.trim().toLowerCase());
  });

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Users</h1>
          <div className="text-secondary small">System-wide directory (platform admin).</div>
        </div>

        <div className="d-flex align-items-center gap-2">
          <input
            className="form-control form-control-sm"
            style={{ width: 280 }}
            placeholder="Search email..."
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
          <button className="btn btn-outline-secondary btn-sm" onClick={load}>Refresh</button>
        </div>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="card">
        <div className="card-body">
          <div className="table-responsive">
            <table className="table table-light table-sm align-middle mb-0">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Created</th>
                  <th>Online</th>
                  <th>Last seen</th>
                  <th>Memberships</th>
                  <th className="text-end">Action</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((u) => (
                  <tr key={u.user_id}>
                    <td>
                      <div className="fw-semibold">{u.email ?? "(no email)"}</div>
                      <div className="small text-secondary">{u.user_id}</div>
                    </td>
                    <td className="text-secondary">{fmtTs(u.created_at)}</td>
                    <td>
                      {u.is_online ? <span className="badge text-bg-success">Online</span> : <span className="badge text-bg-secondary">Offline</span>}
                    </td>
                    <td className="text-secondary">{fmtTs(u.last_seen_at)}</td>
                    <td>
                      {Array.isArray(u.orgs) && u.orgs.length ? (
                        <div className="d-flex flex-column gap-1">
                          {u.orgs.slice(0, 3).map((m: any) => (
                            <div key={m.org_id} className="small">
                              <span className="fw-semibold">{m.org_name}</span>{" "}
                              <span className="text-secondary">({m.status}, {m.role})</span>
                            </div>
                          ))}
                          {u.orgs.length > 3 ? <div className="small text-secondary">+{u.orgs.length - 3} more</div> : null}
                        </div>
                      ) : (
                        <span className="text-secondary small">None</span>
                      )}
                    </td>
                    <td className="text-end">
                      <Link className="btn btn-primary btn-sm" href={`/dashboard/admin/users/${u.user_id}`}>View</Link>
                    </td>
                  </tr>
                ))}
                {filtered.length === 0 && <tr><td colSpan={6} className="text-secondary">No users found.</td></tr>}
              </tbody>
            </table>
          </div>

          <div className="small text-secondary mt-2">
            Online means last activity within 2 minutes (heartbeat).
          </div>
        </div>
      </div>
    </div>
  );
}

