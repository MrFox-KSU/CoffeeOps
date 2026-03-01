import argparse, os, json, datetime as dt, sys
import numpy as np
import pandas as pd
import requests
import lightgbm as lgb

Z80 = 1.281551565545
Z95 = 1.644853626951

def headers(key: str):
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}

def rest_get(base: str, h: dict, path: str, params=None):
    r = requests.get(base + path, headers=h, params=params, timeout=60)
    r.raise_for_status()
    return r.json()

def rest_post(base: str, h: dict, path: str, body: dict):
    r = requests.post(base + path, headers=h, data=json.dumps(body), timeout=120)
    r.raise_for_status()
    return r.json()

def rest_patch(base: str, h: dict, path: str, body: dict):
    r = requests.patch(base + path, headers=h, data=json.dumps(body), timeout=120)
    r.raise_for_status()
    return r.text

def rest_delete(base: str, h: dict, path: str, params=None):
    r = requests.delete(base + path, headers=h, params=params, timeout=120)
    r.raise_for_status()
    return r.text

def safe_update_run(base, h, run_id, patch):
    try:
        rest_patch(base, h, f"/rest/v1/forecast_runs?id=eq.{run_id}", patch)
    except Exception:
        pass

def dynamic_windows(n: int):
    base_lags = [1, 7, 14, 28]
    base_rolls = [7, 14, 28]
    lags = [k for k in base_lags if k < n]
    rolls = [w for w in base_rolls if w < n]
    if n > 1 and 1 not in lags:
        lags = [1]
    return lags, rolls

def make_features(y: pd.Series, lags, rolls):
    df = pd.DataFrame({"y": y})
    for k in lags:
        df[f"lag_{k}"] = df["y"].shift(k)
    for w in rolls:
        df[f"roll_mean_{w}"] = df["y"].shift(1).rolling(w).mean()
        df[f"roll_std_{w}"]  = df["y"].shift(1).rolling(w).std()
    df["dow"] = df.index.dayofweek
    df["month"] = df.index.month
    df["doy"] = df.index.dayofyear
    return df

def train_quantile(X, y, q):
    params = {
        "objective": "quantile",
        "alpha": q,
        "learning_rate": 0.05,
        "num_leaves": 31,
        "min_data_in_leaf": 20,
        "feature_fraction": 0.9,
        "bagging_fraction": 0.9,
        "bagging_freq": 1,
        "verbosity": -1,
    }
    dtrain = lgb.Dataset(X, label=y)
    return lgb.train(params, dtrain, num_boost_round=500)

def clamp0(x: float) -> float:
    return float(x) if x > 0 else 0.0

def baseline_quantiles(hist: np.ndarray):
    mu = float(np.mean(hist)) if hist.size else 0.0
    sd = float(np.std(hist, ddof=0)) if hist.size else 0.0
    p50 = clamp0(mu)
    p80_low  = clamp0(mu - Z80 * sd)
    p80_high = clamp0(mu + Z80 * sd)
    p95_low  = clamp0(mu - Z95 * sd)
    p95_high = clamp0(mu + Z95 * sd)
    return p50, p80_low, p80_high, p95_low, p95_high

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    args = ap.parse_args()

    SUPABASE_URL = os.environ.get("SUPABASE_URL","").strip().rstrip("/")
    SRK = os.environ.get("SUPABASE_SERVICE_ROLE_KEY","").strip()

    if not SUPABASE_URL or not SUPABASE_URL.startswith("http"):
        raise RuntimeError("Missing/invalid SUPABASE_URL. Set GitHub Actions secret SUPABASE_URL to https://<project>.supabase.co")
    if not SRK:
        raise RuntimeError("Missing SUPABASE_SERVICE_ROLE_KEY. Set GitHub Actions secret SUPABASE_SERVICE_ROLE_KEY")

    base = SUPABASE_URL
    h = headers(SRK)

    run_rows = rest_get(base, h, "/rest/v1/forecast_runs",
                        params={"id": f"eq.{args.run_id}",
                                "select": "id,org_id,horizon_days,history_days,anchor_date,branch_id,engine,visibility"})
    if not run_rows:
        raise RuntimeError("Run not found")
    run = run_rows[0]

    org_id = run["org_id"]
    branch_id = run.get("branch_id")
    H = int(run["horizon_days"])
    hist_days = int(run["history_days"])
    anchor = dt.date.fromisoformat(run["anchor_date"])
    start = anchor - dt.timedelta(days=hist_days-1)

    safe_update_run(base, h, args.run_id, {"status":"running","started_at": dt.datetime.utcnow().isoformat()+"Z"})

    # Pull sparse history (only days with sales)
    if branch_id:
        series = rest_post(base, h, "/rest/v1/rpc/get_sales_daily_range_branch",
                           {"p_org_id": org_id, "p_branch_id": branch_id, "p_start": str(start), "p_end": str(anchor)})
    else:
        series = rest_post(base, h, "/rest/v1/rpc/get_sales_daily_range",
                           {"p_org_id": org_id, "p_start": str(start), "p_end": str(anchor)})

    df = pd.DataFrame(series)
    if df.empty:
        raise RuntimeError("No history returned for this window.")

    df["day"] = pd.to_datetime(df["day"])
    df = df.set_index("day").sort_index()

    # CRITICAL: reindex the FULL window start..anchor (not just observed min..max)
    idx = pd.date_range(pd.Timestamp(start), pd.Timestamp(anchor), freq="D")
    df = df.reindex(idx)
    df["net_sales"] = df["net_sales"].fillna(0.0).astype(float)

    y = df["net_sales"]
    n = len(y)

    lags, rolls = dynamic_windows(n)
    feats = make_features(y, lags, rolls).dropna()
    X = feats.drop(columns=["y"])
    ytrain = y.loc[feats.index].values

    use_baseline = (X.shape[0] == 0) or (X.shape[1] == 0)

    future_days = [anchor + dt.timedelta(days=i) for i in range(1, H+1)]
    engine = run.get("engine") or "github_free"
    visibility = run.get("visibility") or "org"

    if use_baseline:
        hist = y.tail(min(28, n)).values
        p50, p80_low, p80_high, p95_low, p95_high = baseline_quantiles(hist)
        out = [{
            "run_id": args.run_id,
            "org_id": org_id,
            "day": str(d),
            "p50_net_sales": p50,
            "p80_low": p80_low,
            "p80_high": p80_high,
            "p95_low": p95_low,
            "p95_high": p95_high,
            "engine": engine,
            "visibility": visibility,
        } for d in future_days]

        rest_delete(base, h, "/rest/v1/forecast_outputs", params={"run_id": f"eq.{args.run_id}"})
        requests.post(base + "/rest/v1/forecast_outputs", headers=h, data=json.dumps(out), timeout=120).raise_for_status()

        safe_update_run(base, h, args.run_id, {
            "status":"succeeded",
            "finished_at": dt.datetime.utcnow().isoformat()+"Z",
            "message":"Baseline forecast (insufficient history for ML features)",
            "metrics": {"engine":"github_free","algo":"baseline_mean_std","horizon_days":H,"history_days":hist_days}
        })
        return

    # ML path
    qs = [0.05, 0.10, 0.50, 0.90, 0.95]
    models = {q: train_quantile(X, ytrain, q) for q in qs}

    y_full = y.copy()
    preds = {q: [] for q in qs}

    for d in future_days:
        ts = pd.Timestamp(d)
        # extend series for feature creation
        if ts not in y_full.index:
            y_full.loc[ts] = np.nan

        f = make_features(y_full, lags, rolls).loc[[ts]].drop(columns=["y"], errors="ignore").fillna(0.0)
        for q in qs:
            preds[q].append(clamp0(float(models[q].predict(f)[0])))
        # recursive median
        y_full.loc[ts] = preds[0.50][-1]

    out = []
    for i, d in enumerate(future_days):
        out.append({
            "run_id": args.run_id,
            "org_id": org_id,
            "day": str(d),
            "p50_net_sales": preds[0.50][i],
            "p80_low": preds[0.10][i],
            "p80_high": preds[0.90][i],
            "p95_low": preds[0.05][i],
            "p95_high": preds[0.95][i],
            "engine": engine,
            "visibility": visibility,
        })

    rest_delete(base, h, "/rest/v1/forecast_outputs", params={"run_id": f"eq.{args.run_id}"})
    requests.post(base + "/rest/v1/forecast_outputs", headers=h, data=json.dumps(out), timeout=120).raise_for_status()

    safe_update_run(base, h, args.run_id, {
        "status":"succeeded",
        "finished_at": dt.datetime.utcnow().isoformat()+"Z",
        "message":"GitHub forecast completed (LightGBM quantiles)",
        "metrics": {"engine":"github_free","algo":"lgbm_quantile","horizon_days":H,"history_days":hist_days}
    })

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # best-effort mark failed
        try:
            rid = None
            for i, a in enumerate(sys.argv):
                if a == "--run-id" and i+1 < len(sys.argv):
                    rid = sys.argv[i+1]
            if rid:
                base = os.environ.get("SUPABASE_URL","").strip().rstrip("/")
                srk = os.environ.get("SUPABASE_SERVICE_ROLE_KEY","").strip()
                if base and srk:
                    safe_update_run(base, headers(srk), rid, {
                        "status":"failed",
                        "finished_at": dt.datetime.utcnow().isoformat()+"Z",
                        "message": str(e)[:900],
                    })
        except Exception:
            pass
        raise
