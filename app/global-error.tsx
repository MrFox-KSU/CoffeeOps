"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html>
      <body>
        <div className="container py-5">
          <div className="card panel-light bg-dark text-light border-secondary">
            <div className="card-body">
              <h1 className="h4 mb-2">Global Error</h1>
              <p className="text-secondary mb-3">
                A fatal error occurred at the app root.
              </p>
              <pre className="bg-black p-3 rounded border border-secondary text-light small">
{String(error?.message ?? error)}
              </pre>
              <button className="btn btn-primary mt-3" onClick={() => reset()}>
                Try again
              </button>
            </div>
          </div>
        </div>
      </body>
    </html>
  );
}
