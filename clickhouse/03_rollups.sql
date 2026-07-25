-- =============================================================
-- KION Analytics — Denormalized fact + KPI rollups
-- Run AFTER 02_load_from_url.sql. Dataset is static, so plain
-- INSERT SELECT rollups (no MVs to babysit during the hackathon).
-- =============================================================

-- ---------- Denormalized fact (Superset-friendly, join-free) ----------
CREATE TABLE IF NOT EXISTS kion.fact_watch
(
    last_watch_dt Date,
    user_id       UInt32,
    item_id       UInt32,
    total_dur     UInt32,
    watched_pct   Nullable(Float32),
    is_completed  UInt8,
    is_meaningful UInt8,
    -- user segment attributes
    age      LowCardinality(String),
    income   LowCardinality(String),
    sex      LowCardinality(String),
    kids_flg UInt8,
    -- item attributes
    content_type  LowCardinality(String),
    title         String,
    release_year  Nullable(UInt16),
    genres_arr    Array(String),
    countries_arr Array(String),
    age_rating    Nullable(Float32)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(last_watch_dt)
ORDER BY (last_watch_dt, content_type, item_id);

INSERT INTO kion.fact_watch
SELECT
    i.last_watch_dt, i.user_id, i.item_id, i.total_dur, i.watched_pct,
    i.is_completed, i.is_meaningful,
    u.age, u.income, u.sex, u.kids_flg,
    it.content_type, it.title, it.release_year,
    it.genres_arr, it.countries_arr, it.age_rating
FROM kion.interactions i
LEFT JOIN kion.users u  ON u.user_id = i.user_id
LEFT JOIN kion.items it ON it.item_id = i.item_id;

-- ---------- Daily platform KPIs (powers KPI cards + forecasts) ----------
CREATE TABLE IF NOT EXISTS kion.kpi_daily
ENGINE = MergeTree ORDER BY dt AS
SELECT
    last_watch_dt                            AS dt,
    uniqExact(user_id)                       AS dau,
    count()                                  AS views,
    sum(total_dur)                           AS watch_seconds,
    sum(total_dur) / uniqExact(user_id)      AS watch_sec_per_user,
    avg(watched_pct)                         AS avg_watched_pct,
    countIf(is_completed = 1) / count()      AS completion_rate,
    uniqExact(item_id)                       AS active_titles,
    uniqExactIf(user_id, is_meaningful = 1)  AS engaged_users
FROM kion.interactions
GROUP BY dt;

-- ---------- Daily per-item stats (movie/show one-pager) ----------
CREATE TABLE IF NOT EXISTS kion.kpi_item_daily
ENGINE = MergeTree ORDER BY (item_id, dt) AS
SELECT
    item_id,
    last_watch_dt AS dt,
    uniqExact(user_id)  AS viewers,
    count()             AS views,
    sum(total_dur)      AS watch_seconds,
    avg(watched_pct)    AS avg_watched_pct,
    countIf(is_completed = 1) / count() AS completion_rate
FROM kion.interactions
GROUP BY item_id, dt;

-- ---------- Daily per-segment stats (segment one-pager) ----------
CREATE TABLE IF NOT EXISTS kion.kpi_segment_daily
ENGINE = MergeTree ORDER BY (age, income, sex, kids_flg, dt) AS
SELECT
    age, income, sex, kids_flg,
    last_watch_dt AS dt,
    uniqExact(user_id) AS dau,
    count()            AS views,
    sum(total_dur)     AS watch_seconds,
    avg(watched_pct)   AS avg_watched_pct
FROM kion.fact_watch
GROUP BY age, income, sex, kids_flg, dt;
