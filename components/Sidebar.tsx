import Link from "next/link";

export function Sidebar({
  active,
  isPlatformAdmin,
}: {
  active?: "dashboard" | "import" | "sales" | "expenses" | "forecast" | "unitEconomics" | "benchmarks" | "admin";
  isPlatformAdmin?: boolean;
}) {
  return (
    <aside className="sidebar p-3 d-none d-lg-block">
      <div className="d-flex align-items-center gap-2 mb-4">
        <div className="brand-badge" />
        <div>
          <div className="fw-semibold">CoffeeOps BI</div>
          <div className="small text-secondary">Executive</div>
        </div>
      </div>

      <nav className="nav nav-pills flex-column gap-1">
        <Link className={`nav-link ${active === "dashboard" ? "active" : ""}`} href="/dashboard">Overview</Link>
        <Link className={`nav-link ${active === "import" ? "active" : ""}`} href="/dashboard/import">
          Import Center <span className="badge text-bg-secondary ms-2">v1</span>
        </Link>
        <Link className={`nav-link ${active === "sales" ? "active" : ""}`} href="/dashboard/sales">Sales</Link>
        <Link className={`nav-link ${active === "expenses" ? "active" : ""}`} href="/dashboard/expenses">Expenses</Link>
        <Link className={`nav-link ${active === "unitEconomics" ? "active" : ""}`} href="/dashboard/unit-economics">Unit Economics</Link>
        <Link className={`nav-link ${active === "forecast" ? "active" : ""}`} href="/dashboard/forecast">Forecast</Link>
        <Link className={`nav-link ${active === "benchmarks" ? "active" : ""}`} href="/dashboard/benchmarks">Benchmarks</Link>

        {isPlatformAdmin ? (
          <>
            <hr className="my-3" />
            <div className="small text-secondary px-2">Admin</div>
            <Link className={`nav-link ${active === "admin" ? "active" : ""}`} href="/dashboard/admin/approvals">Approvals</Link>
            <Link className={`nav-link ${active === "admin" ? "active" : ""}`} href="/dashboard/admin/tiers">Tiers</Link>
            <Link className={`nav-link ${active === "admin" ? "active" : ""}`} href="/dashboard/admin/orgs">Organizations</Link>
            <Link className={`nav-link ${active === "admin" ? "active" : ""}`} href="/dashboard/admin/users">Users</Link>
            <Link className={`nav-link ${active === "admin" ? "active" : ""}`} href="/dashboard/admin/role-mapping">Role mapping</Link>
            <Link className={`nav-link ${active === "admin" ? "active" : ""}`} href="/dashboard/admin/audit">Audit</Link>
          </>
        ) : null}
      </nav>

      <div className="mt-4 small text-secondary">
        Approval + tiers + privacy-safe global benchmarks.
      </div>
    </aside>
  );
}
