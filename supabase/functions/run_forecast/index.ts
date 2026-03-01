import { corsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function jsonResp(obj: any, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY") ?? "";

    const GH_TOKEN = Deno.env.get("GITHUB_TOKEN") ?? "";
    const GH_OWNER = Deno.env.get("GITHUB_OWNER") ?? "";
    const GH_REPO = Deno.env.get("GITHUB_REPO") ?? "";
    const GH_WORKFLOW = Deno.env.get("GITHUB_WORKFLOW") ?? "forecast_free.yml";
    const GH_REF = Deno.env.get("GITHUB_REF") ?? "main";

    const PAID_URL = Deno.env.get("PAID_FORECAST_URL") ?? "";
    const PAID_KEY = Deno.env.get("PAID_FORECAST_API_KEY") ?? "";

    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return jsonResp({ error: "Missing SUPABASE_URL / SUPABASE_ANON_KEY" }, 500);

    const authHeader = req.headers.get("authorization") ?? "";
    const xUserJwt = req.headers.get("x-user-jwt") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader : (xUserJwt ? `Bearer ${xUserJwt}` : "");
    if (!token) return jsonResp({ error: "Missing user JWT (Authorization or x-user-jwt)" }, 401);

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: token } },
      auth: { persistSession: false },
    });

    const body = await req.json().catch(() => ({}));
    const org_id = body.org_id ?? body.p_org_id;
    const branch_id = body.branch_id ?? body.p_branch_id ?? null;
    const horizon_days = Number(body.horizon_days ?? body.p_horizon_days ?? 30);
    const history_days = Number(body.history_days ?? body.p_history_days ?? 365);
    const requested_engine = String(body.engine ?? "github_free");

    if (!org_id) return jsonResp({ error: "Missing org_id" }, 400);

    const { data: run, error: runErr } = await userClient.rpc("create_forecast_run", {
      p_org_id: org_id,
      p_branch_id: branch_id,
      p_horizon_days: horizon_days,
      p_history_days: history_days,
      p_engine: requested_engine,
    });

    if (runErr) return jsonResp({ error: runErr.message }, 400);

    const run_id = run.id;
    const engine = run.engine;

    const admin = SERVICE_ROLE_KEY
      ? createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } })
      : null;

    if (engine === "paid_premium") {
      if (!PAID_URL) {
        if (admin) await admin.from("forecast_runs").update({ status: "failed", message: "Paid engine not configured (PAID_FORECAST_URL missing)" }).eq("id", run_id);
        return jsonResp({ ok: false, run_id, status: "failed", message: "Paid engine not configured" }, 400);
      }

      const res = await fetch(PAID_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...(PAID_KEY ? { "Authorization": `Bearer ${PAID_KEY}` } : {}) },
        body: JSON.stringify({ run_id }),
      });

      if (!res.ok) {
        const t = await res.text();
        if (admin) await admin.from("forecast_runs").update({ status: "failed", message: `Paid dispatch failed: ${t}` }).eq("id", run_id);
        return jsonResp({ ok: false, run_id, status: "failed", message: "Paid dispatch failed", details: t }, 400);
      }

      return jsonResp({ ok: true, run_id, status: "queued", engine });
    }

    if (!GH_TOKEN || !GH_OWNER || !GH_REPO) {
      if (admin) await admin.from("forecast_runs").update({ status: "failed", message: "GitHub not configured (missing Edge secrets)" }).eq("id", run_id);
      return jsonResp({ ok: false, run_id, status: "failed", message: "GitHub not configured (set Edge secrets)" }, 400);
    }

    const url = `https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/workflows/${GH_WORKFLOW}/dispatches`;
    const gh = await fetch(url, {
      method: "POST",
      headers: {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Authorization": `Bearer ${GH_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ref: GH_REF, inputs: { run_id: String(run_id) } }),
    });

    if (!gh.ok) {
      const t = await gh.text();
      if (admin) await admin.from("forecast_runs").update({ status: "failed", message: `GitHub dispatch failed: ${t}` }).eq("id", run_id);
      return jsonResp({ ok: false, run_id, status: "failed", message: "GitHub dispatch failed", details: t }, 400);
    }

    return jsonResp({ ok: true, run_id, status: "queued", engine });
  } catch (e) {
    return jsonResp({ error: String(e?.message ?? e) }, 500);
  }
});