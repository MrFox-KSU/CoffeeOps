"use client";

import { useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { KpiCard } from "@/components/ui/KpiCard";
import { MonthlySalesProfitChart } from "@/components/charts/MonthlySalesProfitChart";

export default function DashboardPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState<string>("");
  const [branchId, setBranchId] = useState<string>("");

  const [days, setDays] = useState<number>(30);
  const [cogsMode, setCogsMode] = useState<"engine" | "unit_cost" | "none">("engine");

  const [kpis, setKpis] = useState<any>(null);
  const [months, setMonths] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);

  function readScope() {
    setOrgId(localStorage.getItem("coffeeops.active_org_id") ?? "");
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
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

      const b = branchId ? branchId : null;

      const [{ data: k, error: e1 }, { data: m, error: e2 }] = await Promise.all([
        supabase.rpc("get_exec_kpis", { p_org_id: orgId, p_days: days, p_cogs_mode: cogsMode, p_branch_id: b }),
        supabase.rpc("get_exec_monthly", { p_org_id: orgId, p_months: 12, p_cogs_mode: cogsMode, p_branch_id: b }),
      ]);

      if (cancelled) return;
      if (e1) return setErr(e1.message);
      if (e2) return setErr(e2.message);

      setKpis(k);
      setMonths((m ?? []).map((r: any) => ({
        month: String(r.month).slice(0, 7),
        net_sales: Number(r.net_sales),
        gross_profit: Number(r.gross_profit),
      })));
    })();

    return () => { cancelled = true; };
  }, [supabase, orgId, branchId, days, cogsMode]);

  const money = (n: any) => (n == null ? "—" : Number(n).toFixed(2));

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Executive Overview</h1>
          <div className="small text-secondary">Scoped by Org + Branch dropdown</div>
        </div>

        <div className="d-flex gap-2">
          <select className="form-select form-select-sm" style={{ width: 160 }} value={days} onChange={(e) => setDays(Number(e.target.value))}>
            <option value={7}>Last 7d</option>
            <option value={30}>Last 30d</option>
            <option value={90}>Last 90d</option>
          </select>

          <select className="form-select form-select-sm" style={{ width: 220 }} value={cogsMode} onChange={(e) => setCogsMode(e.target.value as any)}>
            <option value="engine">COGS: Unit economics engine</option>
            <option value="unit_cost">COGS: products.unit_cost</option>
            <option value="none">COGS: none</option>
          </select>
        </div>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-3">
          <KpiCard label="Net Sales" value={money(kpis?.net_sales)} sublabel={`${kpis?.invoices ?? 0} inv`} />
        </div>
        <div className="col-12 col-lg-3">
          <KpiCard label="COGS" value={money(kpis?.cogs)} />
        </div>
        <div className="col-12 col-lg-3">
          <KpiCard label="Gross Profit" value={money(kpis?.gross_profit)} />
        </div>
        <div className="col-12 col-lg-3">
          <KpiCard label="Gross Margin" value={kpis?.gross_margin == null ? "—" : `${(Number(kpis.gross_margin) * 100).toFixed(1)}%`} />
        </div>

        <div className="col-12">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold">Last 12 months</div>
              <div className="small text-secondary mb-2">Net Sales vs Gross Profit</div>
              <MonthlySalesProfitChart data={months} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
