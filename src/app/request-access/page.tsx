"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type OrgRow = { org_id: string; name: string; support_email: string };

export default function RequestAccessPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgs, setOrgs] = useState<OrgRow[]>([]);
  const [orgId, setOrgId] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data: userRes } = await supabase.auth.getUser();
      if (!userRes?.user) {
        router.replace("/auth/sign-in");
        return;
      }

      const { data, error } = await supabase.rpc("list_listed_orgs", { p_limit: 100 });
      if (cancelled) return;
      if (error) setErr(error.message);
      else setOrgs((data ?? []) as any);
    })();
    return () => { cancelled = true; };
  }, [supabase, router]);

  async function submit() {
    setBusy(true);
    setErr(null);
    setMsg(null);
    try {
      if (!orgId) throw new Error("Select or paste an org_id");
      const { error } = await supabase.rpc("request_org_access", { p_org_id: orgId });
      if (error) throw error;
      setMsg("Request submitted. Please wait for approval.");
      setTimeout(() => router.replace("/pending"), 800);
    } catch (e: any) {
      setErr(e?.message ?? "Failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-5">
      <div className="card">
        <div className="card-body">
          <h1 className="h4 mb-2">Request Access</h1>
          <div className="text-secondary mb-3">
            Choose a listed organization or paste an org ID shared by the admin.
          </div>

          {err && <div className="alert alert-danger ws-prewrap">{err}</div>}
          {msg && <div className="alert alert-success ws-prewrap">{msg}</div>}

          {orgs.length === 0 ? (
            <div className="alert alert-secondary">
              No organizations are currently listed. Paste an org ID provided by the admin.
            </div>
          ) : (
            <>
              <div className="mb-2 small text-secondary">Listed orgs</div>
              <select className="form-select mb-3" value={orgId} onChange={(e) => setOrgId(e.target.value)}>
                <option value="">Select…</option>
                {orgs.map(o => <option key={o.org_id} value={o.org_id}>{o.name}</option>)}
              </select>
            </>
          )}

          <div className="small text-secondary mb-2">Or paste org_id</div>
          <input className="form-control mb-3" value={orgId} onChange={(e) => setOrgId(e.target.value)} placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" />

          <button className="btn btn-primary" disabled={busy} onClick={submit}>
            {busy ? "Submitting…" : "Submit request"}
          </button>
        </div>
      </div>
    </div>
  );
}