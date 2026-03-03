"use client";
import { useEffect, useRef, useState } from "react";
import { ScatterChart, Scatter, CartesianGrid, XAxis, YAxis, Tooltip } from "recharts";

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

export function PriceVsCogsScatter({ data }: { data: any[] }) {
  const { ref, w } = useBoxWidth();
  return (
    <div ref={ref} style={{ minWidth: 0 }}>
      {w <= 0 ? <div style={{ height: 320 }} /> : (
        <ScatterChart width={w} height={320} margin={{ top: 10, right: 10, left: 10, bottom: 10 }}>
          <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
          <XAxis dataKey="avg_price" name="Avg Price" />
          <YAxis dataKey="cogs_per_unit" name="COGS/Unit" />
          <Tooltip />
          <Scatter name="SKUs" data={data} fill="#3B5BFF" />
        </ScatterChart>
      )}
    </div>
  );
}