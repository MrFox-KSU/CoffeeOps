"use client";

import { useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export default function UnitEconomicsPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState<string>("");
  const [days, setDays] = useState<number>(30);
  const [rows, setRows] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const [seedBusy, setSeedBusy] = useState(false);
  const [seedMsg, setSeedMsg] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data, error } = await supabase
        .from("org_members")
        .select("org_id")
        .order("created_at", { ascending: true })
        .limit(1);

      if (cancelled) return;
      if (!error && data && data[0]?.org_id) setOrgId(data[0].org_id);
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase]);

  async function seedDemo() {
    if (!orgId) return;
    setSeedBusy(true);
    setSeedMsg(null);
    setErr(null);
    try {
      const { data, error } = await supabase.rpc("seed_cost_engine_demo", { p_org_id: orgId });
      if (error) throw error;
            const payload = (data && typeof data === "object" && !Array.isArray(data)) ? (data as any) : null;
      const anchor = payload?.anchor_date ? String(payload.anchor_date) : null;
      setSeedMsg("Seeded demo cost engine data" + (anchor ? ` (anchor ${anchor})` : "."));
    } catch (e: any) {
      setErr(e?.message ?? "Seed failed");
    } finally {
      setSeedBusy(false);
    }
  }

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setErr(null);
      if (!orgId) return;

      const { data, error } = await supabase.rpc("get_unit_economics_by_sku", { p_org_id: orgId, p_days: days, p_branch_id: (localStorage.getItem(`coffeeops.active_branch_id.${orgId}`) ?? "") || null });

      if (cancelled) return;
      if (error) setErr(error.message);
      else setRows((data ?? []) as any[]);
    })();

    return () => {
      cancelled = true;
    };
  }, [supabase, orgId, days]);

  const money = (n: any) => (n == null ? "â€”" : Number(n).toFixed(2));
  const pct = (n: any) => (n == null ? "â€”" : `${(Number(n) * 100).toFixed(1)}%`);

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Unit Economics</h1>
          <div className="small text-secondary">COGS includes material + packaging + labor + overhead</div>
        </div>

        <div className="d-flex align-items-center gap-2">
          <select className="form-select form-select-sm maxw-360" value={days} onChange={(e) => setDays(Number(e.target.value))}>
            <option value={7}>Last 7d</option>
            <option value={30}>Last 30d</option>
            <option value={90}>Last 90d</option>
          </select>

          <button className="btn btn-outline-secondary" onClick={seedDemo} disabled={seedBusy || !orgId}>
            {seedBusy ? "Seedingâ€¦" : "Seed demo cost data"}
          </button>
        </div>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}
      {seedMsg && <div className="alert alert-success">{seedMsg}</div>}

      <div className="card">
        <div className="card-body">
          <div className="table-responsive">
            <table className="table table-light table-sm align-middle mb-0">
              <thead>
                <tr>
                  <th>SKU</th>
                  <th>Product</th>
                  <th className="text-end">Units</th>
                  <th className="text-end">Net</th>
                  <th className="text-end">COGS</th>
                  <th className="text-end">GP</th>
                  <th className="text-end">GM%</th>
                  <th className="text-end">COGS/Unit</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.sku}>
                    <td className="text-secondary">{r.sku}</td>
                    <td>{r.product_name}</td>
                    <td className="text-end">{money(r.units_sold)}</td>
                    <td className="text-end">{money(r.net_sales)}</td>
                    <td className="text-end">{money(r.cogs_total)}</td>
                    <td className="text-end">{money(r.gross_profit)}</td>
                    <td className="text-end">{pct(r.gross_margin)}</td>
                    <td className="text-end">{money(r.cogs_per_unit)}</td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={8} className="text-secondary">No data yet.</td></tr>}
              </tbody>
            </table>
          </div>

          <div className="small text-secondary mt-2">Source: public.get_unit_economics_by_sku()</div>
        </div>
      </div>
    </div>
  );
}

