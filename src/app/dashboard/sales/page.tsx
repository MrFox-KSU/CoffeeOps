"use client";

import { useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export default function SalesPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [rows, setRows] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);

  function readScope() {
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
    setOrgId(o);
    setBranchId(localStorage.getItem(`coffeeops.active_branch_id.${o}`) ?? "");
  }

  useEffect(() => {
    readScope();
    const fn = () => readScope();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setErr(null);
      if (!orgId) return;

      const { data, error } = await supabase.rpc("get_sales_daily", {
        p_org_id: orgId,
        p_limit: 60,
        p_branch_id: branchId ? branchId : null,
      });

      if (cancelled) return;
      if (error) setErr(error.message);
      else setRows((data ?? []) as any[]);
    })();
    return () => { cancelled = true; };
  }, [supabase, orgId, branchId]);

  return (
    <div className="container py-4">
      <h1 className="h3 mb-2">Sales</h1>
      <div className="small text-secondary mb-3">Daily trend (scoped)</div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="card">
        <div className="card-body">
          <div className="table-responsive">
            <table className="table table-light table-sm align-middle mb-0">
              <thead>
                <tr>
                  <th>Day</th>
                  <th className="text-end">Net Sales</th>
                  <th className="text-end">Invoices</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.day}>
                    <td>{r.day}</td>
                    <td className="text-end">{Number(r.net_sales).toFixed(2)}</td>
                    <td className="text-end">{r.invoices}</td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={3} className="text-secondary">No data.</td></tr>}
              </tbody>
            </table>
          </div>
          <div className="small text-secondary mt-2">Source: public.get_sales_daily()</div>
        </div>
      </div>
    </div>
  );
}
