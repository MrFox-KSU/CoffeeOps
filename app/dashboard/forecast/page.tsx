"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, Legend } from "recharts";

type RunRow = {
  id: string;
  created_at: string;
  status: string;
  horizon_days: number;
  history_days: number;
  anchor_date: string;
  model: string;
  message: string | null;
};

export default function ForecastPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState<string>("");
  const [branchId, setBranchId] = useState<string>("");

  const [runs, setRuns] = useState<RunRow[]>([]);
  const [activeRunId, setActiveRunId] = useState<string>("");
  const [series, setSeries] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // chart sizing
  const chartRef = useRef<HTMLDivElement | null>(null);
  const [chartW, setChartW] = useState(0);

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
    const el = chartRef.current;
    if (!el) return;
    const update = () => setChartW(el.clientWidth || 0);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  async function loadRuns() {
    if (!orgId) return;
    const { data, error } = await supabase.rpc("list_forecast_runs", {
      p_org_id: orgId,
      p_limit: 20,
      p_branch_id: branchId ? branchId : null,
    });
    if (error) return setErr(error.message);

    const rr = (data ?? []) as any[];
    setRuns(rr);
    if (!activeRunId && rr[0]?.id) setActiveRunId(rr[0].id);
  }

  useEffect(() => {
    setErr(null);
    loadRuns();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orgId, branchId]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setErr(null);
      if (!activeRunId) {
        setSeries([]);
        return;
      }
      const { data, error } = await supabase.rpc("get_forecast_outputs", { p_run_id: activeRunId });
      if (cancelled) return;
      if (error) setErr(error.message);
      else {
        setSeries(
          (data ?? []).map((r: any) => ({
            day: r.day,
            p50: Number(r.p50_net_sales),
            p95_low: Number(r.p95_low),
            p95_high: Number(r.p95_high),
          }))
        );
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase, activeRunId]);

  async function runForecast() {
    if (!orgId) return;
    setBusy(true);
    setErr(null);

    try {
      const { data: sess, error: sessErr } = await supabase.auth.getSession();
      if (sessErr) throw sessErr;

      const token = sess.session?.access_token;
      if (!token) throw new Error("Not signed in");

      const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "") + "/functions/v1/run_forecast";
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
          "x-user-jwt": token,
        },
        body: JSON.stringify({
          org_id: orgId,
          branch_id: branchId ? branchId : null,
          horizon_days: 30,
          history_days: 365,
        }),
      });

      const text = await res.text();
      if (!res.ok) throw new Error(`Forecast HTTP ${res.status}: ${text}`);

      await loadRuns();
    } catch (e: any) {
      setErr(e?.message ?? "Forecast failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between mb-3">
        <div>
          <h1 className="h3 m-0">Forecast</h1>
          <div className="small text-secondary">Branch-scoped runs (All branches uses branch_id = null)</div>
        </div>
        <button className="btn btn-primary" onClick={runForecast} disabled={busy || !orgId}>
          {busy ? "Running…" : "Run forecast"}
        </button>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-4">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Runs</div>
              <div className="list-group">
                {runs.map((r) => (
                  <button
                    key={r.id}
                    className={"list-group-item list-group-item-action " + (r.id === activeRunId ? "active" : "")}
                    onClick={() => setActiveRunId(r.id)}
                  >
                    <div className="d-flex justify-content-between">
                      <span>{String(r.created_at).slice(0, 19).replace("T", " ")}</span>
                      <span className="badge text-bg-secondary">{r.status}</span>
                    </div>
                    <div className="small opacity-75">{r.message ?? `${r.model} • ${r.horizon_days}d`}</div>
                  </button>
                ))}
                {runs.length === 0 && <div className="text-secondary small">No runs yet.</div>}
              </div>
            </div>
          </div>
        </div>

        <div className="col-12 col-lg-8">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Forecast Net Sales</div>

              <div ref={chartRef} className="chart-320" style={{ minWidth: 0 }}>
                {chartW <= 0 ? (
                  <div className="chart-320" />
                ) : (
                  <LineChart width={chartW} height={320} data={series} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
                    <XAxis dataKey="day" tick={{ fontSize: 12 }} />
                    <YAxis tick={{ fontSize: 12 }} />
                    <Tooltip />
                    <Legend />
                    <Line type="monotone" dataKey="p50" name="P50" stroke="#4361ee" dot={false} />
                    <Line type="monotone" dataKey="p95_low" name="P95 Low" stroke="#94a3b8" dot={false} />
                    <Line type="monotone" dataKey="p95_high" name="P95 High" stroke="#94a3b8" dot={false} />
                  </LineChart>
                )}
              </div>

              <div className="small text-secondary mt-2">Source: forecast_outputs</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}