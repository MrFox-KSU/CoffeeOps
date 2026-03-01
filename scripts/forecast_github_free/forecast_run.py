import argparse, os, json, datetime as dt, sys
import numpy as np
import pandas as pd
import requests
import lightgbm as lgb

def headers(key: str):
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }

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

def make_features(y: pd.Series, lags=(1,7,14,28), rolls=(7,14,28)):
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

def safe_update_run(base, h, run_id, patch):
    try:
        rest_patch(base, h, f"/rest/v1/forecast_runs?id=eq.{run_id}", patch)
    except Exception:
        pass

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

    # Load run row
    run_rows = rest_get(base, h, "/rest/v1/forecast_runs",
                        params={"id": f"eq.{args.run_id}",
                                "select": "id,org_id,horizon_days,history_days,anchor_date,branch_id,engine,visibility"})
    if not run_rows:
        raise RuntimeError("Run not found")
    run = run_rows[0]

    org_id = run["org_id"]
    branch_id = run.get("branch_id")
    H = int(run["horizon_days"])
    hist = int(run["history_days"])
    anchor = dt.date.fromisoformat(run["anchor_date"])
    start = anchor - dt.timedelta(days=hist-1)

    safe_update_run(base, h, args.run_id, {"status":"running","started_at": dt.datetime.utcnow().isoformat()+"Z"})

    # Pull history series
    if branch_id:
        series = rest_post(base, h, "/rest/v1/rpc/get_sales_daily_range_branch",
                           {"p_org_id": org_id, "p_branch_id": branch_id, "p_start": str(start), "p_end": str(anchor)})
    else:
        series = rest_post(base, h, "/rest/v1/rpc/get_sales_daily_range",
                           {"p_org_id": org_id, "p_start": str(start), "p_end": str(anchor)})

    df = pd.DataFrame(series)
    if df.empty:
        raise RuntimeError("No history in window")

    df["day"] = pd.to_datetime(df["day"])
    df = df.set_index("day").sort_index()

    idx = pd.date_range(df.index.min(), df.index.max(), freq="D")
    df = df.reindex(idx)
    df["net_sales"] = df["net_sales"].fillna(0.0).astype(float)

    y = df["net_sales"]
    feats = make_features(y).dropna()
    y_aligned = y.loc[feats.index]
    X = feats.drop(columns=["y"])
    ytrain = y_aligned.values

    qs = [0.05, 0.10, 0.50, 0.90, 0.95]
    models = {q: train_quantile(X, ytrain, q) for q in qs}

    future_days = [anchor + dt.timedelta(days=i) for i in range(1, H+1)]
    y_full = y.copy()
    preds = {q: [] for q in qs}

    for dday in future_days:
        ts = pd.Timestamp(dday)
        f = make_features(y_full).loc[[ts]].drop(columns=["y"], errors="ignore").fillna(0.0)
        for q in qs:
            preds[q].append(float(models[q].predict(f)[0]))
        y_full.loc[ts] = preds[0.50][-1]

    engine = run.get("engine") or "github_free"
    visibility = run.get("visibility") or "org"

    out = []
    for i, dday in enumerate(future_days):
        out.append({
            "run_id": args.run_id,
            "org_id": org_id,
            "day": str(dday),
            "p50_net_sales": preds[0.50][i],
            "p80_low": preds[0.10][i],
            "p80_high": preds[0.90][i],
            "p95_low": preds[0.05][i],
            "p95_high": preds[0.95][i],
            "engine": engine,
            "visibility": visibility,
        })

    # Idempotent outputs
    rest_delete(base, h, "/rest/v1/forecast_outputs", params={"run_id": f"eq.{args.run_id}"})
    r = requests.post(base + "/rest/v1/forecast_outputs", headers=h, data=json.dumps(out), timeout=120)
    r.raise_for_status()

    safe_update_run(base, h, args.run_id, {
        "status":"succeeded",
        "finished_at": dt.datetime.utcnow().isoformat()+"Z",
        "message":"GitHub forecast completed",
        "metrics": {"engine":"github_free","algo":"lgbm_quantile","horizon_days":H,"history_days":hist}
    })

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Best-effort mark run failed if we can parse run_id from args
        try:
            rid = None
            for i, a in enumerate(sys.argv):
                if a == "--run-id" and i+1 < len(sys.argv):
                    rid = sys.argv[i+1]
            if rid:
                SUPABASE_URL = os.environ.get("SUPABASE_URL","").strip().rstrip("/")
                SRK = os.environ.get("SUPABASE_SERVICE_ROLE_KEY","").strip()
                if SUPABASE_URL and SRK:
                    base = SUPABASE_URL
                    h = headers(SRK)
                    msg = str(e)
                    if len(msg) > 900:
                        msg = msg[:900]
                    safe_update_run(base, h, rid, {"status":"failed","message": msg, "finished_at": dt.datetime.utcnow().isoformat()+"Z"})
        except Exception:
            pass
        raise
