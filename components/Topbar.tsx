'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getSupabaseBrowserClient } from '@/lib/supabase/client';

export function Topbar() {
  const router = useRouter();
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    if (!supabase) return;

    supabase.auth.getUser().then(({ data }) => {
      setEmail(data.user?.email ?? null);
    });
  }, []);

  async function signOut() {
    const supabase = getSupabaseBrowserClient();
    if (!supabase) {
      router.push('/setup');
      return;
    }

    await supabase.auth.signOut();
    router.push('/');
  }

  return (
    <div className="topbar px-3 py-2 d-flex justify-content-between align-items-center">
      <div className="d-flex align-items-center gap-2">
        <Link className="btn btn-sm btn-outline-light d-lg-none" href="/dashboard">
          Menu
        </Link>
        <div>
          <div className="fw-semibold">Executive BI</div>
          <div className="small-muted">Cloud-first Supabase</div>
        </div>
      </div>

      <div className="d-flex align-items-center gap-2">
        {email ? <span className="small-muted">{email}</span> : <span className="small-muted">Not signed in</span>}
        <button className="btn btn-sm btn-outline-light" onClick={signOut}>
          Sign out
        </button>
      </div>
    </div>
  );
}
