#!/bin/sh
# Container entrypoint: wait for PostgreSQL, apply migrations, then replace this
# shell with Gunicorn. `exec` makes Gunicorn the container's main process (PID 1),
# so Docker's restart policy restarts the container when Gunicorn exits.
set -eu

echo "[entrypoint] Waiting for PostgreSQL..."
python scripts/wait_for_db.py

echo "[entrypoint] Applying database migrations..."
flask --app "app:create_app()" db upgrade

echo "[entrypoint] Starting Gunicorn on 0.0.0.0:5000"
exec gunicorn \
    --bind 0.0.0.0:5000 \
    --workers "${GUNICORN_WORKERS:-2}" \
    --access-logfile - \
    --error-logfile - \
    "app:create_app()"
