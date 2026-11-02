#!/bin/sh
# Runs once, the first time the PostgreSQL data volume is initialised.
#
# The official image creates POSTGRES_USER as a superuser. That account is an
# administrator for setup only. The application connects as APP_DB_USER, a
# non-superuser role that owns the cloudnotes databases.
set -eu

: "${APP_DB_USER:?APP_DB_USER must be set}"
: "${APP_DB_PASSWORD:?APP_DB_PASSWORD must be set}"

# Credentials are passed as psql variables, so they are never interpolated into
# shell code. :"var" quotes an identifier and :'var' quotes a literal.
psql -v ON_ERROR_STOP=1 \
     -v app_user="$APP_DB_USER" \
     -v app_pass="$APP_DB_PASSWORD" \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" <<'EOSQL'
CREATE ROLE :"app_user" WITH LOGIN PASSWORD :'app_pass'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

ALTER DATABASE cloudnotes OWNER TO :"app_user";

-- Separate database used only by the automated test suite.
CREATE DATABASE cloudnotes_test OWNER :"app_user";
EOSQL

echo "[init] Created role and databases for application user '$APP_DB_USER'."
