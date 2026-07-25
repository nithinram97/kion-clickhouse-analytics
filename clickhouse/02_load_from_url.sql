-- =============================================================
-- KION Analytics — Load data (zero local download)
--
-- Verified against the real files from github.com/irsafilo/KION_DATASET
-- (data_en.zip). Row counts and column quirks below are measured, not
-- assumed:
--   interactions.csv  5,476,251 rows  (no index column)
--   users_en.csv        840,197 rows  (leading unnamed pandas index col)
--   items_en.csv         15,963 rows  (leading unnamed pandas index col)
--
-- Quirks handled here:
--   * users_en / items_en start with an unnamed pandas index column.
--     `input_format_with_names_use_header = 0` forces positional mapping
--     so the blank header name can't confuse column matching.
--   * The English items file has actors_translated / directors_translated
--     (there are no plain `actors` / `directors` columns).
--   * release_year and for_kids are stored as floats ('2002.0', '1.0')
--     with empty strings for missing -> read as Nullable(Float32) and
--     cast; toUInt16()/toUInt8() propagate NULL for NULL input.
--   * age / income / sex are blank for ~14k users -> ifNull to ''.
--   * watched_pct is genuinely NULL for some interactions -> stays Nullable.
--
-- Prereq: run rehost/rehost.sh ONCE in a GitHub Codespace to publish
--         interactions.csv.gz / users_en.csv.gz / items_en.csv.gz to your
--         own public repo. ClickHouse url() cannot read .zip.
-- Find/replace:  nithinramappacontact-byte/kion-data  ->  your repo
-- =============================================================

SET max_http_get_redirects = 5;  -- github.com redirects

-- ---------- interactions (5,476,251 rows) ----------
INSERT INTO kion.interactions (user_id, item_id, last_watch_dt, total_dur, watched_pct)
SELECT user_id, item_id, last_watch_dt, total_dur, watched_pct
FROM url(
    'https://raw.githubusercontent.com/nithinramappacontact-byte/kion-clickhouse-analytics/refs/heads/main/interactions.csv.gz',
    CSVWithNames,
    'user_id UInt32,
     item_id UInt32,
     last_watch_dt Date,
     total_dur UInt32,
     watched_pct Nullable(Float32)'
);

-- ---------- users (840,197 rows; idx = pandas index column, discarded) ----------
INSERT INTO kion.users (user_id, age, income, sex, kids_flg)
SELECT
    user_id,
    ifNull(age, '')     AS age,      -- ~14k blanks
    ifNull(income, '')  AS income,   -- ~15k blanks
    ifNull(sex, '')     AS sex,      -- ~14k blanks; values 'M' / 'F'
    ifNull(kids_flg, 0) AS kids_flg
FROM url(
    'https://raw.githubusercontent.com/nithinramappacontact-byte/kion-clickhouse-analytics/refs/heads/main/users_en.csv.gz',
    CSVWithNames,
    'idx UInt32,
     user_id UInt32,
     age Nullable(String),
     income Nullable(String),
     sex Nullable(String),
     kids_flg Nullable(UInt8)'
)
SETTINGS input_format_with_names_use_header = 0;

-- ---------- items (15,963 rows; idx discarded, *_translated mapped) ----------
INSERT INTO kion.items (item_id, content_type, title, title_orig, release_year,
                        genres, countries, for_kids, age_rating, studios,
                        directors, actors, description, keywords)
SELECT
    item_id,
    ifNull(content_type, '')    AS content_type,   -- 'film' | 'series'
    ifNull(title, '')           AS title,
    ifNull(title_orig, '')      AS title_orig,
    toUInt16(release_year)      AS release_year,   -- '2002.0' -> 2002, NULL stays NULL
    ifNull(genres, '')          AS genres,         -- 'drama, foreign, detective'
    ifNull(countries, '')       AS countries,
    toUInt8(for_kids)           AS for_kids,       -- '1.0'/'0.0'/'' (mostly empty)
    age_rating,                                    -- '16.0' -> kept as Float32
    ifNull(studios, '')         AS studios,
    ifNull(directors_translated, '') AS directors,
    ifNull(actors_translated, '')    AS actors,
    ifNull(description, '')     AS description,
    ifNull(keywords, '')        AS keywords
FROM url(
    'https://raw.githubusercontent.com/nithinramappacontact-byte/kion-clickhouse-analytics/refs/heads/main/items_en.csv.gz',
    CSVWithNames,
    'idx UInt32,
     item_id UInt32,
     content_type Nullable(String),
     title Nullable(String),
     title_orig Nullable(String),
     release_year Nullable(Float32),
     genres Nullable(String),
     countries Nullable(String),
     for_kids Nullable(Float32),
     age_rating Nullable(Float32),
     studios Nullable(String),
     description Nullable(String),
     keywords Nullable(String),
     actors_translated Nullable(String),
     actors_transliterated Nullable(String),
     directors_translated Nullable(String),
     transliterated Nullable(String)'
)
SETTINGS input_format_with_names_use_header = 0;

-- Materialize the user projection after load (cheaper than during inserts)
ALTER TABLE kion.interactions MATERIALIZE PROJECTION by_user;

-- ---------- verify ----------
-- SELECT count() FROM kion.interactions;   -- 5476251
-- SELECT count() FROM kion.users;          --  840197
-- SELECT count() FROM kion.items;          --   15963