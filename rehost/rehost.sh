#!/usr/bin/env bash
# =============================================================
# One-time re-host of KION English CSVs as .csv.gz
# Why: ClickHouse url() cannot open .zip archives, only gzip.
# Run this INSIDE a GitHub Codespace opened on a fresh PUBLIC
# repo (e.g. <you>/kion-data). Nothing touches your laptop.
# Gzipped sizes: interactions 64MB, users 7MB, items 6.2MB
# (all under GitHub's 100MB push limit).
# =============================================================
set -euo pipefail

wget -q https://github.com/irsafilo/KION_DATASET/raw/f69775be31fa5779907cf0a92ddedb70037fb5ae/data_en.zip
unzip -q data_en.zip && rm -rf __MACOSX data_en.zip
gzip -9 data_en/*.csv
mv data_en/*.gz .
rmdir data_en

git add ./*.gz
git commit -m "KION en dataset as csv.gz for ClickHouse url() ingestion"
git push

echo "Done. Raw URLs:"
REPO=$(git config --get remote.origin.url | sed -E 's#.*github.com[:/](.+)\.git#\1#; s#.*github.com[:/](.+)#\1#')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
for f in interactions.csv.gz users_en.csv.gz items_en.csv.gz; do
  echo "https://raw.githubusercontent.com/${REPO}/${BRANCH}/${f}"
done
