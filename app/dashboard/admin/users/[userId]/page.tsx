"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type Daily = any;
type PV = any;
type Sess = any;

function fmtTs(s: any) {
  if (!s) return "-";
  try { return String(s).slice(0,19).replace("T"," "); } catch { return String(s); }
}
function fmtHrs(sec: any) {
  const n = Number(sec ?? 0);
  return `${(n/3600).toFixed(2)}h`;
}
function durationMins(started: any, endedOrLast: any) {
  if (!started || !endedOrLast) return "-";
  const a = new Date(started).getTime();
  const b = new Date(endedOrLast).getTime();
  if (!isFinite(a) || !isFinite(b) || b < a) return "-";
  return `${Math.round((b - a) / 60000)}m`;
}

export default function AdminUserDetailPage({ params }: { params: { userId: string } }) {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [user, setUser] = useState<any>(null);
  const [daily, setDaily] = useState<Daily[]>([]);
  const [pvs, setPvs] = useState<PV[]>([]);
  const [sessions, setSessions] = useState<Sess[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const loadAll = useCallback(async () => {
    setErr(null);

    const u = supabase.rpc("platform_list_users", { p_limit: 1000 });
    const d = supabase.rpc("platform_get_user_daily", { p_user_id: params.userId, p_days: 14 });
    const pv = supabase.rpc("platform_get_user_pageviews", { p_user_id: params.userId, p_days: 7 });
    const s = supabase.rpc("platform_list_user_sessions", { p_user_id: params.userId, p_limit: 50 });

    const [u1, d1, pv1, s1] = await Promise.all([u, d, pv, s]);

    if (u1.error) return setErr(u1.error.message);
    if (d1.error) return setErr(d1.error.message);
    if (pv1.error) return setErr(pv1.error.message);
    if (s1.error) return setErr(s1.error.message);

    const found = (u1.data ?? []).find((x: any) => String(x.user_id) === params.userId);
    setUser(found ?? null);
    setDaily((d1.data ?? []) as any);
    setPvs((pv1.data ?? []) as any);
    setSessions((s1.data ?? []) as any);
  }, [supabase, params.userId]);

  useEffect(() => { loadAll(); }, [loadAll]);

  const setStatus = useCallback(async (org_id: string, status: string) => {
    setBusy(true); setErr(null);
    try {
      const { error } = await supabase.rpc("platform_set_member_status", {
        p_org_id: org_id,
        p_user_id: params.userId,
        p_status: status,
      });
      if (error) throw error;
      await loadAll();
    } catch (e: any) {
      setErr(e?.message ?? "Failed");
    } finally {
      setBusy(false);
    }
  }, [supabase, params.userId, loadAll]);

  const setRoleKind = useCallback(async (org_id: string, kind: "admin" | "member") => {
    setBusy(true); setErr(null);
    try {
      const { error } = await supabase.rpc("platform_set_member_role_kind", {
        p_org_id: org_id,
        p_user_id: params.userId,
        p_kind: kind,
      });
      if (error) throw error;
      await loadAll();
    } catch (e: any) {
      setErr(e?.message ?? "Failed");
    } finally {
      setBusy(false);
    }
  }, [supabase, params.userId, loadAll]);

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between mb-3">
        <div>
          <h1 className="h3 m-0">User Detail</h1>
          <div className="text-secondary small">{params.userId}</div>
        </div>
        <Link className="btn btn-outline-secondary" href="/dashboard/admin/users">Back</Link>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-6">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Profile</div>
              {user ? (
                <>
                  <div><span className="text-secondary">Email:</span> <span className="fw-semibold">{user.email ?? "-"}</span></div>
                  <div><span className="text-secondary">Created:</span> {fmtTs(user.created_at)}</div>
                  <div><span className="text-secondary">Online:</span> {user.is_online ? "Yes" : "No"}</div>
                  <div><span className="text-secondary">Last seen:</span> {fmtTs(user.last_seen_at)}</div>
                </>
              ) : (
                <div className="text-secondary">User not found.</div>
              )}
            </div>
          </div>

          <div className="card mt-3">
            <div className="card-body">
              <div className="fw-semibold mb-2">Org memberships</div>
              {Array.isArray(user?.orgs) && user.orgs.length ? (
                <div className="table-responsive">
                  <table className="table table-light table-sm align-middle mb-0">
                    <thead>
                      <tr>
                        <th>Org</th>
                        <th>Status</th>
                        <th>Role</th>
                        <th className="text-end">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {user.orgs.map((m: any) => (
                        <tr key={m.org_id}>
                          <td className="fw-semibold">{m.org_name}</td>
                          <td>{m.status}</td>
                          <td>{m.role}</td>
                          <td className="text-end">
                            <button className="btn btn-success btn-sm me-2" disabled={busy} onClick={() => setStatus(m.org_id, "approved")}>Approve</button>
                            <button className="btn btn-outline-secondary btn-sm me-2" disabled={busy} onClick={() => setStatus(m.org_id, "suspended")}>Suspend</button>
                            <button className="btn btn-outline-secondary btn-sm me-2" disabled={busy} onClick={() => setRoleKind(m.org_id, "admin")}>Promote admin</button>
                            <button className="btn btn-outline-secondary btn-sm" disabled={busy} onClick={() => setRoleKind(m.org_id, "member")}>Demote normal</button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <div className="text-secondary">No org memberships.</div>
              )}
              <div className="small text-secondary mt-2">Role changes use DB mapping.</div>
            </div>
          </div>

          <div className="card mt-3">
            <div className="card-body">
              <div className="fw-semibold mb-2">Sessions (last 50)</div>
              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Org</th>
                      <th>Started</th>
                      <th>Last seen</th>
                      <th>Ended</th>
                      <th>Reason</th>
                      <th className="text-end">Duration</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sessions.map((s: any, i: number) => (
                      <tr key={i}>
                        <td className="fw-semibold">{s.org_name ?? s.org_id}</td>
                        <td className="text-secondary">{fmtTs(s.started_at)}</td>
                        <td className="text-secondary">{fmtTs(s.last_seen_at)}</td>
                        <td className="text-secondary">{fmtTs(s.ended_at)}</td>
                        <td className="text-secondary">{s.end_reason ?? (s.ended_at ? "-" : "open")}</td>
                        <td className="text-end">{durationMins(s.started_at, s.ended_at ?? s.last_seen_at)}</td>
                      </tr>
                    ))}
                    {sessions.length === 0 && <tr><td colSpan={6} className="text-secondary">No sessions.</td></tr>}
                  </tbody>
                </table>
              </div>
              <div className="small text-secondary mt-2">Timeout sessions close after 15 minutes of inactivity.</div>
            </div>
          </div>

        </div>

        <div className="col-12 col-lg-6">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Daily usage (14 days)</div>
              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Day</th>
                      <th className="text-end">Active</th>
                      <th className="text-end">Sessions</th>
                      <th className="text-end">Page views</th>
                    </tr>
                  </thead>
                  <tbody>
                    {daily.map((d: any) => (
                      <tr key={d.day}>
                        <td>{d.day}</td>
                        <td className="text-end">{fmtHrs(d.active_seconds)}</td>
                        <td className="text-end">{d.sessions}</td>
                        <td className="text-end">{d.page_views}</td>
                      </tr>
                    ))}
                    {daily.length === 0 && <tr><td colSpan={4} className="text-secondary">No data.</td></tr>}
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <div className="card mt-3">
            <div className="card-body">
              <div className="fw-semibold mb-2">Top pages (7 days)</div>
              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Day</th>
                      <th>Path</th>
                      <th className="text-end">Views</th>
                    </tr>
                  </thead>
                  <tbody>
                    {pvs.map((p: any) => (
                      <tr key={p.day + ":" + p.path}>
                        <td>{p.day}</td>
                        <td className="text-secondary">{p.path}</td>
                        <td className="text-end">{p.views}</td>
                      </tr>
                    ))}
                    {pvs.length === 0 && <tr><td colSpan={3} className="text-secondary">No page views.</td></tr>}
                  </tbody>
                </table>
              </div>
              <div className="small text-secondary mt-2">Tracked: /dashboard/* only.</div>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}