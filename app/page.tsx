import Link from 'next/link';

export default function HomePage() {
  return (
    <div className="landing">

    <div className="text-dark">

    <main className="container py-5">
      <div className="row align-items-center g-5">
        <div className="col-12 col-lg-6">
          <span className="badge rounded-pill text-bg-dark mb-3">
            Premium BI • Supabase Cloud • CSV-first
          </span>
          <h1 className="display-5 fw-semibold lh-sm">
            CoffeeOps Executive BI
            <span className="d-block text-muted fs-4 mt-3">
              Import CSV. Normalize operations. Ship dashboard-ready truth.
            </span>
          </h1>

          <p className="text-muted mt-4">
            This app is intentionally engineered for production-grade ingestion: idempotent import jobs,
            row-level validation, audit trails, and stable analytics contracts.
          </p>

          <div className="d-flex flex-wrap gap-2 mt-4">
            <Link className="btn btn-primary btn-lg" href="/auth/sign-in">
              Sign in
            </Link>
            <Link className="btn btn-outline-light btn-lg" href="/auth/sign-up">
              Create account
            </Link>
            <Link className="btn btn-link text-decoration-none" href="/setup">
              Environment setup
            </Link>
          </div>

          <div className="mt-5 d-flex gap-4 small-muted">
            <div>
              <div className="fw-semibold">Import Center</div>
              <div className="text-muted">Job statuses + mapping + errors</div>
            </div>
            <div>
              <div className="fw-semibold">Dashboards</div>
              <div className="text-muted">KPIs, trends, drilldowns</div>
            </div>
            <div>
              <div className="fw-semibold">RLS</div>
              <div className="text-muted">Org isolation by default</div>
            </div>
          </div>
        </div>

        <div className="col-12 col-lg-6">
          <div className="card panel-light p-4">
            <div className="d-flex justify-content-between align-items-center">
              <div>
                <div className="small-muted">Executive overview (preview)</div>
                <div className="h5 mb-0">Last 30 Days</div>
              </div>
              <span className="badge rounded-pill">demo</span>
            </div>
            <hr />

            <div className="row g-3">
              <div className="col-12 col-md-6">
                <div className="card panel-light kpi-card p-3">
                  <div className="small-muted">Net sales</div>
                  <div className="h3 mb-0">$ —</div>
                  <div className="small-muted mt-2">Import sales to activate</div>
                </div>
              </div>
              <div className="col-12 col-md-6">
                <div className="card panel-light kpi-card p-3">
                  <div className="small-muted">Gross profit</div>
                  <div className="h3 mb-0">$ —</div>
                  <div className="small-muted mt-2">COGS engine in Iteration 4+</div>
                </div>
              </div>
              <div className="col-12">
                <div className="card panel-light p-3">
                  <div className="d-flex justify-content-between align-items-center">
                    <div>
                      <div className="small-muted">Hero trend chart</div>
                      <div className="fw-semibold">Monthly net sales + gross profit</div>
                    </div>
                    <span className="badge rounded-pill text-bg-dark">coming</span>
                  </div>
                  <div className="mt-3 hero-box">
                    <div className="h-100 d-flex align-items-center justify-content-center text-muted">
                      Chart placeholder
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div className="mt-3 small-muted">
              After you set Supabase env vars, sign in and create your org. Defaults (branch + cost centers) auto-bootstrap.
            </div>
          </div>
        </div>
      </div>
    </main>
    </div>
    </div>
  );
}
