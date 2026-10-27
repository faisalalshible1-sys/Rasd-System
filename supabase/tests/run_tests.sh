#!/usr/bin/env bash
# يشغّل اختبارات قاعدة البيانات على Postgres محلي: ./run_tests.sh <host-or-socket-dir> <port>
set -euo pipefail
H=${1:-localhost}; PORT=${2:-5432}; DIR=$(cd "$(dirname "$0")/.." && pwd)
P="psql -h $H -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
psql -h "$H" -p "$PORT" -U postgres -qc "drop database if exists dctest" -c "create database dctest"
$P -d dctest -f "$DIR/tests/00_supabase_shim.sql" 2>&1 | grep -v -e wal_level -e 'Set wal_level' || true
$P -d dctest -f "$DIR/migrations/20261026000001_schema.sql"
$P -d dctest -f "$DIR/migrations/20261026000002_import_projects.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261026000003_admin_email.sql"
$P -d dctest -f "$DIR/migrations/20261026000004_releases.sql"
$P -d dctest -f "$DIR/migrations/20261026000004_releases.sql"
$P -d dctest -f "$DIR/migrations/20261027000005_contract_finance.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261027000005_contract_finance.sql" >/dev/null
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/10_rules_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
