'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { SetupRequired } from '@/components/SetupRequired';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';

export default function CreateOrgPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!supabase) return <SetupRequired />;

  async function submit() {
    setError(null);

    const trimmed = name.trim();
    if (trimmed.length < 2) {
      setError('Org name must be at least 2 characters.');
      return;
    }

    setBusy(true);
    try {
      const { data: userRes } = await supabase!.auth.getUser();
      if (!userRes.user) {
        router.replace('/auth/sign-in');
        return;
      }

      const { data, error: rpcError } = await supabase!.rpc('create_org', { p_name: trimmed });
      if (rpcError) {
        setError(rpcError.message);
        return;
      }

      // data is org_id (uuid)
      router.push('/dashboard');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-5">
      <div className="row justify-content-center">
        <div className="col-12 col-lg-6">
          <div className="card panel-light p-4">
            <div className="small-muted">Org setup</div>
            <h1 className="h3 mb-1">Create your organization</h1>
            <p className="text-muted">
              When you create an org, the database will automatically bootstrap:
              <strong> default branch</strong> and <strong>system cost centers</strong>. You become <span className="code-inline">super_admin</span>.
            </p>

            <div className="mt-3">
              <label className="form-label">Organization name</label>
              <input
                className="form-control form-control-lg"
                placeholder="e.g., Acme Coffee Roasters"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>

            {error ? (
              <div className="alert alert-danger mt-3 mb-0" role="alert">
                {error}
              </div>
            ) : null}

            <div className="d-flex gap-2 mt-4">
              <button className="btn btn-primary btn-lg" onClick={submit} disabled={busy}>
                {busy ? 'Creating…' : 'Create org'}
              </button>
              <Link className="btn btn-outline-light btn-lg" href="/dashboard">
                Back
              </Link>
            </div>

            <hr className="my-4" />

            <div className="small-muted">
              This action calls the Supabase RPC <span className="code-inline">create_org(p_name)</span>.
              If you haven’t applied the migration yet, you’ll see an RPC error.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
