"use client";
import { useEffect, useRef, useState } from "react";
import { LineChart, Line, CartesianGrid, XAxis, YAxis, Tooltip, Legend } from "recharts";

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

export function OperatingTrendChart({ data }: { data: any[] }) {
  const { ref, w } = useBoxWidth();
  return (
    <div ref={ref} style={{ minWidth: 0 }}>
      {w <= 0 ? <div style={{ height: 320 }} /> : (
        <LineChart width={w} height={320} data={data} margin={{ top: 10, right: 10, left: 10, bottom: 10 }}>
          <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
          <XAxis dataKey="day" />
          <YAxis />
          <Tooltip />
          <Legend />
          <Line type="monotone" dataKey="net_sales" name="Net Sales" stroke="#3B5BFF" dot={false} />
          <Line type="monotone" dataKey="cogs_total" name="COGS (incl OH)" stroke="#EF4444" dot={false} />
          <Line type="monotone" dataKey="expenses_total" name="Expenses" stroke="#F59E0B" dot={false} />
          <Line type="monotone" dataKey="labor_total" name="Labor" stroke="#10B981" dot={false} />
          <Line type="monotone" dataKey="net_profit" name="Net Profit" stroke="#111827" dot={false} />
        </LineChart>
      )}
    </div>
  );
}