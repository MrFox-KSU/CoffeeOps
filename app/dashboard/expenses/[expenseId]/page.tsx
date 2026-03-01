"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

type AllocationRow = { cost_center_code: string; amount: string };

export default function ExpenseAllocationPage({ params }: { params: { expenseId: string } }) {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const [expense, setExpense] = useState<any>(null);
  const [codes, setCodes] = useState<string[]>([]);
  const [rows, setRows] = useState<AllocationRow[]>([]);
  const [status, setStatus] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setErr(null);

      const { data: exp, error: e1 } = await (supabase as any)
        .from("expenses")
        .select("id,org_id,expense_date,reference_number,vendor,category,amount,cost_center_code")
        .eq("id", params.expenseId)
        .single();

      if (cancelled) return;
      if (e1) return setErr(e1.message);

      setExpense(exp);

      // codes
      const { data: c, error: e2 } = await supabase.rpc("list_cost_center_codes", { p_org_id: exp.org_id });
      if (!cancelled && !e2) setCodes((c ?? []).map((x: any) => x.cost_center_code));

      // existing allocations
      const { data: a, error: e3 } = await supabase.rpc("get_expense_allocations", { p_expense_id: exp.id });
      if (!cancelled && e3) setErr(e3.message);
      if (!cancelled && !e3) {
        const existing = (a ?? []).map((x: any) => ({ cost_center_code: x.cost_center_code, amount: String(x.amount) }));
        setRows(existing.length ? existing : [{ cost_center_code: "UNALLOCATED", amount: String(exp.amount) }]);
      }

      // preview
      const { data: p, error: e4 } = await supabase.rpc("preview_expense_allocation", { p_expense_id: exp.id });
      if (!cancelled && !e4) setStatus(p);
    })();

    return () => {
      cancelled = true;
    };
  }, [supabase, params.expenseId]);

  function addRow() {
    setRows((r) => [...r, { cost_center_code: codes[0] ?? "UNALLOCATED", amount: "0" }]);
  }

  function removeRow(i: number) {
    setRows((r) => r.filter((_, idx) => idx !== i));
  }

  async function save() {
    if (!expense) return;
    setBusy(true);
    setErr(null);
    try {
      const payload = rows.map((r) => ({
        cost_center_code: r.cost_center_code,
        amount: Number(r.amount),
      }));

      const { data, error } = await supabase.rpc("allocate_expense_to_cost_centers", {
        p_expense_id: expense.id,
        p_allocations: payload,
      });

      if (error) throw error;

      const { data: p2 } = await supabase.rpc("preview_expense_allocation", { p_expense_id: expense.id });
      setStatus(p2 ?? null);
    } catch (e: any) {
      setErr(e?.message ?? "Save failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container py-4">
      <div className="d-flex align-items-center justify-content-between mb-3">
        <div>
          <h1 className="h4 m-0">Allocate Expense</h1>
          <div className="text-secondary small">{params.expenseId}</div>
        </div>
        <Link className="btn btn-outline-light" href="/dashboard/expenses">
          Back
        </Link>
      </div>

      {err && <div className="alert alert-danger">{err}</div>}

      {expense && (
        <div className="card panel-light bg-dark border-secondary mb-3">
          <div className="card-body">
            <div className="d-flex flex-wrap gap-3">
              <div><div className="small text-secondary">Date</div><div className="fw-semibold">{expense.expense_date}</div></div>
              <div><div className="small text-secondary">Vendor</div><div className="fw-semibold">{expense.vendor ?? "-"}</div></div>
              <div><div className="small text-secondary">Category</div><div className="fw-semibold">{expense.category}</div></div>
              <div><div className="small text-secondary">Amount</div><div className="fw-semibold">{Number(expense.amount).toFixed(2)}</div></div>
            </div>
            {status && (
              <div className="mt-3 small text-secondary">
                Status: <span className="text-dark">{status.status}</span> • Allocated: {Number(status.allocated_amount).toFixed(2)} • Unallocated: {Number(status.unallocated_amount).toFixed(2)}
              </div>
            )}
          </div>
        </div>
      )}

      <div className="card panel-light bg-dark border-secondary">
        <div className="card-body">
          <div className="d-flex justify-content-between align-items-center mb-2">
            <div className="fw-semibold">Allocations</div>
            <button className="btn btn-outline-light btn-sm" onClick={addRow}>Add</button>
          </div>

          <div className="table-responsive">
            <table className="table table-dark table-sm align-middle mb-0">
              <thead>
                <tr>
                  <th>Cost Center</th>
                  <th className="text-end">Amount</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i}>
                    <td className="minw-220">
                      <select
                        className="form-select form-select-sm"
                        value={r.cost_center_code}
                        onChange={(e) => {
                          const v = e.target.value;
                          setRows((prev) => prev.map((x, idx) => (idx === i ? { ...x, cost_center_code: v } : x)));
                        }}
                      >
                        {codes.map((c) => (
                          <option key={c} value={c}>{c}</option>
                        ))}
                        {!codes.includes(r.cost_center_code) && <option value={r.cost_center_code}>{r.cost_center_code}</option>}
                      </select>
                    </td>
                    <td className="text-end w-160">
                      <input
                        className="form-control form-control-sm text-end"
                        value={r.amount}
                        onChange={(e) => {
                          const v = e.target.value;
                          setRows((prev) => prev.map((x, idx) => (idx === i ? { ...x, amount: v } : x)));
                        }}
                      />
                    </td>
                    <td className="text-end w-90">
                      <button className="btn btn-outline-danger btn-sm" onClick={() => removeRow(i)}>Remove</button>
                    </td>
                  </tr>
                ))}
                {rows.length === 0 && (
                  <tr><td colSpan={3} className="text-secondary">No allocations yet.</td></tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="d-flex justify-content-end mt-3">
            <button className="btn btn-success" onClick={save} disabled={busy}>
              {busy ? "Saving…" : "Save allocations"}
            </button>
          </div>

          <div className="small text-secondary mt-2">
            Rule: allocation amounts must sum exactly to the expense amount.
          </div>
        </div>
      </div>
    </div>
  );
}
