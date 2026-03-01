"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type OrgRow = {
  org_id: string;
  name: string;
  subscription_tier_code: string;
  is_listed: boolean;
  branch_count: number;
  support_email: string;
  created_at: string;
};

type Tier = { tier_code: string; name: string };

export default function OrgsAdminPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgs, setOrgs] = useState<OrgRow[]>([]);
  const [tiers, setTiers] = useState<Tier[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [newName, setNewName] = useState("");
  const [newTier, setNewTier] = useState("free");
  const [newListed, setNewListed] = useState(false);
  const [newOwnerEmail, setNewOwnerEmail] = useState("");

  const load = useCallback(async () => {
    setErr(null);
    const [o, t] = await Promise.all([
      supabase.rpc("platform_list_orgs", { p_limit: 500 }),
      supabase.from("subscription_tiers").select("tier_code,name").order("tier_code", { ascending: true }),
    ]);
    if (o.error) return setErr(o.error.message);
    if (t.error) return setErr(t.error.message);
    setOrgs((o.data ?? []) as any);
    setTiers((t.data ?? []) as any);
  }, [supabase]);

  useEffect(() => { load(); }, [load]);

  const createOrg = useCallback(async () => {
    setBusy(true);
    setErr(null);
    try {
      const payload: any = {
        p_name: newName,
        p_tier_code: newTier,
        p_is_listed: newListed,
      };
      if (newOwnerEmail && newOwnerEmail.trim().length > 0) payload.p_owner_email = newOwnerEmail.trim();

      const { error } = await supabase.rpc("platform_create_org", payload);
      if (error) throw error;

      setNewName("");
      setNewOwnerEmail("");
      setNewTier("free");
      setNewListed(false);

      await load();
    } catch (e: any) {
      setErr(e?.message ?? "Create org failed");
    } finally {
      setBusy(false);
    }
  }, [supabase, newName, newTier, newListed, newOwnerEmail, load]);

  const saveOrg = useCallback(async (org: OrgRow) => {
    setBusy(true);
    setErr(null);
    try {
      const { error } = await supabase.rpc("platform_update_org", {
        p_org_id: org.org_id,
        p_tier_code: org.subscription_tier_code,
        p_is_listed: org.is_listed,
      });
      if (error) throw error;
      await load();
    } catch (e: any) {
      setErr(e?.message ?? "Update failed");
    } finally {
      setBusy(false);
    }
  }, [supabase, load]);

  return (
    <div className="container py-4">
      <h1 className="h3 mb-2">Organizations</h1>
      <div className="text-secondary mb-3">Create orgs, set tier/listed, and manage members (platform admin).</div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="card mb-3">
        <div className="card-body">
          <div className="fw-semibold mb-2">Create organization</div>
          <div className="row g-2">
            <div className="col-12 col-lg-4">
              <input className="form-control" placeholder="Org name" value={newName} onChange={(e) => setNewName(e.target.value)} />
            </div>
            <div className="col-12 col-lg-3">
              <select className="form-select" value={newTier} onChange={(e) => setNewTier(e.target.value)}>
                {tiers.map(t => <option key={t.tier_code} value={t.tier_code}>{t.name}</option>)}
              </select>
            </div>
            <div className="col-12 col-lg-3">
              <input className="form-control" placeholder="Owner email (optional)" value={newOwnerEmail} onChange={(e) => setNewOwnerEmail(e.target.value)} />
            </div>
            <div className="col-12 col-lg-2 d-flex align-items-center gap-2">
              <label className="form-check m-0">
                <input className="form-check-input" type="checkbox" checked={newListed} onChange={(e) => setNewListed(e.target.checked)} />
                <span className="form-check-label">Listed</span>
              </label>
              <button className="btn btn-primary ms-auto" disabled={busy || !newName.trim()} onClick={createOrg}>
                {busy ? "Creating..." : "Create"}
              </button>
            </div>
          </div>
          <div className="small text-secondary mt-2">
            If owner email is set, that user is added as an approved org member.
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card-body">
          <div className="table-responsive">
            <table className="table table-light table-sm align-middle mb-0">
              <thead>
                <tr>
                  <th>Org</th>
                  <th className="text-end">Branches</th>
                  <th>Listed</th>
                  <th>Tier</th>
                  <th className="text-end">Actions</th>
                </tr>
              </thead>
              <tbody>
                {orgs.map((o) => (
                  <tr key={o.org_id}>
                    <td className="fw-semibold">{o.name}</td>
                    <td className="text-end">{o.branch_count}</td>
                    <td>
                      <input type="checkbox" checked={Boolean(o.is_listed)} onChange={(e) => {
                        const v = e.target.checked;
                        setOrgs(prev => prev.map(x => x.org_id===o.org_id ? { ...x, is_listed: v } : x));
                      }} />
                    </td>
                    <td style={{ width: 220 }}>
                      <select className="form-select form-select-sm" value={o.subscription_tier_code}
                        onChange={(e) => {
                          const v = e.target.value;
                          setOrgs(prev => prev.map(x => x.org_id===o.org_id ? { ...x, subscription_tier_code: v } : x));
                        }}
                      >
                        {tiers.map(t => <option key={t.tier_code} value={t.tier_code}>{t.name}</option>)}
                      </select>
                    </td>
                    <td className="text-end">
                      <Link className="btn btn-outline-secondary btn-sm me-2" href={`/dashboard/admin/orgs/${o.org_id}`}>Members</Link>
                      <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => saveOrg(o)}>Save</button>
                    </td>
                  </tr>
                ))}
                {orgs.length === 0 && <tr><td colSpan={5} className="text-secondary">No orgs.</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}