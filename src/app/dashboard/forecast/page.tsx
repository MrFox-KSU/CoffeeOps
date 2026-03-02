"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  // Fail loudly in dev so you don't get silent fetch errors.
  // In production, you already enforce these at build/deploy.
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY");
}
import { AreaChart, Area, CartesianGrid, XAxis, YAxis, Tooltip } from "recharts";

type RunRow = any;
type OutRow = any;

function useBoxWidth() {
  const ref = useRef<HTMLDivElement | null>(null);
  const [w, setW] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const upd = () => setW(el.clientWidth || 0);
    upd();
    const ro = new ResizeObserver(upd);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return { ref, w };
}

export default function ForecastPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState("");
  const [branchId, setBranchId] = useState<string | null>(null);

  const [ent, setEnt] = useState<any>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const [engine, setEngine] = useState<"github_free" | "paid_premium">("github_free");
  const [horizonDays, setHorizonDays] = useState(30);
  const [historyDays, setHistoryDays] = useState(365);

  const [runs, setRuns] = useState<RunRow[]>([]);
  const [activeRunId, setActiveRunId] = useState<string | null>(null);
  const [outputs, setOutputs] = useState<OutRow[]>([]);
  const [busyRun, setBusyRun] = useState(false);

  const { ref, w } = useBoxWidth();

  const readScope = useCallback(() => {
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
    setOrgId(o);
    if (o) setBranchId(localStorage.getItem(`coffeeops.active_branch_id.${o}`) ?? null);
    else setBranchId(null);
  }, []);

  useEffect(() => {
    readScope();
    const fn = () => readScope();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, [readScope]);

  const loadEnt = useCallback(async () => {
    if (!orgId) return;
    setErr(null);

    const a = await supabase.rpc("is_platform_admin");
    if (!a.error) setIsAdmin(Boolean(a.data));

    const e = await supabase.rpc("get_forecast_entitlements_v2", { p_org_id: orgId });
    if (e.error) {
      setErr(e.error.message);
      return;
    }
    const row = Array.isArray(e.data) ? e.data[0] : e.data;
    setEnt(row ?? null);

    // clamp defaults based on tier
    if (row?.max_forecast_horizon_days) setHorizonDays((v: number) => Math.min(v, Number(row.max_forecast_horizon_days)));
    if (row?.max_forecast_history_days) setHistoryDays((v: number) => Math.min(v, Number(row.max_forecast_history_days)));

    // If not admin, force free engine
    if (!Boolean(a.data)) setEngine("github_free");
  }, [supabase, orgId]);

  const loadRuns = useCallback(async () => {
    if (!orgId) return;
    setErr(null);

    let q = supabase
      .from("forecast_runs")
      .select("id,status,engine,visibility,created_at,started_at,finished_at,message,horizon_days,history_days,anchor_date,branch_id")
      .eq("org_id", orgId)
      .order("created_at", { ascending: false })
      .limit(25);

    if (branchId) q = q.eq("branch_id", branchId);

    const { data, error } = await q;
    if (error) setErr(error.message);
    else setRuns((data ?? []) as any[]);
  }, [supabase, orgId, branchId]);

  const loadOutputs = useCallback(async (runId: string) => {
    setErr(null);
    const { data, error } = await supabase
      .from("forecast_outputs")
      .select("day,p50_net_sales,p80_low,p80_high,p95_low,p95_high")
      .eq("run_id", runId)
      .order("day", { ascending: true });

    if (error) setErr(error.message);
    else setOutputs((data ?? []) as any[]);
  }, [supabase]);

  useEffect(() => { void loadEnt(); }, [loadEnt]);
  useEffect(() => { void loadRuns(); }, [loadRuns]);

  // Poll active run while queued/running
  useEffect(() => {
    if (!activeRunId) return;
    const r = runs.find(x => x.id === activeRunId);
    if (!r) return;
    const st = String(r.status || "");
    if (st !== "queued" && st !== "running") return;

    const t = setInterval(async () => {
      await loadRuns();
      await loadOutputs(activeRunId);
    }, 6000);

    return () => clearInterval(t);
  }, [activeRunId, runs, loadRuns, loadOutputs]);

  async function runForecast() {
    if (!orgId) return;
    setBusyRun(true);
    setErr(null);

    try {
      if (ent && ent.forecast_enabled === false && !isAdmin) {
        throw new Error(`Forecast is disabled for your tier (${ent.tier_code}).`);
      }

      if (!isAdmin) {
        // hard force free
        if (engine !== "github_free") setEngine("github_free");
      } else {
        // admin: if paid chosen, tier flag must be enabled
        if (engine === "paid_premium" && ent?.paid_forecast_enabled !== true) {
          throw new Error(`Paid premium is not enabled for tier (${ent?.tier_code}). Enable it in Admin â†’ Tiers.`);
        }
      }

      // user jwt
      const { data: s, error: se } = await supabase.auth.getSession();
      if (se) throw se;
      const token = s.session?.access_token;
      if (!token) throw new Error("No session token. Please sign in again.");

      const res = await fetch(`${SUPABASE_URL}/functions/v1/run_forecast`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": SUPABASE_ANON_KEY,
          "Authorization": `Bearer ${token}`,
        },
        body: JSON.stringify({
          org_id: orgId,
          branch_id: branchId,
          horizon_days: horizonDays,
          history_days: historyDays,
          engine,
        }),
      });

      const text = await res.text();
      if (!res.ok) throw new Error(`Forecast HTTP ${res.status}: ${text}`);
      const j = text ? JSON.parse(text) : null;

      if (j?.run_id) {
        setActiveRunId(j.run_id);
        await loadRuns();
        await loadOutputs(j.run_id);
      } else {
        await loadRuns();
      }
    } catch (e: any) {
      setErr(e?.message ?? "Forecast failed");
    } finally {
      setBusyRun(false);
    }
  }

  const canRun = Boolean(orgId) && (isAdmin || ent?.forecast_enabled !== false);

  const chartData = outputs.map((r: any) => ({
    day: String(r.day),
    p50: Number(r.p50_net_sales ?? 0),
    p80_low: Number(r.p80_low ?? 0),
    p80_high: Number(r.p80_high ?? 0),
  }));

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Forecast</h1>
          <div className="small text-secondary">
            GitHub-free engine trains per run. Paid premium is admin-only (stub for later).
          </div>
        </div>

        <div className="d-flex align-items-center gap-2 flex-wrap">
          <input className="form-control form-control-sm" style={{ width: 120 }} type="number"
            value={horizonDays}
            min={1}
            max={ent?.max_forecast_horizon_days ?? 365}
            onChange={(e) => setHorizonDays(Number(e.target.value))}
          />
          <input className="form-control form-control-sm" style={{ width: 140 }} type="number"
            value={historyDays}
            min={30}
            max={ent?.max_forecast_history_days ?? 3650}
            onChange={(e) => setHistoryDays(Number(e.target.value))}
          />

          {isAdmin ? (
            <select className="form-select form-select-sm" style={{ width: 210 }} value={engine} onChange={(e) => setEngine(e.target.value as any)}>
              <option value="github_free">GitHub Free (LGBM quantiles)</option>
              <option value="paid_premium" disabled={ent?.paid_forecast_enabled !== true}>Paid Premium (admin)</option>
            </select>
          ) : null}

          <button className="btn btn-primary" disabled={!canRun || busyRun} onClick={runForecast}>
            {busyRun ? "Running..." : "Run forecast"}
          </button>
        </div>
      </div>

      {ent ? (
        <div className="small text-secondary mb-2">
          Tier: <span className="fw-semibold">{ent.tier_code}</span> â€¢ Runs/day: {ent.max_forecast_runs_per_day} â€¢ Max horizon: {ent.max_forecast_horizon_days} â€¢ Max history: {ent.max_forecast_history_days}
        </div>
      ) : null}

      {ent && ent.forecast_enabled === false && !isAdmin ? (
        <div className="alert alert-warning">
          Forecast is disabled for your tier (<b>{ent.tier_code}</b>). Contact admin or upgrade tier.
        </div>
      ) : null}

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-4">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Recent runs</div>
              <div className="list-group">
                {runs.map((r) => (
                  <button
                    key={r.id}
                    className={`list-group-item list-group-item-action ${activeRunId === r.id ? "active" : ""}`}
                    onClick={async () => { setActiveRunId(r.id); await loadOutputs(r.id); }}
                  >
                    <div className="d-flex justify-content-between">
                      <span className="fw-semibold">{String(r.status).toUpperCase()}</span>
                      <span className="small">{String(r.created_at).slice(0,19).replace("T"," ")}</span>
                    </div>
                    <div className="small">engine: {r.engine} â€¢ H{r.horizon_days}/Hist{r.history_days}</div>
                    {r.message ? <div className="small text-secondary ws-prewrap">{r.message}</div> : null}
                  </button>
                ))}
                {runs.length === 0 ? <div className="text-secondary small">No runs yet.</div> : null}
              </div>
              <div className="small text-secondary mt-2">Source: forecast_runs</div>
              {activeRunId && (() => {
                const r = runs.find(x => x.id === activeRunId);
                if (!r) return null;
                const st = String(r.status || "");
                if (st !== "queued" && st !== "running") return null;
                return <div className="small text-secondary mt-2">Auto-refresh: every 6s while {st.toUpperCase()}.</div>;
              })()}

            </div>
          </div>
        </div>

        <div className="col-12 col-lg-8">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Forecast output (P50 with P80 band)</div>

              <div ref={ref} style={{ minWidth: 0 }}>
                {w <= 0 || chartData.length === 0 ? (
                  <div className="text-secondary">{(() => {
                      const r = activeRunId ? runs.find(x => x.id === activeRunId) : null;
                      const st = r ? String(r.status || "") : "";
                      if (st === "queued" || st === "running") {
                        return `No output yet. The run is ${st.toUpperCase()} — outputs appear when it completes.`;
                      }
                      return "No output yet. Select a run (or wait for it to finish).";
                    })()}</div>
                ) : (
                  <AreaChart width={w} height={320} data={chartData} margin={{ top: 10, right: 10, left: 10, bottom: 10 }}>
                    <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
                    <XAxis dataKey="day" />
                    <YAxis />
                    <Tooltip />
                    <Area type="monotone" dataKey="p80_high" stroke="transparent" fillOpacity={0.10} />
                    <Area type="monotone" dataKey="p80_low" stroke="transparent" fillOpacity={0.10} />
                    <Area type="monotone" dataKey="p50" stroke="#3B5BFF" fill="#3B5BFF" fillOpacity={0.15} />
                  </AreaChart>
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





