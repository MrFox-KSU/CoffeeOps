import Link from 'next/link';

export function SetupRequired() {
  return (
    <div className="container py-5">
      <div className="row justify-content-center">
        <div className="col-12 col-lg-8">
          <div className="card panel-light p-4">
            <h1 className="h3 mb-2">Supabase environment not configured</h1>
            <p className="text-muted">
              This app is intentionally designed to <strong>not crash</strong> when environment variables are missing.
              Configure the variables below and restart the dev server.
            </p>

            <div className="mt-3">
              <div className="fw-semibold">Required variables</div>
              <ul className="mt-2">
                <li>
                  <span className="code-inline">NEXT_PUBLIC_SUPABASE_URL</span>
                </li>
                <li>
                  <span className="code-inline">NEXT_PUBLIC_SUPABASE_ANON_KEY</span>
                </li>
              </ul>
              <div className="small-muted">
                Optional (server-only, future iterations): <span className="code-inline">SUPABASE_SERVICE_ROLE_KEY</span>
              </div>
            </div>

            <hr />

            <div className="d-flex flex-wrap gap-2">
              <Link className="btn btn-primary" href="/">
                Back to home
              </Link>
              <a className="btn btn-outline-light" href="https://supabase.com/dashboard" target="_blank" rel="noreferrer">
                Open Supabase Dashboard
              </a>
            </div>

            <div className="mt-4 small-muted">
              Tip: copy <span className="code-inline">.env.example</span> to <span className="code-inline">.env.local</span>.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
