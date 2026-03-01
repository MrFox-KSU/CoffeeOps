"use client";

import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, Tooltip, CartesianGrid, Legend } from "recharts";
import { useEffect, useState } from "react";

export function MonthlySalesProfitChart({ data }: { data: any[] }) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  if (!mounted) return <div className="chart-320" />;
  return (
    <div className="chart-320">
      <ResponsiveContainer>
        <AreaChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" opacity={0.15} />
          <XAxis dataKey="month" tick={{ fill: "#b7bcc5", fontSize: 12 }} />
          <YAxis tick={{ fill: "#b7bcc5", fontSize: 12 }} />
          <Tooltip contentStyle={{ background: "#0f1115", border: "1px solid #2a2f38", color: "#fff" }} />
          <Legend />
          <Area type="monotone" dataKey="net_sales" name="Net Sales" stroke="#4cc9f0" fill="#4cc9f0" fillOpacity={0.15} />
          <Area type="monotone" dataKey="gross_profit" name="Gross Profit" stroke="#80ffdb" fill="#80ffdb" fillOpacity={0.12} />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
