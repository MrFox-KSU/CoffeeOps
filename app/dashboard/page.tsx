"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

import { KpiCard } from "@/components/ui/KpiCard";
import { MonthlySalesProfitChart } from "@/components/charts/MonthlySalesProfitChart";
import { OperatingTrendChart } from "@/components/charts/OperatingTrendChart";
import { ExpenseMixChart } from "@/components/charts/ExpenseMixChart";
import { PriceVsCogsScatter } from "@/components/charts/PriceVsCogsScatter";

type ExecDailyRow = {
  day: string;
  net_sales: number;
  cogs_total: number;
  gross_profit: number;
  expenses_total: number;
  labor_total: number;
  net_profit: number;
  invoices: number;
  gross_margin: number | null;
};

export default function DashboardPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);

  const [orgId, setOrgId] = useState("");
  const [branchId, setBranchId] = useState<string | null>(null);

  const [err, setErr] = useState<string | null>(null);

  const [kpi, setKpi] = useState<any>(null);
  const [monthly, setMonthly] = useState<any[]>([]);
  const [daily90, setDaily90] = useState<any[]>([]);
  const [expenseMix, setExpenseMix] = useState<any[]>([]);
  const [unitRows, setUnitRows] = useState<any[]>([]);

  const readScope = useCallback(() => {
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
    setOrgId(o);

    if (!o) {
      setBranchId(null);
      return;
    }
    const b = localStorage.getItem(`coffeeops.active_branch_id.${o}`) ?? "";
    setBranchId(b ? b : null);
  }, []);

  useEffect(() => {
    readScope();
    const fn = () => readScope();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, [readScope]);

  const loadAll = useCallback(async () => {
    setErr(null);
    if (!orgId) return;

    const [d30, d365, d90, ex, ue] = await Promise.all([
      supabase.rpc("get_exec_daily", { p_org_id: orgId, p_branch_id: (branchId || undefined), p_days: 30 }),
      supabase.rpc("get_exec_daily", { p_org_id: orgId, p_branch_id: (branchId || undefined), p_days: 365 }),
      supabase.rpc("get_exec_daily", { p_org_id: orgId, p_branch_id: (branchId || undefined), p_days: 90 }),
      supabase.rpc("get_expense_category_mix", { p_org_id: orgId, p_branch_id: (branchId || undefined), p_days: 30, p_limit: 10 }),
      supabase.rpc("get_unit_economics_by_sku_branch", { p_org_id: orgId, p_branch_id: (branchId || undefined), p_days: 30 }),
    ]);

    if (d30.error) return setErr(d30.error.message);
    if (d365.error) return setErr(d365.error.message);
    if (d90.error) return setErr(d90.error.message);
    if (ex.error) return setErr(ex.error.message);
    if (ue.error) return setErr(ue.error.message);

    const rows30 = (d30.data ?? []) as any[];
    const rows365 = (d365.data ?? []) as any[];
    const rows90 = (d90.data ?? []) as any[];

    // KPI aggregation (last 30d)
    const sum = (arr: any[], k: string) => arr.reduce((a, r) => a + Number(r?.[k] ?? 0), 0);
    const netSales = sum(rows30, "net_sales");
    const cogs = sum(rows30, "cogs_total");
    const gp = netSales - cogs;
    const expenses = sum(rows30, "expenses_total");
    const labor = sum(rows30, "labor_total");
    const np = gp - expenses - labor;
    const invoices = sum(rows30, "invoices");
    const gm = netSales === 0 ? null : gp / netSales;
    const avgTicket = invoices === 0 ? null : netSales / invoices;

    setKpi({
      net_sales: netSales,
      cogs_total: cogs,
      gross_profit: gp,
      gross_margin: gm,
      expenses_total: expenses,
      labor_total: labor,
      net_profit: np,
      invoices,
      avg_ticket: avgTicket,
    });

    // Monthly from daily365 (branch-aware)
    const byMonth = new Map<string, { month: string; net_sales: number; gross_profit: number }>();
    for (const r of rows365) {
      const d = String(r.day);
      const month = d.slice(0, 7); // YYYY-MM
      if (!byMonth.has(month)) byMonth.set(month, { month, net_sales: 0, gross_profit: 0 });
      const m = byMonth.get(month)!;
      const ns = Number(r.net_sales ?? 0);
      const gp2 = Number(r.gross_profit ?? (Number(r.net_sales ?? 0) - Number(r.cogs_total ?? 0)));
      m.net_sales += ns;
      m.gross_profit += gp2;
    }
    const monthlyArr = Array.from(byMonth.values()).sort((a, b) => a.month.localeCompare(b.month)).slice(-12);
    setMonthly(monthlyArr);

    // Trend (90d)
    setDaily90(rows90.map((r: any) => ({
      day: String(r.day),
      net_sales: Number(r.net_sales ?? 0),
      cogs_total: Number(r.cogs_total ?? 0),
      expenses_total: Number(r.expenses_total ?? 0),
      labor_total: Number(r.labor_total ?? 0),
      net_profit: Number(r.net_profit ?? 0),
    })));

    setExpenseMix((ex.data ?? []) as any[]);
    setUnitRows((ue.data ?? []) as any[]);
  }, [supabase, orgId, branchId]);

  useEffect(() => { void loadAll(); }, [loadAll]);

  const money = (n: any) => (n == null ? "-" : Number(n).toFixed(2));
  const pct = (n: any) => (n == null ? "-" : `${(Number(n) * 100).toFixed(1)}%`);

  const scatterData = [...unitRows]
    .filter((r: any) => r.avg_price != null && r.cogs_per_unit != null)
    .sort((a: any, b: any) => Number(b.units_sold ?? 0) - Number(a.units_sold ?? 0))
    .slice(0, 25);

  const topProfit = [...unitRows]
    .sort((a: any, b: any) => Number(b.gross_profit ?? 0) - Number(a.gross_profit ?? 0))
    .slice(0, 12);

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Executive Overview</h1>
          <div className="small text-secondary">
            Scoped by Org + Branch switcher. Org: <span className="code-inline">{orgId || "(none)"}</span>
            {branchId ? <> â€¢ Branch: <span className="code-inline">{branchId}</span></> : <> â€¢ Branch: <span className="code-inline">ALL</span></>}
          </div>
        </div>

        <div className="d-flex gap-2">
          <button className="btn btn-outline-secondary btn-sm" onClick={loadAll} disabled={!orgId}>
            Refresh
          </button>
        </div>
      </div>

      {!orgId ? (
        <div className="alert alert-warning">
          Select an organization from the top switcher to load the dashboard.
        </div>
      ) : null}

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      {orgId ? (
        <>
          <div className="row g-3 mb-3">
            <div className="col-12 col-lg-2"><KpiCard label="Net Sales" value={money(kpi?.net_sales)} sublabel={`${kpi?.invoices ?? 0} inv`} /></div>
            <div className="col-12 col-lg-2"><KpiCard label="COGS" value={money(kpi?.cogs_total)} /></div>
            <div className="col-12 col-lg-2"><KpiCard label="Gross Profit" value={money(kpi?.gross_profit)} /></div>
            <div className="col-12 col-lg-2"><KpiCard label="Gross Margin" value={pct(kpi?.gross_margin)} /></div>
            <div className="col-12 col-lg-2"><KpiCard label="Expenses" value={money(kpi?.expenses_total)} tone="warn" /></div>
            <div className="col-12 col-lg-2"><KpiCard label="Net Profit" value={money(kpi?.net_profit)} tone={Number(kpi?.net_profit ?? 0) >= 0 ? "good" : "bad"} /></div>
          </div>

          <div className="row g-3">
            <div className="col-12">
              <div className="card">
                <div className="card-body">
                  <div className="fw-semibold">Monthly sales + profit (last 12 months)</div>
                  <div className="small text-secondary mb-2">
                    If sales is stable but profit drops, costs are drifting (COGS/overhead/expenses/labor).
                  </div>
                  <MonthlySalesProfitChart data={monthly} />
                </div>
              </div>
            </div>

            <div className="col-12">
              <div className="card">
                <div className="card-body">
                  <div className="fw-semibold">Operating trend (daily, last 90d)</div>
                  <div className="small text-secondary mb-2">
                    Shows what is squeezing profit: COGS (incl overhead), expenses, and labor vs net sales.
                  </div>
                  <OperatingTrendChart data={daily90} />
                </div>
              </div>
            </div>

            <div className="col-12 col-lg-6">
              <div className="card">
                <div className="card-body">
                  <div className="fw-semibold">Expense mix (last 30d)</div>
                  <div className="small text-secondary mb-2">
                    Which categories consume cash. Use this to target cost reductions with minimal revenue impact.
                  </div>
                  <ExpenseMixChart data={expenseMix} />
                </div>
              </div>
            </div>

            <div className="col-12 col-lg-6">
              <div className="card">
                <div className="card-body">
                  <div className="fw-semibold">Price vs COGS/Unit (top 25 SKUs by units)</div>
                  <div className="small text-secondary mb-2">
                    Items with high COGS/Unit relative to price are margin risks. Low COGS/Unit + high price are margin engines.
                  </div>
                  <PriceVsCogsScatter data={scatterData} />
                </div>
              </div>
            </div>

            <div className="col-12">
              <div className="card">
                <div className="card-body">
                  <div className="fw-semibold">Top SKUs by gross profit (last 30d)</div>
                  <div className="small text-secondary mb-2">
                    These are the products paying your bills. If a high-volume SKU is missing here, it may be underpriced or high-cost.
                  </div>

                  <div className="table-responsive">
                    <table className="table table-light table-sm align-middle mb-0">
                      <thead>
                        <tr>
                          <th>SKU</th>
                          <th>Product</th>
                          <th className="text-end">Units</th>
                          <th className="text-end">Avg Price</th>
                          <th className="text-end">COGS/Unit</th>
                          <th className="text-end">Gross Profit</th>
                          <th className="text-end">Margin</th>
                        </tr>
                      </thead>
                      <tbody>
                        {topProfit.map((r: any) => (
                          <tr key={r.sku}>
                            <td className="text-secondary">{r.sku}</td>
                            <td className="fw-semibold">{r.product_name}</td>
                            <td className="text-end">{money(r.units_sold)}</td>
                            <td className="text-end">{money(r.avg_price)}</td>
                            <td className="text-end">{money(r.cogs_per_unit)}</td>
                            <td className="text-end">{money(r.gross_profit)}</td>
                            <td className="text-end">{pct(r.gross_margin)}</td>
                          </tr>
                        ))}
                        {topProfit.length === 0 ? (
                          <tr><td colSpan={7} className="text-secondary">No unit economics rows yet.</td></tr>
                        ) : null}
                      </tbody>
                    </table>
                  </div>

                </div>
              </div>
            </div>

          </div>
        </>
      ) : null}
    </div>
  );
}
