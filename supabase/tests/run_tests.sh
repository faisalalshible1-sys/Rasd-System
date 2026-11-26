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
# المستندات الفنية والتقارير اليومية للإشراف (الترحيل 20)
$P -d dctest -f "$DIR/migrations/20261114000020_documents_supervision.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261114000020_documents_supervision.sql"
$P -d dctest -f "$DIR/migrations/20261114000020_documents_supervision.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261114000020_documents_supervision.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/94_documents_supervision_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# أقسام الوحدات: الترميم والمباني التاريخية، التخطيط وضمان الجودة، السلامة المهنية، المطابقة والاستلام (الترحيل 21)
$P -d dctest -f "$DIR/migrations/20261114000021_unit_sections.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261114000021_unit_sections.sql"
$P -d dctest -f "$DIR/migrations/20261114000021_unit_sections.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261114000021_unit_sections.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/95_unit_sections_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# الشؤون الفنية ونقل السجلات، والفيديو، وقوالب الطباعة وسجل التصدير (الترحيل 22)
$P -d dctest -f "$DIR/migrations/20261116000022_print_center.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261116000022_print_center.sql"
$P -d dctest -f "$DIR/migrations/20261116000022_print_center.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261116000022_print_center.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/96_print_center_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# «منظومة رصد»: الصلاحيات الدقيقة، والرقم الإشاري الموسّع، وتخصيص الواجهة (الترحيل 23)
$P -d dctest -f "$DIR/migrations/20261119000023_rasd_grants_refs.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261119000023_rasd_grants_refs.sql"
$P -d dctest -f "$DIR/migrations/20261119000023_rasd_grants_refs.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261119000023_rasd_grants_refs.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/97_rasd_grants_refs_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# المراسلات الداخلية: الخاصة والمجموعات والقنوات والمرفقات وقفل المحادثات (الترحيل 24)
$P -d dctest -f "$DIR/migrations/20261119000024_chat.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261119000024_chat.sql"
$P -d dctest -f "$DIR/migrations/20261119000024_chat.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261119000024_chat.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/98_chat_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# مركز الأمن السيبراني الموسّع (الترحيل 25)
$P -d dctest -f "$DIR/migrations/20261119000025_security_center.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261119000025_security_center.sql"
$P -d dctest -f "$DIR/migrations/20261119000025_security_center.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261119000025_security_center.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/99_security_center_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# الكتابة عبر الدوال المدققة فقط: العقود وملاحظات الجودة وصلاحيات النماذج والاسم والإشعارات (الترحيل 26)
$P -d dctest -f "$DIR/migrations/20261121000026_audited_writes.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000026_audited_writes.sql"
$P -d dctest -f "$DIR/migrations/20261121000026_audited_writes.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000026_audited_writes.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/100_audited_writes_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# لائحة الأسعار الاسترشادية 2026 ومُعِدّ المقايسات (الترحيلان 27 و28)
$P -d dctest -f "$DIR/migrations/20261121000027_prices_boq.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000027_prices_boq.sql"
$P -d dctest -f "$DIR/migrations/20261121000028_price_list_2026.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000028_price_list_2026.sql"
$P -d dctest -f "$DIR/migrations/20261121000027_prices_boq.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000027_prices_boq.sql"
$P -d dctest -f "$DIR/migrations/20261121000028_price_list_2026.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000028_price_list_2026.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/101_prices_boq_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# بنود الجدول الزمني لكل مشروع (الترحيل 29)
$P -d dctest -f "$DIR/migrations/20261121000029_schedule_items.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000029_schedule_items.sql"
$P -d dctest -f "$DIR/migrations/20261121000029_schedule_items.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261121000029_schedule_items.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/102_schedule_items_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# إعداد البرنامج الزمني من المقايسة المعتمدة (الشؤون الفنية) ومتابعته (الإشراف) (الترحيل 30)
$P -d dctest -f "$DIR/migrations/20261122000030_plans_supervision.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000030_plans_supervision.sql"
$P -d dctest -f "$DIR/migrations/20261122000030_plans_supervision.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000030_plans_supervision.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/103_plans_supervision_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# ترجمة تنفيذ البرنامج الزمني المعتمد إلى سجل المخاطر وSWOT (الترحيل 31)
$P -d dctest -f "$DIR/migrations/20261122000031_auto_risks_swot.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000031_auto_risks_swot.sql"
$P -d dctest -f "$DIR/migrations/20261122000031_auto_risks_swot.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000031_auto_risks_swot.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/104_auto_risks_swot_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# رمز QR يفتح نسخة PDF الأصلية المحفوظة بالصلاحية (الترحيل 32)
$P -d dctest -f "$DIR/migrations/20261122000032_export_files.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000032_export_files.sql"
$P -d dctest -f "$DIR/migrations/20261122000032_export_files.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000032_export_files.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/105_export_files_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# حذف المقايسة يحذف بنودها من البرنامج الزمني والإشراف، والأفكار بالقسم والصفحة، وتخصيص الواجهة الموسّع (الترحيل 33)
$P -d dctest -f "$DIR/migrations/20261122000033_boq_cascade_ideas_layout.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000033_boq_cascade_ideas_layout.sql"
$P -d dctest -f "$DIR/migrations/20261122000033_boq_cascade_ideas_layout.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261122000033_boq_cascade_ideas_layout.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/106_boq_cascade_ideas_layout_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# عزل الأقسام: كل قسم يطّلع على عمله وحده، وأساسيات العقود للربط، والنماذج المسندة (الترحيل 34)
$P -d dctest -f "$DIR/migrations/20261123000034_section_isolation.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261123000034_section_isolation.sql"
$P -d dctest -f "$DIR/migrations/20261123000034_section_isolation.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261123000034_section_isolation.sql"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/107_section_isolation_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
# ملف العقد ومرفقاته: تصنيفات وقرار التكليف بالمهندس وأنواع الملفات حتى 50 ميغابايت، ولا تطّلع عليه الأقسام الأخرى (الترحيل 35)
$P -d dctest -f "$DIR/migrations/20261126000035_contract_files.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261126000035_contract_files.sql"
$P -d dctest -f "$DIR/migrations/20261126000035_contract_files.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261126000035_contract_files.sql"
$P -d dctest -f "$DIR/rollbacks/20261126000035_contract_files_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 35 ولا مرفقات"
$P -d dctest -f "$DIR/migrations/20261126000035_contract_files.sql" >/dev/null && echo "PASS: إعادة الترحيل 35 بعد التراجع"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/108_contract_files_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
$P -d dctest -c "insert into doc_items (kind, project_id, category, title, status) select 'attachment', id, 'other', 'مرفق يمنع التراجع', 'active' from projects limit 1" >/dev/null
if $P -d dctest -f "$DIR/rollbacks/20261126000035_contract_files_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 35 مع وجود مرفقات"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.columns where table_name = 'doc_items' and column_name = 'engineer_id'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع ووجود مرفقات، والمنظومة كما هي"
$P -d dctest -c "delete from doc_items where title = 'مرفق يمنع التراجع'" >/dev/null
