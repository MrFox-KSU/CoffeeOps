"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type DailyRow = {
  day: string;
  amount: number;
  tax_amount: number;
  total_amount: number;
  expense_rows: number;
};

type AllocRow = {
  expense_id: string;
  expense_date: string;
  vendor: string | null;
  category: string;
  amount: number;
  allocated_amount: number;
  unallocated_amount: number;
  allocation_status: "unallocated" | "partial" | "allocated";
};

export default function ExpensesPage() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [orgId, setOrgId] = useState("");
  const [branchId, setBranchId] = useState(""); // "" => all branches

  const [daily, setDaily] = useState<DailyRow[]>([]);
  const [alloc, setAlloc] = useState<AllocRow[]>([]);
  const [err, setErr] = useState<string | null>(null);

  function readScope() {
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
    setOrgId(o);
    setBranchId(localStorage.getItem(`coffeeops.active_branch_id.${o}`) ?? "");
  }

  useEffect(() => {
    readScope();
    const fn = () => readScope();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setErr(null);
      if (!orgId) return;

      const b = branchId ? branchId : null;

      const [{ data: d1, error: e1 }, { data: d2, error: e2 }] = await Promise.all([
        supabase.rpc("get_expenses_daily", { p_org_id: orgId, p_limit: 60, p_branch_id: b }),
        supabase.rpc("list_expenses_for_allocation", { p_org_id: orgId, p_limit: 200, p_branch_id: b }),
      ]);

      if (cancelled) return;
      if (e1) return setErr(e1.message);
      if (e2) return setErr(e2.message);

      setDaily((d1 ?? []) as any);
      setAlloc((d2 ?? []) as any);
    })();

    return () => {
      cancelled = true;
    };
  }, [supabase, orgId, branchId]);

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between flex-wrap gap-2 mb-3">
        <div>
          <h1 className="h3 m-0">Expenses</h1>
          <div className="small text-secondary">Daily trend + allocation status (scoped by branch)</div>
        </div>
      </div>

      {err && <div className="alert alert-danger ws-prewrap">{err}</div>}

      <div className="row g-3">
        <div className="col-12 col-lg-6">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Daily</div>
              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Day</th>
                      <th className="text-end">Amount</th>
                      <th className="text-end">Rows</th>
                    </tr>
                  </thead>
                  <tbody>
                    {daily.map((r) => (
                      <tr key={r.day}>
                        <td>{r.day}</td>
                        <td className="text-end">{Number(r.total_amount ?? r.amount).toFixed(2)}</td>
                        <td className="text-end">{r.expense_rows}</td>
                      </tr>
                    ))}
                    {daily.length === 0 && (
                      <tr>
                        <td colSpan={3} className="text-secondary">
                          No expenses yet.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
              <div className="small text-secondary mt-2">Source: public.get_expenses_daily()</div>
            </div>
          </div>
        </div>

        <div className="col-12 col-lg-6">
          <div className="card">
            <div className="card-body">
              <div className="fw-semibold mb-2">Allocation queue</div>
              <div className="table-responsive">
                <table className="table table-light table-sm align-middle mb-0">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th>Vendor</th>
                      <th>Category</th>
                      <th className="text-end">Amount</th>
                      <th className="text-end">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {alloc.map((r) => (
                      <tr key={r.expense_id}>
                        <td>{r.expense_date}</td>
                        <td className="text-secondary">{r.vendor ?? "-"}</td>
                        <td>{r.category}</td>
                        <td className="text-end">{Number(r.amount).toFixed(2)}</td>
                        <td className="text-end">
                          <Link className="btn btn-outline-secondary btn-sm" href={`/dashboard/expenses/${r.expense_id}`}>
                            {r.allocation_status}
                          </Link>
                        </td>
                      </tr>
                    ))}
                    {alloc.length === 0 && (
                      <tr>
                        <td colSpan={5} className="text-secondary">
                          No expenses yet.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
              <div className="small text-secondary mt-2">Source: public.list_expenses_for_allocation()</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}