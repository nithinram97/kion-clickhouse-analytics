-- =============================================================
-- KION Analytics — Forecasting with PURE ClickHouse SQL
-- (in-database "ML" — no Python needed)
--
-- Model: linear trend (simpleLinearRegression aggregate) ×
--        day-of-week seasonal index, i.e. a seasonal-trend model
--        trained and applied entirely inside ClickHouse.
--
-- Same shape as scripts/forecast.py: train on everything except
-- the last 28 days, forecast those 28 (overlap => variance cards)
-- plus 14 days beyond the data. Writes model='sql_trend_dow' so it
-- can coexist with 'holt_winters' rows for comparison.
-- Run AFTER 03_rollups.sql.
-- =============================================================

INSERT INTO kion.kpi_forecast (dt, kpi_name, forecast, lower_bound, upper_bound, model)
WITH
    (SELECT max(dt) FROM kion.kpi_daily) AS max_dt,
    max_dt - 27 AS holdout_start,   -- first forecasted day
    42 AS horizon_days,             -- 28 holdout + 14 future

    -- unpivot kpi_daily -> (dt, kpi_name, value)
    long AS
    (
        SELECT dt, kpi.1 AS kpi_name, kpi.2 AS value
        FROM kion.kpi_daily
        ARRAY JOIN
            [('dau',           toFloat64(dau)),
             ('views',         toFloat64(views)),
             ('watch_seconds', toFloat64(watch_seconds)),
             ('engaged_users', toFloat64(engaged_users))] AS kpi
    ),

    train AS (SELECT * FROM long WHERE dt < holdout_start),

    -- linear trend per KPI: value ~ k * day + b  (least squares in SQL)
    trend AS
    (
        SELECT kpi_name,
               simpleLinearRegression(toFloat64(toRelativeDayNum(dt)), value) AS kb
        FROM train
        GROUP BY kpi_name
    ),

    -- day-of-week seasonal index from the last 8 training weeks
    dow_idx AS
    (
        SELECT kpi_name, toDayOfWeek(dt) AS dow,
               avg(value) / avgIf_overall AS idx
        FROM train
        INNER JOIN
        (
            SELECT kpi_name, avg(value) AS avgIf_overall
            FROM train
            WHERE dt >= holdout_start - 56
            GROUP BY kpi_name
        ) o USING (kpi_name)
        WHERE dt >= holdout_start - 56
        GROUP BY kpi_name, dow, avgIf_overall
    ),

    -- residual std of the fitted model on train (for the interval)
    resid AS
    (
        SELECT t.kpi_name AS kpi_name,
               stddevPop(t.value -
                   (tr.kb.1 * toFloat64(toRelativeDayNum(t.dt)) + tr.kb.2) * d.idx) AS rstd
        FROM train t
        INNER JOIN trend tr ON tr.kpi_name = t.kpi_name
        INNER JOIN dow_idx d ON d.kpi_name = t.kpi_name AND d.dow = toDayOfWeek(t.dt)
        GROUP BY t.kpi_name
    ),

    future AS
    (
        SELECT holdout_start + toIntervalDay(number) AS dt
        FROM numbers(horizon_days)
    )

SELECT
    f.dt AS dt,
    tr.kpi_name AS kpi_name,
    greatest((tr.kb.1 * toFloat64(toRelativeDayNum(f.dt)) + tr.kb.2) * d.idx, 0) AS forecast,
    greatest(forecast - 1.96 * r.rstd, 0) AS lower_bound,
    forecast + 1.96 * r.rstd              AS upper_bound,
    'sql_trend_dow'                       AS model
FROM future f
CROSS JOIN trend tr
INNER JOIN dow_idx d ON d.kpi_name = tr.kpi_name AND d.dow = toDayOfWeek(f.dt)
INNER JOIN resid r  ON r.kpi_name = tr.kpi_name;

-- =============================================================
-- Bonus in-database ML/time-series tools worth showing judges
-- =============================================================

-- 1) Trainable ML in SQL: stochasticLinearRegression trains a model as an
--    aggregate state you can store and apply with evalMLMethod:
--
--    CREATE TABLE kion.ml_model_dau ENGINE = Memory AS
--    SELECT stochasticLinearRegressionState(0.01, 0.1, 32, 'Adam')
--           (toFloat64(dau), toFloat64(toRelativeDayNum(dt)),
--            toFloat64(toDayOfWeek(dt)))                        AS state
--    FROM kion.kpi_daily WHERE dt < (SELECT max(dt) - 27 FROM kion.kpi_daily);
--
--    SELECT evalMLMethod(state, toFloat64(toRelativeDayNum(dt)),
--                        toFloat64(toDayOfWeek(dt))) AS predicted_dau
--    FROM kion.ml_model_dau, kion.kpi_daily;
--
-- 2) STL decomposition — returns [seasonal, trend, residual] arrays:
--    SELECT seriesDecomposeSTL(groupArray(toFloat64(dau)), 7)[2] AS trend
--    FROM (SELECT dau FROM kion.kpi_daily ORDER BY dt);
--
-- 3) Anomaly detection on a KPI series (Tukey fences):
--    SELECT seriesOutliersDetectTukey(groupArray(toFloat64(dau)))
--    FROM (SELECT dau FROM kion.kpi_daily ORDER BY dt);
--
-- 4) Dominant period detection via FFT (not compiled into every build —
--    verify on your Cloud instance before demoing):
--    SELECT seriesPeriodDetectFFT(groupArray(toFloat64(dau)))
--    FROM (SELECT dau FROM kion.kpi_daily ORDER BY dt);   -- expect ~7
