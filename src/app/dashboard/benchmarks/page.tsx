"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { ScatterChart, Scatter, XAxis, YAxis, CartesianGrid, Tooltip, Legend } from "recharts";

type Row = {
  plot_id: string;
  plot_title: string;
  x_label: string;
  y_label: string;
  series: "self" | "others";
  branch_id: string | null;
  label: string;
  x: number;
  y: number;
  n: number | null;
};

function PlotCard({ meta, self, others }: { meta: Row; self: Row[]; others: Row[] }) {
  const ref = useRef<HTMLDivElement | null>(null);
  const [w, setW] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const update = () => setW(el.clientWidth || 0);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div className="card">
      <div className="card-body">
        <div className="fw-semibold">{meta.plot_title}</div>
        <div className="small text-secondary mb-2">{meta.x_label} vs {meta.y_label}</div>

        <div ref={ref} className="chart-320" style={{ minWidth: 0 }}>
          {w <= 0 ? (
            <div className="chart-320" />
          ) : (
            <ScatterChart width={w} height={320} margin={{ top: 10, right: 10, left: 10, bottom: 10 }}>
              <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
              <XAxis dataKey="x" name={meta.x_label} />
              <YAxis dataKey="y" name={meta.y_label} />
              <Tooltip
                content={({ active, payload }) => {
                  if (!active || !payload || payload.length === 0) return null;
                  const r: any = payload[0].payload;
                  const title = r.series === "others" ? `Others${r.n ? ` (n=${r.n})` : ""}` : r.label;
                  return (
                    <div className="card panel-light p-2 no-shadow" style={{ borderRadius: 12 }}>
                      <div className="fw-semibold">{title}</div>
                      <div className="small text-secondary">{meta.x_label}: {Number(r.x).toFixed(2)}</div>
                      <div className="small text-secondary">{meta.y_label}: {Number(r.y).toFixed(4)}</div>
                    </div>
                  );
                }}
              />
              <Legend />
              <Scatter name="Others" data={others} fill="#94A3B8" />
              <Scatter name="Your branches" data={self} fill="#3B5BFF" />
            </ScatterChart>
          )}
        </div>
      </div>
    </div>
  );
}

export default function BenchmarksPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState("");
  const [days, setDays] = useState(30);
  const [rows, setRows] = useState<Row[]>([]);
  const [err, setErr] = useState<string | null>(null);

  function readOrg() {
    setOrgId(localStorage.getItem("coffeeops.active_org_id") ?? "");
  }

  useEffect(() => {
    readOrg();
    const fn = () => readOrg();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setErr(null);
      if (!orgId) return;

      const { data, error } = await supabase.rpc("get_benchmark_points", { p_org_id: orgId, p_days: days });
      if (cancelled) return;
      if (error) setErr(error.message);
      else setRows((data ?? []) as any);
    })();

    return () => { cancelled = true; };
  }, [supabase, orgId, days]);

  const plots = useMemo(() => {
    const m = new Map<string, Row[]>();
    for (const r of rows) {
      if (!m.has(r.plot_id)) m.set(r.plot_id, []);
      m.get(r.plot_id)!.push(r);
    }
    return Array.from(m.values()).map((d) => ({
      meta: d[0],
      self: d.filter((x) => x.series === "self"),
      others: d.filter((x) => x.series === "others"),
    }));
  }, [rows]);

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Benchmarks</h1>
          <div className="small text-secondary">Global peers are anonymized + bucketed (privacy-safe).</div>
        </div>

        <select className="form-select form-select-sm maxw-360" value={days} onChange={(e) => setDays(Number(e.target.value))}>
          <option value={7}>Last 7d</option>
          <option value={30}>Last 30d</option>
          <option value={90}>Last 90d</option>
        </select>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        {plots.map((p) => (
          <div className="col-12 col-lg-6" key={p.meta.plot_id}>
            <PlotCard meta={p.meta} self={p.self} others={p.others} />
          </div>
        ))}
        {plots.length === 0 && !err ? (
          <div className="col-12"><div className="card"><div className="card-body text-secondary">No benchmark data yet.</div></div></div>
        ) : null}
      </div>
    </div>
  );
}