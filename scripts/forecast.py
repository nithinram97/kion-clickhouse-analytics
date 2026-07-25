"""
Build forecasts for daily KPIs and write them to kion.kpi_forecast.

Approach: Holt-Winters (weekly seasonality) via statsmodels — no Prophet
compilation headaches, trains in seconds, good enough for a hackathon demo.

Method: train on all days except the last HOLDOUT_DAYS, forecast the
holdout + FUTURE_DAYS ahead. The holdout overlap is what makes the
"actual vs forecast" variance cards work.

Usage:
    pip install -r requirements.txt
    export CH_HOST=... CH_USER=default CH_PASSWORD=...   # or use .env values
    python forecast.py
"""

import os

import clickhouse_connect
import pandas as pd
from statsmodels.tsa.holtwinters import ExponentialSmoothing

KPIS = ["dau", "views", "watch_seconds", "engaged_users"]
HOLDOUT_DAYS = 28   # forecast overlaps last 4 weeks of actuals
FUTURE_DAYS = 14    # and extends 2 weeks past the data


def main() -> None:
    client = clickhouse_connect.get_client(
        host=os.environ["CH_HOST"],
        username=os.environ.get("CH_USER", "default"),
        password=os.environ["CH_PASSWORD"],
        secure=True,
    )

    df = client.query_df(
        f"SELECT dt, {', '.join(KPIS)} FROM kion.kpi_daily ORDER BY dt"
    )
    df["dt"] = pd.to_datetime(df["dt"])
    df = df.set_index("dt").asfreq("D")
    # fill occasional gap days so the seasonal model doesn't choke
    df = df.interpolate(limit_direction="both")

    rows = []
    for kpi in KPIS:
        series = df[kpi].astype(float)
        train = series.iloc[:-HOLDOUT_DAYS]

        model = ExponentialSmoothing(
            train, trend="add", seasonal="add", seasonal_periods=7,
            initialization_method="estimated",
        ).fit()

        horizon = HOLDOUT_DAYS + FUTURE_DAYS
        forecast = model.forecast(horizon)

        # crude interval: +/- 1.96 * residual std (fine for a demo)
        resid_std = float((train - model.fittedvalues).std())
        for dt, value in forecast.items():
            rows.append(
                {
                    "dt": dt.date(),
                    "kpi_name": kpi,
                    "forecast": max(float(value), 0.0),
                    "lower_bound": max(float(value) - 1.96 * resid_std, 0.0),
                    "upper_bound": float(value) + 1.96 * resid_std,
                    "model": "holt_winters",
                }
            )
        print(f"{kpi}: trained on {len(train)} days, wrote {horizon} forecast rows")

    out = pd.DataFrame(rows)
    client.insert_df("kion.kpi_forecast", out)
    print(f"Inserted {len(out)} rows into kion.kpi_forecast")


if __name__ == "__main__":
    main()
