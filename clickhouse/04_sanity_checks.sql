-- =============================================================
-- KION Analytics — Sanity checks (expected values in comments)
-- =============================================================

SELECT count() FROM kion.interactions;   -- 5,476,251
SELECT count() FROM kion.users;          -- 962,179
SELECT count() FROM kion.items;          -- 15,706
SELECT count() FROM kion.fact_watch;     -- 5,476,251

SELECT min(last_watch_dt), max(last_watch_dt) FROM kion.interactions;
-- 2021-03-13 .. 2022-08-22  (hardcode "today" = 2022-08-22 in the app!)

SELECT count() FROM kion.kpi_daily;      -- one row per day (~528)

-- KPI card smoke test
SELECT dt, dau, views, round(watch_seconds/3600) AS watch_hours,
       round(completion_rate * 100, 1) AS completion_pct
FROM kion.kpi_daily
ORDER BY dt DESC
LIMIT 7;

-- Actual vs forecast (after running scripts/forecast.py)
SELECT f.dt, f.kpi_name, round(f.forecast) AS forecast, k.dau AS actual,
       round((k.dau - f.forecast) / f.forecast * 100, 1) AS variance_pct
FROM kion.kpi_forecast f
LEFT JOIN kion.kpi_daily k ON k.dt = f.dt
WHERE f.kpi_name = 'dau'
ORDER BY f.dt DESC
LIMIT 14;
