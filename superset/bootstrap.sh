#!/usr/bin/env bash
set -e

superset db upgrade

superset fab create-admin \
  --username "${ADMIN_USERNAME:-admin}" \
  --password "${ADMIN_PASSWORD:-admin}" \
  --firstname Admin --lastname User \
  --email admin@local || true

superset init

exec gunicorn -w 4 -k gevent --timeout 120 -b 0.0.0.0:8088 "superset.app:create_app()"