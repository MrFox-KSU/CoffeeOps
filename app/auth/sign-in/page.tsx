'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { SetupRequired } from '@/components/SetupRequired';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';

export default function SignInPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!supabase) return <SetupRequired />;

  async function submit() {
    setError(null);

    const e = email.trim();
    if (!e.includes('@')) {
      setError('Please enter a valid email address.');
      return;
    }

    setBusy(true);
    try {
      const { error: signInError } = await supabase!.auth.signInWithPassword({
        email: e,
        password
      });

      if (signInError) {
        setError(signInError.message);
        return;
      }

      router.replace('/dashboard');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-5">
      <div className="row justify-content-center">
        <div className="col-12 col-lg-5">
          <div className="card panel-light p-4">
            <div className="small-muted">Welcome back</div>
            <h1 className="h3 mb-1">Sign in</h1>
            <p className="text-muted">Secure auth powered by Supabase.</p>

            <div className="mt-3">
              <label className="form-label">Email</label>
              <input
                className="form-control"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@company.com"
                inputMode="email"
              />
            </div>

            <div className="mt-3">
              <label className="form-label">Password</label>
              <input
                className="form-control"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                type="password"
                placeholder="Your password"
              />
            </div>

            {error ? (
              <div className="alert alert-danger mt-3 mb-0" role="alert">
                {error}
              </div>
            ) : null}

            <div className="d-flex gap-2 mt-4">
              <button className="btn btn-primary" onClick={submit} disabled={busy}>
                {busy ? 'Signing in…' : 'Sign in'}
              </button>
              <Link className="btn btn-outline-light" href="/auth/sign-up">
                Create account
              </Link>
            </div>

            <hr className="my-4" />

            <div className="small-muted">
              If you just created an account and email confirmations are enabled, confirm your email first.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
