'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { SetupRequired } from '@/components/SetupRequired';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';

export default function SignUpPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  if (!supabase) return <SetupRequired />;

  async function submit() {
    setError(null);
    setNotice(null);

    const e = email.trim();
    if (!e.includes('@')) {
      setError('Please enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters.');
      return;
    }

    setBusy(true);
    try {
      const { data, error: signUpError } = await supabase!.auth.signUp({
        email: e,
        password,
        options: {
          data: {
            full_name: fullName.trim() || null
          }
        }
      });

      if (signUpError) {
        setError(signUpError.message);
        return;
      }

      // If email confirmations are enabled, session may be null.
      if (!data.session) {
        setNotice('Account created. Check your email to confirm, then sign in.');
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
            <div className="small-muted">Welcome</div>
            <h1 className="h3 mb-1">Create your account</h1>
            <p className="text-muted">Email + password via Supabase Auth.</p>

            <div className="mt-3">
              <label className="form-label">Full name (optional)</label>
              <input
                className="form-control"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="e.g., Aisha Al-Saud"
              />
            </div>

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
                placeholder="Minimum 8 characters"
              />
            </div>

            {error ? (
              <div className="alert alert-danger mt-3 mb-0" role="alert">
                {error}
              </div>
            ) : null}

            {notice ? (
              <div className="alert alert-success mt-3 mb-0" role="alert">
                {notice}
              </div>
            ) : null}

            <div className="d-flex gap-2 mt-4">
              <button className="btn btn-primary" onClick={submit} disabled={busy}>
                {busy ? 'Creating…' : 'Create account'}
              </button>
              <Link className="btn btn-outline-light" href="/auth/sign-in">
                Sign in
              </Link>
            </div>

            <hr className="my-4" />

            <div className="small-muted">
              After you sign in, create an org. Org defaults are applied in Postgres via migration triggers.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
