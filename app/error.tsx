"use client";

import { useEffect } from "react";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("App Route Error:", error);
  }, [error]);

  return (
    <div className="container py-5">
      <div className="card panel-light bg-dark text-light border-secondary">
        <div className="card-body">
          <h1 className="h4 mb-2">Something went wrong</h1>
          <p className="text-secondary mb-3">
            An unexpected error occurred while rendering this route.
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
  );
}
