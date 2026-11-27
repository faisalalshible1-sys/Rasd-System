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
# البرنامج الزمني من المقايسة: المقايسة المستوردة ومعدلات الإنتاجية والعلاقات الأربع والإصدارات والصلاحيات الدقيقة (الترحيل 36)
$P -d dctest -f "$DIR/migrations/20261127000036_schedule_v2.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261127000036_schedule_v2.sql"
$P -d dctest -f "$DIR/migrations/20261127000036_schedule_v2.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261127000036_schedule_v2.sql"
$P -d dctest -f "$DIR/rollbacks/20261127000036_schedule_v2_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 36 ولا بيانات بعده"
$P -d dctest -f "$DIR/migrations/20261127000036_schedule_v2.sql" >/dev/null && echo "PASS: إعادة الترحيل 36 بعد التراجع"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/109_schedule_v2_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -f "$DIR/rollbacks/20261127000036_schedule_v2_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 36 مع وجود إصدارات وعلاقات"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'pm_item_links'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي المنظومة إصدارات وعلاقات، والمنظومة كما هي"
# ضمانات العقد بنسب ثابتة وتصحيحها بنسخة احتياطية، وخصم التأمينات، وأوامر التغيير ببنودها واعتمادها وسجلها، ولجنة الاستلام (الترحيل 37)
$P -d dctest -f "$DIR/migrations/20261128000037_contracts_v3.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261128000037_contracts_v3.sql"
$P -d dctest -f "$DIR/migrations/20261128000037_contracts_v3.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261128000037_contracts_v3.sql"
$P -d dctest -f "$DIR/rollbacks/20261128000037_contracts_v3_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 37 ولا بيانات بعده، والضمانات كما في النسخة الاحتياطية"
$P -d dctest -tAc "select value from app_settings where key = 'finance.guarantee_initial_rate'" | grep -qx '0.05' && echo "PASS: والنسبة الافتراضية للابتدائي عادت 5%"
$P -d dctest -f "$DIR/migrations/20261128000037_contracts_v3.sql" >/dev/null && echo "PASS: إعادة الترحيل 37 بعد التراجع"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/110_contracts_v3_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -f "$DIR/rollbacks/20261128000037_contracts_v3_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 37 مع وجود أوامر تغيير ولجان"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'contract_committees'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي المنظومة أوامر تغيير ولجان، والمنظومة كما هي"
# قسم المخازن: دور «موظف» وعزله، ونطاقات الصلاحيات، والتهيئة، والموظفون، والأصناف، والمستندات وحجزها وترحيلها وعكسها، والصلاحية (الترحيل 38)
$P -d dctest -f "$DIR/migrations/20261129000038_stores_foundation.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261129000038_stores_foundation.sql"
$P -d dctest -f "$DIR/migrations/20261129000038_stores_foundation.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261129000038_stores_foundation.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261129000038_stores_foundation_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 38 ولا بيانات في القسم، والدوال كما كانت"
$P -d dctest -tAc "select count(*) from pg_class where relname like 'st\_%' escape '\\' and relkind = 'r'" | grep -qx 0 && echo "PASS: ولا جداول للقسم بعد التراجع"
$P -d dctest -1 -f "$DIR/migrations/20261129000038_stores_foundation.sql" >/dev/null && echo "PASS: إعادة الترحيل 38 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/120_stores_foundation_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -1 -f "$DIR/rollbacks/20261129000038_stores_foundation_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 38 مع وجود بيانات في القسم"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'st_docs'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي القسم بيانات، والمنظومة كما هي"
# الأصول والعُهد والإهلاك: نطاق مسؤول الأصول، وسياسات الإهلاك، وسجل الأصول، والتسليم والإرجاع وتأكيد الموظف، والاستبعاد، والاستيراد (الترحيل 39)
$P -d dctest -f "$DIR/migrations/20261130000039_stores_assets.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261130000039_stores_assets.sql"
$P -d dctest -f "$DIR/migrations/20261130000039_stores_assets.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261130000039_stores_assets.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261130000039_stores_assets_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 39 ولا أصول، ودوال الترحيل 38 كما كانت"
$P -d dctest -tAc "select count(*) from pg_class where relname in ('st_assets', 'st_custody', 'st_asset_events', 'st_asset_policies') and relkind = 'r'" | grep -qx 0 && echo "PASS: ولا جداول للأصول بعد التراجع، وبيانات المخزون باقية"
$P -d dctest -1 -f "$DIR/migrations/20261130000039_stores_assets.sql" >/dev/null && echo "PASS: إعادة الترحيل 39 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/121_stores_assets_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -1 -f "$DIR/rollbacks/20261130000039_stores_assets_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 39 مع وجود أصول وعهد"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'st_assets'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي السجل أصول وعهد، والمنظومة كما هي"
# قسم الصيانة: البلاغات والفرز والإسناد وتنفيذ الفني وتأكيد صاحب البلاغ، وربط الأصول، والصيانة الدورية، والتنبيهات، والإعدادات (الترحيل 40)
$P -d dctest -f "$DIR/migrations/20261201000040_maintenance.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261201000040_maintenance.sql"
$P -d dctest -f "$DIR/migrations/20261201000040_maintenance.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261201000040_maintenance.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261201000040_maintenance_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 40 ولا بيانات صيانة، والدوال كما كانت"
$P -d dctest -tAc "select count(*) from pg_class where relname like 'mt\_%' escape '\\' and relkind = 'r'" | grep -qx 0 && echo "PASS: ولا جداول للصيانة بعد التراجع"
$P -d dctest -1 -f "$DIR/migrations/20261201000040_maintenance.sql" >/dev/null && echo "PASS: إعادة الترحيل 40 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/122_maintenance_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -1 -f "$DIR/rollbacks/20261201000040_maintenance_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 40 مع وجود بلاغات"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'mt_requests'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي القسم بلاغات، والمنظومة كما هي"
# قسم المشتريات: طلبات الاحتياج ومراجعة التوفر واعتماد المدير وعروض الأسعار وأمر الشراء والاستلام على دفعات (الترحيل 41)
$P -d dctest -f "$DIR/migrations/20261202000041_procurement.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261202000041_procurement.sql"
$P -d dctest -f "$DIR/migrations/20261202000041_procurement.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261202000041_procurement.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261202000041_procurement_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 41 ولا بيانات مشتريات، والدوال كما كانت"
$P -d dctest -tAc "select count(*) from pg_class where relname like 'pr\_%' escape '\\' and relkind = 'r'" | grep -qx 0 && echo "PASS: ولا جداول للمشتريات بعد التراجع"
$P -d dctest -1 -f "$DIR/migrations/20261202000041_procurement.sql" >/dev/null && echo "PASS: إعادة الترحيل 41 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/123_procurement_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -1 -f "$DIR/rollbacks/20261202000041_procurement_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 41 مع وجود طلبات"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'pr_requests'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي القسم طلبات، والمنظومة كما هي"
# الجرد الدوري بالتسوية: جلسات الجرد والعدّ والتقديم وقرار مدير المخازن وتوليد التسوية المعتمدة (الترحيل 42)
$P -d dctest -f "$DIR/migrations/20261203000042_stocktaking.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261203000042_stocktaking.sql"
$P -d dctest -f "$DIR/migrations/20261203000042_stocktaking.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261203000042_stocktaking.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261203000042_stocktaking_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 42 ولا جلسات جرد، والمخازن كما هي"
$P -d dctest -tAc "select count(*) from pg_class where relname in ('st_counts', 'st_count_lines') and relkind = 'r'" | grep -qx 0 && echo "PASS: ولا جداول للجرد بعد التراجع"
$P -d dctest -1 -f "$DIR/migrations/20261203000042_stocktaking.sql" >/dev/null && echo "PASS: إعادة الترحيل 42 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/124_stocktaking_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -1 -f "$DIR/rollbacks/20261203000042_stocktaking_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 42 مع وجود جلسات جرد"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'st_counts'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وفي القسم جلسات جرد، والمنظومة كما هي"
# خطط الاستجابة للمخاطر ومخاطر الأقسام الآلية (الترحيل 43)
$P -d dctest -f "$DIR/migrations/20261204000043_risk_actions_sections.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261204000043_risk_actions_sections.sql"
$P -d dctest -f "$DIR/migrations/20261204000043_risk_actions_sections.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261204000043_risk_actions_sections.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261204000043_risk_actions_sections_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 43 ولا إجراءات استجابة، والمخاطر كما هي"
$P -d dctest -tAc "select count(*) from pg_class where relname in ('risk_actions', 'risk_auto_runs') and relkind = 'r'" | grep -qx 0 && echo "PASS: ولا جداول لإجراءات الاستجابة بعد التراجع"
$P -d dctest -1 -f "$DIR/migrations/20261204000043_risk_actions_sections.sql" >/dev/null && echo "PASS: إعادة الترحيل 43 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/125_risk_actions_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
if $P -d dctest -1 -f "$DIR/rollbacks/20261204000043_risk_actions_sections_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 43 مع وجود إجراءات استجابة"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'risk_actions'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع وللمخاطر إجراءات، والمنظومة كما هي"
# مواقع الخريطة (الترحيل 44)
$P -d dctest -f "$DIR/migrations/20261205000044_geo_points.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261205000044_geo_points.sql"
$P -d dctest -f "$DIR/migrations/20261205000044_geo_points.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261205000044_geo_points.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261205000044_geo_points_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 44 ولا مواقع مسجَّلة"
$P -d dctest -1 -f "$DIR/migrations/20261205000044_geo_points.sql" >/dev/null && echo "PASS: إعادة الترحيل 44 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/126_geo_points_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -d dctest -qc "insert into public.geo_points (project_id, lat, lng) select id, 1, 1 from public.projects limit 1 on conflict do nothing" >/dev/null
if $P -d dctest -1 -f "$DIR/rollbacks/20261205000044_geo_points_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 44 مع وجود مواقع"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'geo_points'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع ومواقع مسجَّلة، والمنظومة كما هي"
# المعالم والمؤشرات (الترحيل 45)
$P -d dctest -f "$DIR/migrations/20261206000045_milestones_kpi.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261206000045_milestones_kpi.sql"
$P -d dctest -f "$DIR/migrations/20261206000045_milestones_kpi.sql" >/dev/null 2>&1 || $P -d dctest -f "$DIR/migrations/20261206000045_milestones_kpi.sql"
$P -d dctest -1 -f "$DIR/rollbacks/20261206000045_milestones_kpi_down.sql" >/dev/null && echo "PASS: التراجع عن الترحيل 45 ولا بيانات"
$P -d dctest -1 -f "$DIR/migrations/20261206000045_milestones_kpi.sql" >/dev/null && echo "PASS: إعادة الترحيل 45 بعد التراجع في معاملة واحدة"
psql -h "$H" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -d dctest -f "$DIR/tests/127_milestones_kpi_test.sql" 2>&1 | sed 's/^psql:[^ ]* //' | grep -v '^$'
psql -h "$H" -p "$PORT" -U postgres -d dctest -qc "insert into public.pm_milestones (project_id, title, planned_date) select id, 'باقٍ', current_date from public.projects limit 1" >/dev/null
if $P -d dctest -1 -f "$DIR/rollbacks/20261206000045_milestones_kpi_down.sql" >/dev/null 2>&1; then echo "FAIL: تراجع الترحيل 45 مع وجود معالم"; exit 1; fi
$P -d dctest -tAc "select count(*) from information_schema.tables where table_name = 'pm_milestones'" | grep -qx 1 && echo "PASS (رُفض كما يجب): التراجع ومعالم مسجَّلة، والمنظومة كما هي"
