"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type Tier = any;

export default function TiersPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [tiers, setTiers] = useState<Tier[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setErr(null);
    const { data, error } = await supabase.from("subscription_tiers").select("*").order("tier_code", { ascending: true });
    if (error) setErr(error.message);
    else setTiers((data ?? []) as any);
  }, [supabase]);

  useEffect(() => { load(); }, [load]);

  const save = useCallback(async (t: Tier) => {
    setBusy(true);
    setErr(null);
    try {
      const payload: any = {
        name: t.name,
        max_branches: t.max_branches,
        max_benchmark_plots: t.max_benchmark_plots,
        global_benchmark_enabled: t.global_benchmark_enabled,
      };
      if (typeof t.forecast_enabled === "boolean") payload.forecast_enabled = t.forecast_enabled;

      const { error } = await supabase.from("subscription_tiers").update(payload).eq("tier_code", t.tier_code);
      if (error) throw error;
      await load();
    } catch (e: any) {
      setErr(e?.message ?? "Save failed");
    } finally {
      setBusy(false);
    }
  }, [supabase, load]);

  const hasForecast = tiers.some((t) => typeof t.forecast_enabled === "boolean");

  return (
    <div className="container py-4">
      <h1 className="h3 mb-2">Subscription Tiers</h1>
      <div className="text-secondary mb-3">Edit tier limits (platform admin).</div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        {tiers.map((t, idx) => (
          <div className="col-12 col-lg-4" key={t.tier_code}>
            <div className="card">
              <div className="card-body">
                <div className="fw-semibold mb-2">{String(t.tier_code ?? "").toUpperCase()}</div>

                <div className="mb-2">
                  <div className="small text-secondary">Name</div>
                  <input className="form-control form-control-sm" value={t.name ?? ""}
                    onChange={(e) => { const copy=[...tiers]; copy[idx]={...copy[idx], name:e.target.value}; setTiers(copy); }}
                  />
                </div>

                <div className="mb-2">
                  <div className="small text-secondary">Max branches</div>
                  <input className="form-control form-control-sm" type="number" value={t.max_branches ?? 1}
                    onChange={(e) => { const copy=[...tiers]; copy[idx]={...copy[idx], max_branches:Number(e.target.value)}; setTiers(copy); }}
                  />
                </div>

                <div className="mb-2">
                  <div className="small text-secondary">Benchmark plots (1-6)</div>
                  <input className="form-control form-control-sm" type="number" value={t.max_benchmark_plots ?? 4}
                    onChange={(e) => { const copy=[...tiers]; copy[idx]={...copy[idx], max_benchmark_plots:Number(e.target.value)}; setTiers(copy); }}
                  />
                </div>

                <div className="form-check mb-2">
                  <input className="form-check-input" type="checkbox" checked={Boolean(t.global_benchmark_enabled)}
                    onChange={(e) => { const copy=[...tiers]; copy[idx]={...copy[idx], global_benchmark_enabled:e.target.checked}; setTiers(copy); }}
                  />
                  <label className="form-check-label">Enable global benchmarks</label>
                </div>

                {hasForecast ? (
                  <div className="form-check mb-3">
                    <input className="form-check-input" type="checkbox" checked={Boolean(t.forecast_enabled)}
                      onChange={(e) => { const copy=[...tiers]; copy[idx]={...copy[idx], forecast_enabled:e.target.checked}; setTiers(copy); }}
                    />
                    <label className="form-check-label">Enable forecast</label>
                  </div>
                ) : null}

                <button className="btn btn-primary w-100" disabled={busy} onClick={() => save(t)}>
                  {busy ? "Saving..." : "Save"}
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}