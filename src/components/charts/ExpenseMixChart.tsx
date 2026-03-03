"use client";
import { useEffect, useRef, useState } from "react";
import { BarChart, Bar, CartesianGrid, XAxis, YAxis, Tooltip } from "recharts";

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

export function ExpenseMixChart({ data }: { data: any[] }) {
  const { ref, w } = useBoxWidth();
  return (
    <div ref={ref} style={{ minWidth: 0 }}>
      {w <= 0 ? <div style={{ height: 260 }} /> : (
        <BarChart width={w} height={260} data={data} margin={{ top: 10, right: 10, left: 10, bottom: 10 }}>
          <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
          <XAxis dataKey="category" />
          <YAxis />
          <Tooltip />
          <Bar dataKey="amount" name="Amount" fill="#F59E0B" />
        </BarChart>
      )}
    </div>
  );
}