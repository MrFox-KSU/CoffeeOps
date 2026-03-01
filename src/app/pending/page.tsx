"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export default function PendingPage() {
  const router = useRouter();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [email, setEmail] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data: userRes } = await supabase.auth.getUser();
      if (!userRes?.user) {
        router.replace("/auth/sign-in");
        return;
      }
      const { data, error } = await supabase.rpc("get_platform_support_email");
      if (cancelled) return;
      if (error) setErr(error.message);
      else setEmail(String(data ?? ""));
    })();
    return () => { cancelled = true; };
  }, [supabase, router]);

  return (
    <div className="container py-5">
      <div className="card">
        <div className="card-body">
          <h1 className="h4 mb-2">Approval Required</h1>
          <div className="text-secondary mb-3">
            Your account is pending approval by the platform super admin.
          </div>

          {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

          <div className="mb-2">Please contact admin:</div>
          <div className="fw-semibold mb-4">{email ? email : "Loading…"}</div>

          <div className="d-flex gap-2 flex-wrap">
            <Link className="btn btn-primary" href="/request-access">
              Request access to an organization
            </Link>
            <Link className="btn btn-outline-secondary" href="/onboarding/org">
              Create a new organization
            </Link>
          </div>

          <div className="small text-secondary mt-3">
            If the org is not listed, ask the admin to share the org ID.
          </div>
        </div>
      </div>
    </div>
  );
}