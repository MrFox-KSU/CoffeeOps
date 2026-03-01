import argparse, os, json, datetime as dt
import numpy as np
import pandas as pd
import requests
import lightgbm as lgb

def headers(url, key):
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}

def rest_get(url, h, path, params=None):
    r = requests.get(url + path, headers=h, params=params); r.raise_for_status(); return r.json()

def rest_post(url, h, path, body):
    r = requests.post(url + path, headers=h, data=json.dumps(body)); r.raise_for_status(); return r.json()

def rest_patch(url, h, path, body):
    r = requests.patch(url + path, headers=h, data=json.dumps(body)); r.raise_for_status(); return r.text

def rest_delete(url, h, path, params=None):
    r = requests.delete(url + path, headers=h, params=params); r.raise_for_status(); return r.text

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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    args = ap.parse_args()

        SUPABASE_URL = os.environ.get("SUPABASE_URL","").strip().rstrip("/")
    if not SUPABASE_URL or not SUPABASE_URL.startswith("http"):
        raise RuntimeError("Missing/invalid SUPABASE_URL. Set GitHub Actions secret SUPABASE_URL to https://<project>.supabase.co")
    SRK = os.environ.get("SUPABASE_SERVICE_ROLE_KEY","").strip()
    if not SRK:
        raise RuntimeError("Missing SUPABASE_SERVICE_ROLE_KEY. Set GitHub Actions secret SUPABASE_SERVICE_ROLE_KEY")
    h = headers(SUPABASE_URL, SRK)

    run = rest_get(SUPABASE_URL, h, "/rest/v1/forecast_runs", params={"id": f"eq.{args.run_id}", "select": "id,org_id,horizon_days,history_days,anchor_date,branch_id"})
    if not run:
        raise RuntimeError("Run not found")
    run = run[0]

    org_id = run["org_id"]
    H = int(run["horizon_days"])
    hist = int(run["history_days"])
    anchor = dt.date.fromisoformat(run["anchor_date"])
    start = anchor - dt.timedelta(days=hist-1)

    rest_patch(SUPABASE_URL, h, f"/rest/v1/forecast_runs?id=eq.{args.run_id}", {"status":"running","started_at": dt.datetime.utcnow().isoformat()+"Z"})

    series = rest_post(SUPABASE_URL, h, "/rest/v1/rpc/get_sales_daily_range", {"p_org_id": org_id, "p_start": str(start), "p_end": str(anchor)})
    df = pd.DataFrame(series)
    if df.empty:
        raise RuntimeError("No history in window")

    df["day"] = pd.to_datetime(df["day"])
    df = df.set_index("day").sort_index()

    # fill missing dates with 0
    idx = pd.date_range(df.index.min(), df.index.max(), freq="D")
    df = df.reindex(idx)
    df["net_sales"] = df["net_sales"].fillna(0.0).astype(float)

    y = df["net_sales"]
    feats = make_features(y).dropna()
    y_aligned = y.loc[feats.index]
    X = feats.drop(columns=["y"])
    ytrain = y_aligned.values

    qs = [0.10, 0.50, 0.90, 0.05, 0.95]
    models = {q: train_quantile(X, ytrain, q) for q in qs}

    # recursive forecast using median
    future_days = [anchor + dt.timedelta(days=i) for i in range(1, H+1)]
    y_full = y.copy()
    preds = {q: [] for q in qs}

    for dday in future_days:
        ts = pd.Timestamp(dday)
        f = make_features(y_full).loc[[ts]].drop(columns=["y"], errors="ignore").fillna(0.0)
        for q in qs:
            preds[q].append(float(models[q].predict(f)[0]))
        y_full.loc[ts] = preds[0.50][-1]

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
        })

    # idempotent outputs
    rest_delete(SUPABASE_URL, h, "/rest/v1/forecast_outputs", params={"run_id": f"eq.{args.run_id}"})
    requests.post(SUPABASE_URL + "/rest/v1/forecast_outputs", headers=h, data=json.dumps(out)).raise_for_status()

    rest_patch(SUPABASE_URL, h, f"/rest/v1/forecast_runs?id=eq.{args.run_id}", {
        "status":"succeeded",
        "finished_at": dt.datetime.utcnow().isoformat()+"Z",
        "message":"GitHub forecast completed",
        "metrics": {"engine":"github_free","algo":"lgbm_quantile","horizon_days":H,"history_days":hist}
    })

if __name__ == "__main__":
    main()

