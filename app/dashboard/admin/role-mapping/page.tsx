"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export default function RoleMappingPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [labels, setLabels] = useState<string[]>([]);
  const [adminRole, setAdminRole] = useState<string>("");
  const [memberRole, setMemberRole] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const load = useCallback(async () => {
    setErr(null);
    setMsg(null);

    const [l, m] = await Promise.all([
      supabase.rpc("platform_list_org_role_labels"),
      supabase.rpc("platform_get_role_mappings"),
    ]);

    if (l.error) return setErr(l.error.message);
    if (m.error) return setErr(m.error.message);

    setLabels(((l.data ?? []) as any[]).map((x: any) => x.role_label));

    const map = (m.data ?? []) as any[];
    const a = map.find((x: any) => x.kind === "admin");
    const r = map.find((x: any) => x.kind === "member");
    setAdminRole(a?.role_label ?? "");
    setMemberRole(r?.role_label ?? "");
  }, [supabase]);

  useEffect(() => { load(); }, [load]);

  async function save(kind: "admin" | "member", role_label: string) {
    setBusy(true);
    setErr(null);
    setMsg(null);
    try {
      const { error } = await supabase.rpc("platform_set_role_mapping", {
        p_kind: kind,
        p_role_label: role_label,
      });
      if (error) throw error;
      setMsg("Saved mapping.");
      await load();
    } catch (e: any) {
      setErr(e?.message ?? "Save failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-4">
      <h1 className="h3 mb-2">Role Mapping</h1>
      <div className="text-secondary mb-3">
        Map admin and normal-user roles to org_role enum labels used by your database.
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}
      {msg && <div className="alert alert-success ws-prewrap">{msg}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-6">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Normal user mapping</div>
              <select className="form-select mb-3" value={memberRole} onChange={(e) => setMemberRole(e.target.value)}>
                <option value="">Select...</option>
                {labels.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
              <button className="btn btn-primary" disabled={busy || !memberRole} onClick={() => save("member", memberRole)}>
                {busy ? "Saving..." : "Save normal user"}
              </button>
            </div>
          </div>
        </div>

        <div className="col-12 col-lg-6">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Admin mapping</div>
              <select className="form-select mb-3" value={adminRole} onChange={(e) => setAdminRole(e.target.value)}>
                <option value="">Select...</option>
                {labels.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
              <button className="btn btn-primary" disabled={busy || !adminRole} onClick={() => save("admin", adminRole)}>
                {busy ? "Saving..." : "Save admin"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}