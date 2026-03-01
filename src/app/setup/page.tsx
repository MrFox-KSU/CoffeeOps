export default function SetupPage() {
  const hasUrl = !!process.env.NEXT_PUBLIC_SUPABASE_URL;
  const hasAnon = !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  return (
    <div className="container py-5">
      <div className="card panel-light bg-dark text-light border-secondary">
        <div className="card-body">
          <h1 className="h3 mb-3">Setup required</h1>
          <p className="text-secondary">
            The app is running, but required Supabase environment variables are missing.
          </p>

          <ul className="mb-4">
            <li>
              NEXT_PUBLIC_SUPABASE_URL:{" "}
              <span className={hasUrl ? "text-success" : "text-danger"}>
                {hasUrl ? "present" : "missing"}
              </span>
            </li>
            <li>
              NEXT_PUBLIC_SUPABASE_ANON_KEY:{" "}
              <span className={hasAnon ? "text-success" : "text-danger"}>
                {hasAnon ? "present" : "missing"}
              </span>
            </li>
          </ul>

          <p className="text-secondary mb-2">Fix by creating/editing <code>.env.local</code> in the repo root:</p>
          <pre className="bg-black p-3 rounded border border-secondary text-light">
{`NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=...`}
          </pre>

          <p className="text-secondary mb-0">
            After updating env vars, restart: <code>npm run dev</code>
          </p>
        </div>
      </div>
    </div>
  );
}
