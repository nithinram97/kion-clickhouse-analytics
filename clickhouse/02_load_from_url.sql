-- =============================================================
-- KION Analytics — Load data (zero local download)
-- Prereq: run rehost/rehost.sh ONCE in a GitHub Codespace to put
--         interactions.csv.gz / users_en.csv.gz / items_en.csv.gz
--         into your own public repo, then set the repo below.
-- Find/replace:  <GH_USER>/kion-data  ->  your repo
-- =============================================================

SET max_http_get_redirects = 5;  -- raw.githubusercontent redirects

-- ---------- interactions (~5,476,251 rows) ----------
INSERT INTO kion.interactions (user_id, item_id, last_watch_dt, total_dur, watched_pct)
SELECT user_id, item_id, last_watch_dt, total_dur, watched_pct
FROM url(
    'https://raw.githubusercontent.com/<GH_USER>/kion-data/main/interactions.csv.gz',
    CSVWithNames,
    'user_id UInt32, item_id UInt32, last_watch_dt Date,
     total_dur UInt32, watched_pct Nullable(Float32)'
);

-- ---------- users (~962,179 rows; idx = pandas index col, discarded) ----------
INSERT INTO kion.users (user_id, age, income, sex, kids_flg)
SELECT user_id,
       ifNull(age, '')     AS age,
       ifNull(income, '')  AS income,
       ifNull(sex, '')     AS sex,
       ifNull(kids_flg, 0) AS kids_flg
FROM url(
    'https://raw.githubusercontent.com/<GH_USER>/kion-data/main/users_en.csv.gz',
    CSVWithNames,
    'idx UInt32, user_id UInt32, age Nullable(String), income Nullable(String),
     sex Nullable(String), kids_flg Nullable(UInt8)'
);

-- ---------- items (~15,706 rows; *_translated -> directors/actors) ----------
INSERT INTO kion.items (item_id, content_type, title, title_orig, release_year,
                        genres, countries, for_kids, age_rating, studios,
                        directors, actors, description, keywords)
SELECT item_id,
       ifNull(content_type, '') AS content_type,
       ifNull(title, ''), ifNull(title_orig, ''),
       toUInt16OrNull(toString(release_year)) AS release_year,
       ifNull(genres, ''), ifNull(countries, ''),
       toUInt8OrNull(toString(for_kids)) AS for_kids,
       age_rating,
       ifNull(studios, ''),
       ifNull(directors_translated, ''),
       ifNull(actors_translated, ''),
       ifNull(description, ''), ifNull(keywords, '')
FROM url(
    'https://raw.githubusercontent.com/<GH_USER>/kion-data/main/items_en.csv.gz',
    CSVWithNames,
    'idx UInt32, item_id UInt32, content_type Nullable(String),
     title Nullable(String), title_orig Nullable(String),
     release_year Nullable(Float32), genres Nullable(String),
     countries Nullable(String), for_kids Nullable(Float32),
     age_rating Nullable(Float32), studios Nullable(String),
     description Nullable(String), keywords Nullable(String),
     actors_translated Nullable(String), actors_transliterated Nullable(String),
     directors_translated Nullable(String), transliterated Nullable(String)'
);

-- Materialize the user projection after load (cheaper than during inserts)
ALTER TABLE kion.interactions MATERIALIZE PROJECTION by_user;
