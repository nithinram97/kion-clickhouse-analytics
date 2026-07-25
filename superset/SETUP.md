# Superset setup

Superset comes up at http://localhost:8088 (admin/admin unless changed in `.env`).
The compose command installs `clickhouse-connect` automatically on first boot.

## 1. Connect ClickHouse Cloud

Settings → Database Connections → + Database → ClickHouse Connect, or paste the
SQLAlchemy URI:

```
clickhousedb://default:<PASSWORD>@<your-instance>.clickhouse.cloud:8443/kion?secure=true
```

## 2. Create datasets

Add these as datasets (all join-free by design):

| Dataset | Powers |
|---|---|
| `kion.kpi_daily` | KPI trend dashboards, forecast-vs-actual |
| `kion.kpi_item_daily` | Movie/show one-pager dashboard |
| `kion.kpi_segment_daily` | Segment one-pager dashboard |
| `kion.fact_watch` | Free exploration, genre/country breakdowns |
| `kion.kpi_forecast` | Forecast overlays |

## 3. Suggested dashboards (one per deep-link target)

1. **KPI Overview** — big-number cards + time series per KPI. Native filters: date range.
2. **Content One-Pager** — filtered on `title`/`item_id`. Charts: viewers trend,
   completion rate, watch hours, avg watched pct.
3. **Segment One-Pager** — native filters: `age`, `income`, `sex`, `kids_flg`.
4. **Forecast vs Actual** — mixed chart joining `kpi_daily` + `kpi_forecast` (use a
   SQL Lab virtual dataset for the join).

Set the default date range to end **2022-08-22** (dataset's last day) or every
"last N days" chart will be empty.

## 4. Deep-linking from KPI cards (button → filtered dashboard)

Don't hand-encode filter state in URLs (fragile across versions). Use the
permalink API from your Express backend at click time:

```
POST http://localhost:8088/api/v1/dashboard/<dashboard_id>/permalink
Authorization: Bearer <access_token>        # from /api/v1/security/login
Content-Type: application/json

{
  "filterState": {
    "nativeFilters": { ... filter values built from chat context ... }
  }
}
```

Response contains a `key`; redirect the browser to:

```
http://localhost:8088/superset/dashboard/p/<key>/
```

Flow: LibreChat produces the KPI overview → each card's button calls your
backend with the chat context (KPI name, date range, segment/title) → backend
logs into Superset, creates the permalink, returns the URL → frontend opens it.

Tip: capture the exact `nativeFilters` JSON shape by setting filters manually
on the dashboard, creating a permalink from the share menu, and inspecting the
network call — then template that JSON in your backend.
