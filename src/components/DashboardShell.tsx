"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { Sidebar } from "@/components/Sidebar";
import { ActivityTracker } from "@/components/ActivityTracker";

type OrgRow = { org_id: string; name: string; subscription_tier_code: string; support_email: string };
type BranchRow = { branch_id: string; code: string | null; name: string; is_default: boolean };

function emitScope() {
  window.dispatchEvent(new Event("coffeeops:scope"));
}

export function DashboardShell({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);

  const [loading, setLoading] = useState(true);
  const [isPlatformAdmin, setIsPlatformAdmin] = useState(false);

  const [orgs, setOrgs] = useState<OrgRow[]>([]);
  const [orgId, setOrgId] = useState<string>("");

  const [branches, setBranches] = useState<BranchRow[]>([]);
  const [branchId, setBranchId] = useState<string>(""); // "" => All

  const active =
    pathname.startsWith("/dashboard/import") ? "import" :
    pathname.startsWith("/dashboard/sales") ? "sales" :
    pathname.startsWith("/dashboard/expenses") ? "expenses" :
    pathname.startsWith("/dashboard/forecast") ? "forecast" :
    pathname.startsWith("/dashboard/unit-economics") ? "unitEconomics" :
    pathname.startsWith("/dashboard/benchmarks") ? "benchmarks" :
    pathname.startsWith("/dashboard/admin") ? "admin" :
    "dashboard";

  const refreshBranches = useCallback(async (nextOrg: string) => {
    const { data } = await supabase.rpc("list_branches_for_org", { p_org_id: nextOrg });
    setBranches((data ?? []) as any);
  }, [supabase]);

  const loadScope = useCallback(async () => {
    setLoading(true);

    const { data: userRes } = await supabase.auth.getUser();
    if (!userRes?.user) {
      router.replace("/auth/sign-in");
      return;
    }

    const { data: pa } = await supabase.rpc("is_platform_admin");
    setIsPlatformAdmin(Boolean(pa));

    const { data: orgRows } = await supabase.rpc("list_orgs_for_dropdown");
    const o = (orgRows ?? []) as OrgRow[];
    setOrgs(o);

    if (o.length === 0) {
      router.replace("/pending");
      return;
    }

    const savedOrg = localStorage.getItem("coffeeops.active_org_id");
    const nextOrg = (savedOrg && o.some(x => x.org_id === savedOrg)) ? savedOrg : o[0].org_id;

    setOrgId(nextOrg);
    localStorage.setItem("coffeeops.active_org_id", nextOrg);

    await refreshBranches(nextOrg);

    const savedBranch = localStorage.getItem(`coffeeops.active_branch_id.${nextOrg}`) ?? "";
    setBranchId(savedBranch);

    setLoading(false);
    emitScope();
  }, [router, supabase, refreshBranches]);

  useEffect(() => { loadScope(); }, [loadScope]);

  async function onChangeOrg(nextOrg: string) {
    setOrgId(nextOrg);
    localStorage.setItem("coffeeops.active_org_id", nextOrg);

    await refreshBranches(nextOrg);

    setBranchId("");
    localStorage.setItem(`coffeeops.active_branch_id.${nextOrg}`, "");
    emitScope();
  }

  function onChangeBranch(nextBranch: string) {
    setBranchId(nextBranch);
    localStorage.setItem(`coffeeops.active_branch_id.${orgId}`, nextBranch);
    emitScope();
  }

  return (
    <div className="d-flex app-shell">
      <Sidebar active={active as any} isPlatformAdmin={isPlatformAdmin} />

      <div className="flex-grow-1">
        <div className="topbar d-flex align-items-center justify-content-between px-3">
          <div className="d-flex align-items-center gap-2">
            <div className="fw-semibold">Scope</div>

            {loading ? (
              <div className="small text-secondary">Loadingâ€¦</div>
            ) : (
              <>
                <select className="form-select form-select-sm" style={{ width: 260 }} value={orgId} onChange={(e) => onChangeOrg(e.target.value)}>
                  {orgs.map((o) => (
                    <option key={o.org_id} value={o.org_id}>
                      {o.name} ({o.subscription_tier_code})
                    </option>
                  ))}
                </select>

                <select className="form-select form-select-sm" style={{ width: 220 }} value={branchId} onChange={(e) => onChangeBranch(e.target.value)} disabled={!orgId}>
                  <option value="">All branches</option>
                  {branches.map((b) => (
                    <option key={b.branch_id} value={b.branch_id}>
                      {b.name}
                    </option>
                  ))}
                </select>
              </>
            )}
          </div>

          <div className="small text-secondary">{isPlatformAdmin ? "Platform Admin" : "Member"}</div>
        </div>

        <ActivityTracker />
        <main>{children}</main>
      </div>
    </div>
  );
}
