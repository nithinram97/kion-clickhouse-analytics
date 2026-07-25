# KION Analytics — Hackathon Stack

OTT (Sony LIV-style) analytics on the [KION dataset](https://github.com/irsafilo/KION_DATASET):
ClickHouse Cloud warehouse + local LibreChat (AI assistant) + local Superset (dashboards).

```
kion-analytics/
├── docker-compose.yml        # LibreChat + MongoDB + Superset (local)
├── .env.example              # copy to .env, fill keys
├── clickhouse/
│   ├── 01_schema.sql         # database + tables + projection
│   ├── 02_load_from_url.sql  # zero-download ingestion via url()
│   ├── 03_rollups.sql        # fact_watch + kpi_daily/item/segment
│   ├── 04_sanity_checks.sql  # expected counts + smoke queries
│   └── 05_ml_forecast.sql    # pure-SQL in-database forecasting (no Python)
├── rehost/rehost.sh          # one-time: zip -> csv.gz in your repo (Codespace)
├── librechat/librechat.yaml  # LibreChat config incl. ClickHouse MCP server
├── superset/SETUP.md         # ClickHouse URI, datasets, dashboards, deep-links
└── scripts/
    ├── forecast.py           # Holt-Winters -> kion.kpi_forecast
    └── requirements.txt
```

## Setup order

1. **Re-host data (one-time, ~2 min, no laptop download)**
   Create a public repo `<you>/kion-data`, open a **GitHub Codespace** on it, run
   `rehost/rehost.sh`. It prints the three raw `.csv.gz` URLs.

2. **ClickHouse Cloud** — in the SQL console, run in order:
   `01_schema.sql` → `02_load_from_url.sql` (replace `<GH_USER>/kion-data`) →
   `03_rollups.sql` → `04_sanity_checks.sql` (verify counts) →
   `05_ml_forecast.sql` (pure-SQL forecasts, model=`sql_trend_dow`).

3. **Local stack**
   ```bash
   cp .env.example .env   # fill GOOGLE_KEY etc.
   docker compose up -d
   ```
   - LibreChat → http://localhost:3080
   - Superset  → http://localhost:8088 (admin/admin)
   - ClickHouse MCP server → internal :8000 (LibreChat connects automatically;
     in the LibreChat UI, create an Agent and enable the `clickhouse` MCP tools
     so it can run live SELECTs against `kion.*`)

4. **Superset** — follow `superset/SETUP.md` (connect ClickHouse, datasets,
   4 dashboards, permalink deep-linking).

5. **Forecasts** — two interchangeable engines writing to `kion.kpi_forecast`:
   - **Pure SQL** (already done in step 2 via `05_ml_forecast.sql`), model
     `sql_trend_dow` — linear trend × day-of-week index, trained in-database.
   - **Python Holt-Winters** (optional, for comparison), model `holt_winters`:
     ```bash
     cd scripts && pip install -r requirements.txt
     export CH_HOST=... CH_USER=default CH_PASSWORD=...
     python forecast.py
     ```
   Filter by `model` in charts to compare the two.

## Things that will bite you if forgotten

- **Data ends 2022-08-22.** Hardcode "today" = `2022-08-22` in the app/dashboards,
  or every "last 7 days" view shows zeros.
- The English items file has `directors_translated`/`actors_translated`
  (not `directors`/`actors`) — `02_load_from_url.sql` already maps them.
- `users_en.csv` / `items_en.csv` carry a pandas index column — handled via
  explicit `url()` structures.
- `url()` cannot read `.zip` — that's why the one-time `.csv.gz` re-host exists.

## KPI set (all computable from these tables)

- **Engagement**: DAU/WAU/MAU, views, watch hours, watch time/user, avg watched %,
  completion rate (≥90%), engaged-user rate (≥10%), stickiness (DAU/MAU)
- **Content**: active titles, top titles by watch hours, genre share, film vs
  series split, new vs library share, catalog coverage
- **Audience**: segment mix (age × income × sex × kids), watch time per segment,
  kids-content share, week-over-week retention proxy
- **Forecast vs actual**: variance % on DAU, views, watch hours, engaged users
