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
$P -d dctest -f "$DIR/migrations/20261027000006_platform_v2.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261027000006_platform_v2.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261027000007_security_auditor_role.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261027000007_security_auditor_role.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261027000008_users_admin.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261027000008_users_admin.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261028000009_security_hardening.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261028000009_security_hardening.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261102000010_contracts.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261102000010_contracts.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000011_finance_security.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000011_finance_security.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000012_finance_v5.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000012_finance_v5.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000013_rls_initplan.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000013_rls_initplan.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000014_fk_indexes.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261105000014_fk_indexes.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261109000015_risks_swot.sql" >/dev/null
$P -d dctest -f "$DIR/migrations/20261109000015_risks_swot.sql" >/dev/null
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/10_rules_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/20_platform_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/30_users_admin_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/40_hardening_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/50_contracts_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/60_finance_security_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/70_finance_v5_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/80_risks_swot_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# الإصدار السابع يُطبَّق على القاعدة بعد اختبارات الإصدار السادس (كما على قاعدة فعلية فيها تعديلات المستخدمين)
$P -d dctest -f "$DIR/migrations/20261111000016_project_tracking.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261111000016_project_tracking.sql"
$P -d dctest -f "$DIR/migrations/20261111000016_project_tracking.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261111000016_project_tracking.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/90_project_tracking_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# الإصدار 2.3 / 2.1 (الترحيل 17) فوق قاعدة فيها بيانات الإصدار السابع
$P -d dctest -f "$DIR/migrations/20261112000017_registers_v23.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261112000017_registers_v23.sql"
$P -d dctest -f "$DIR/migrations/20261112000017_registers_v23.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261112000017_registers_v23.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/91_registers_v23_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# «لا ينطبق» للضمان الابتدائي ولتكليف المهندسين وتصحيحات الدمج (الترحيل 18، مستقل عن 16 و17)
$P -d dctest -f "$DIR/migrations/20261112000018_na_options.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261112000018_na_options.sql"
$P -d dctest -f "$DIR/migrations/20261112000018_na_options.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261112000018_na_options.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/92_na_options_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# الدورة المستندية للعقود – الإصدار 2 المعتمد (الترحيل 19)
$P -d dctest -f "$DIR/migrations/20261112000019_doc_cycle_v2.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261112000019_doc_cycle_v2.sql"
$P -d dctest -f "$DIR/migrations/20261112000019_doc_cycle_v2.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261112000019_doc_cycle_v2.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/93_doc_cycle_v2_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
