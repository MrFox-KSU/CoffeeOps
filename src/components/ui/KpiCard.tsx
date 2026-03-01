"use client";

type Props = {
  label: string;
  value: string;
  sublabel?: string;
  tone?: "default" | "good" | "bad" | "warn";
};

export function KpiCard({ label, value, sublabel, tone = "default" }: Props) {
  const badge =
    tone === "good"
      ? "text-bg-success"
      : tone === "bad"
      ? "text-bg-danger"
      : tone === "warn"
      ? "text-bg-warning"
      : "text-bg-secondary";

  return (
    <div className="card kpi-card">
      <div className="card-body">
        <div className="d-flex align-items-start justify-content-between gap-2">
          <div>
            <div className="kpi-label">{label}</div>
            <div className="kpi-value">{value}</div>
          </div>
          {sublabel && <span className={`badge ${badge}`}>{sublabel}</span>}
        </div>
      </div>
    </div>
  );
}
