-- =============================================================
-- KION Analytics — Schema (run in ClickHouse Cloud SQL console)
-- =============================================================

CREATE DATABASE IF NOT EXISTS kion;

-- ---------- Dimension: users ----------
CREATE TABLE IF NOT EXISTS kion.users
(
    user_id  UInt32,
    age      LowCardinality(String),   -- e.g. 'age_25_34' ('' if unknown)
    income   LowCardinality(String),   -- e.g. 'income_20_40'
    sex      LowCardinality(String),   -- 'M' / 'F' / ''
    kids_flg UInt8 DEFAULT 0
)
ENGINE = MergeTree
ORDER BY user_id;

-- ---------- Dimension: items ----------
CREATE TABLE IF NOT EXISTS kion.items
(
    item_id       UInt32,
    content_type  LowCardinality(String),          -- 'film' | 'series'
    title         String,
    title_orig    String,
    release_year  Nullable(UInt16),
    genres        String,                          -- comma-separated, as in CSV
    genres_arr    Array(String) MATERIALIZED
                  arrayMap(x -> trim(x), splitByChar(',', genres)),
    countries     String,
    countries_arr Array(String) MATERIALIZED
                  arrayMap(x -> trim(x), splitByChar(',', countries)),
    for_kids      Nullable(UInt8),
    age_rating    Nullable(Float32),               -- source has '16.0'
    studios       String,
    directors     String,                          -- from directors_translated
    actors        String,                          -- from actors_translated
    description   String,
    keywords      String
)
ENGINE = MergeTree
ORDER BY item_id;

-- ---------- Fact: interactions ----------
-- ORDER BY date first (KPI time-range scans), item second (movie one-pager).
CREATE TABLE IF NOT EXISTS kion.interactions
(
    user_id       UInt32,
    item_id       UInt32,
    last_watch_dt Date,
    total_dur     UInt32,             -- watch seconds
    watched_pct   Nullable(Float32),  -- 0..100, has NULLs
    is_completed  UInt8 MATERIALIZED watched_pct >= 90,
    is_meaningful UInt8 MATERIALIZED watched_pct >= 10  -- "real view" (Kion challenge threshold)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(last_watch_dt)
ORDER BY (last_watch_dt, item_id, user_id);

-- User-centric access path (segment/user queries)
ALTER TABLE kion.interactions
    ADD PROJECTION IF NOT EXISTS by_user (SELECT * ORDER BY (user_id, last_watch_dt));

-- ---------- Forecasts (written by scripts/forecast.py) ----------
CREATE TABLE IF NOT EXISTS kion.kpi_forecast
(
    dt          Date,
    kpi_name    LowCardinality(String),   -- 'dau', 'views', 'watch_seconds', ...
    forecast    Float64,
    lower_bound Float64,
    upper_bound Float64,
    model       LowCardinality(String),   -- 'holt_winters', 'prophet', ...
    trained_at  DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(trained_at)
ORDER BY (kpi_name, dt);
