// =====================================================================
// مصادر التصدير: كل سجل في المنظومة بأعمدته وتصفيته ومؤشراته، ليُستخرج بأي صيغة ويُطبع بأي قالب.
// المصدر يعرف عناصره (العقود، المستخلصات، سجلات الأقسام…)، وكيف يصير العنصر صفاً، وعقده وتاريخه للتصفية.
// =====================================================================

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart';
import '../contractor_account.dart';
import '../finance_kpi.dart';
import '../models.dart';
import '../pm.dart';
import '../prices.dart';
import '../rasd.dart' show sectionDefaultNames;
import '../registers.dart';
import '../schedule.dart';
import '../assets.dart';
import '../maintenance.dart';
import '../milestones.dart';
import '../procurement.dart';
import '../stocktaking.dart';
import '../stores.dart';
import '../units.dart';
import 'model.dart';

/// ما يحدده المستخدم عند الاستخراج.
class ExportQuery {
  const ExportQuery({this.projectId, this.from, this.to, this.items, this.search = ''});

  /// عقد واحد (null: كل العقود).
  final String? projectId;
  final DateTime? from;
  final DateTime? to;

  /// العناصر المعروضة في الصفحة إن جاء الطلب منها (null: كل السجل).
  final List<Object>? items;
  final String search;
}

class ExportSource {
  const ExportSource({
    required this.id,
    required this.section,
    required this.title,
    required this.icon,
    required this.columns,
    required this.build,
    required this.count,
    this.ready = _always,
    this.byProject = true,
    this.byDate = true,
    this.dateLabel = 'التاريخ',
  });

  final String id;

  /// مفتاح القسم في الشاشة الرئيسية (cycle، risks، docs…).
  final String section;
  final String title;
  final IconData icon;
  final List<ExportColumn> columns;
  final bool Function(AppState app) ready;
  final ExportTable Function(AppState app, ExportQuery q) build;
  final int Function(AppState app) count;

  /// هل يُصفّى بالعقد وبالتاريخ؟
  final bool byProject;
  final bool byDate;
  final String dateLabel;
}

bool _always(AppState app) => true;

/// أسماء الأقسام كما في الشاشة الرئيسية (مكررة هنا حتى لا يعتمد السجل على الواجهة).
const Map<String, String> exportSectionNames = {
  'cycle': 'الدورة المستندية',
  'risks': 'المخاطر ومتابعة المشاريع',
  'swot': 'تحليل SWOT',
  'docs': 'الشؤون الفنية',
  'supervision': 'الإشراف',
  'heritage': 'الترميم والمباني التاريخية',
  'planning_qa': 'مكتب التخطيط وضمان الجودة',
  'safety': 'مكتب السلامة المهنية',
  'acceptance': 'المطابقة والاستلام',
  'print': 'الطباعة والتصدير',
  'stores': 'المخازن والأصول',
  'maintenance': 'الصيانة',
  'procurement': 'المشتريات',
};

DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);

/// يبني مصدراً من نوع عناصر [T].
ExportSource _src<T extends Object>({
  required String id,
  required String section,
  required String title,
  required IconData icon,
  required List<ExportColumn> columns,
  required List<T> Function(AppState app) items,
  required List<Object?> Function(AppState app, T x) row,
  String? Function(T x)? project,
  DateTime? Function(T x)? date,
  String dateLabel = 'التاريخ',
  List<(String, String)> Function(AppState app, List<T> list)? summary,
  bool Function(AppState app) ready = _always,
}) {
  List<T> pick(AppState app, ExportQuery q) {
    var list = q.items == null ? items(app) : q.items!.whereType<T>().toList();
    if (q.projectId != null && project != null) list = list.where((x) => project(x) == q.projectId).toList();
    if ((q.from != null || q.to != null) && date != null) {
      list = list.where((x) {
        final d = date(x);
        if (d == null) return false;
        final day = _d0(d);
        if (q.from != null && day.isBefore(_d0(q.from!))) return false;
        if (q.to != null && day.isAfter(_d0(q.to!))) return false;
        return true;
      }).toList();
    }
    return list;
  }

  return ExportSource(
    id: id,
    section: section,
    title: title,
    icon: icon,
    columns: columns,
    ready: ready,
    byProject: project != null,
    byDate: date != null,
    dateLabel: dateLabel,
    count: (app) => ready(app) ? items(app).length : 0,
    build: (app, q) {
      final list = pick(app, q);
      var rows = [for (final x in list) row(app, x)];
      final s = q.search.trim();
      if (s.isNotEmpty) {
        final n = normalizeArabic(s);
        rows = rows.where((r) => r.any((v) => v != null && normalizeArabic(v.toString()).contains(n))).toList();
      }
      final meta = <(String, String)>[
        if (q.projectId != null) ('العقد', app.project(q.projectId!)?.label ?? ''),
        if (q.from != null || q.to != null)
          (dateLabel, '${q.from == null ? '…' : dayText(q.from)} — ${q.to == null ? '…' : dayText(q.to)}'),
        if (q.items != null) ('النطاق', 'المعروض في الصفحة'),
        if (s.isNotEmpty) ('البحث', s),
        ('عدد السجلات', '${rows.length}'),
      ];
      return ExportTable(
        sourceId: id,
        title: title,
        section: exportSectionNames[section] ?? '',
        columns: columns,
        rows: rows,
        summary: summary == null || list.isEmpty ? const [] : summary(app, list),
        meta: meta,
      ).recompute();
    },
  );
}

typedef _C = ExportColumn;
String _pj(AppState app, String? id) => id == null || id.isEmpty ? '' : (app.project(id)?.label ?? '');
String _who(AppState app, String? id) => id == null ? '' : (app.people[id]?.displayName ?? '');
double? _pct(double? fraction) => fraction == null ? null : (fraction * 1000).round() / 10;
String _join(Iterable<String> l) => l.where((s) => s.trim().isNotEmpty).join('، ');

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// كل المصادر المتاحة لهذا المستخدم الآن (ما لم تُطبَّق ترحيلاته لا يظهر)، من أقسامه ووحداته وحدها (الترحيل 34).
List<ExportSource> exportSources(AppState app) => [for (final s in _all(app)) if (s.ready(app) && _visible(app, s)) s];

ExportSource? exportSource(AppState app, String id) {
  for (final s in _all(app)) {
    if (s.id == id) return s.ready(app) && _visible(app, s) ? s : null;
  }
  return null;
}

/// المصدر من قسم يراه المستخدم (وسجل الوحدة من وحدة يطّلع عليها). سجل المستخدمين لمن يدقق أصلاً.
bool _visible(AppState app, ExportSource s) {
  if (s.id == 'cycle:users') return true;
  if (!app.seesSection(s.section)) return false;
  if (s.id.startsWith('unit:')) {
    final k = unitKinds[s.id.substring(5)];
    return k == null || app.seesUnit(k.unit);
  }
  return true;
}

List<ExportSource> _all(AppState app) => [
      // ============================================================ الدورة المستندية
      _src<Project>(
        id: 'cycle:contracts',
        section: 'cycle',
        title: 'سجل العقود',
        icon: Icons.folder_open_rounded,
        items: (a) => a.projects,
        project: (p) => p.id,
        columns: const [
          _C('contract_no', 'رقم العقد'),
          _C('assign_no', 'رقم التكليف القديم', flex: 0.8, on: false),
          _C('name', 'اسم المشروع', flex: 2.2),
          _C('owner', 'مالك المشروع', flex: 1.2),
          _C('companies', 'الشركات', flex: 1.4),
          _C('department', 'القسم المشرف', flex: 1.1),
          _C('value', 'القيمة التعاقدية', type: ColType.money, flex: 1.2),
          _C('executed', 'المنفذ', type: ColType.money, flex: 1.2, on: false),
          _C('progress', 'إنجاز الدورة', type: ColType.percent, flex: 0.8),
          _C('stage', 'المرحلة الحالية', flex: 1.2),
          _C('next', 'المستند التالي', flex: 1.4, on: false),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, p) {
          final pr = a.progressOf(p);
          return [
            p.contractNo,
            p.assignNo,
            p.name,
            p.owner,
            _join(a.companiesOf(p)),
            a.departmentName(p.department),
            p.contractValue,
            p.executedValue,
            (pr.pct * 1000).round() / 10,
            stageName(pr.stage),
            pr.next?.name ?? '—',
            p.notes,
          ];
        },
        summary: (a, l) {
          final avg = l.fold<double>(0, (s, p) => s + a.progressOf(p).pct) / l.length;
          final value = l.fold<double>(0, (s, p) => s + (p.contractValue ?? 0));
          return [('العقود', '${l.length}'), ('متوسط إنجاز الدورة', '${(avg * 100).round()}%'), ('مجموع القيم التعاقدية', fmtNumber(value))];
        },
      ),
      _src<Project>(
        id: 'cycle:forms',
        section: 'cycle',
        title: 'حالة نماذج الدورة المستندية',
        icon: Icons.grid_on_rounded,
        items: (a) => a.projects,
        project: (p) => p.id,
        columns: [
          const _C('contract', 'العقد', flex: 2),
          for (final f in app.formDefs) _C('f_${f.key}', f.name, flex: 0.9),
          const _C('progress', 'الإنجاز', type: ColType.percent, flex: 0.7),
        ],
        row: (a, p) => [
          p.label,
          for (final f in a.formDefs) a.statuses[p.id]?[f.key]?.label ?? '',
          (a.progressOf(p).pct * 1000).round() / 10,
        ],
      ),
      _src<ChangeRequest>(
        id: 'cycle:requests',
        section: 'cycle',
        title: 'طلبات تغيير الحالة والاعتمادات',
        icon: Icons.fact_check_rounded,
        items: (a) => a.requests,
        project: (r) => r.projectId,
        date: (r) => r.requestedAt,
        dateLabel: 'تاريخ الطلب',
        columns: const [
          _C('date', 'تاريخ الطلب', type: ColType.date, flex: 0.9),
          _C('contract', 'العقد', flex: 2),
          _C('form', 'النموذج', flex: 1.4),
          _C('from', 'من', flex: 0.8),
          _C('to', 'إلى', flex: 0.8),
          _C('by', 'مقدّم الطلب', flex: 1.1),
          _C('state', 'القرار', flex: 0.8),
          _C('decided_by', 'صاحب القرار', flex: 1.1, on: false),
          _C('note', 'الملاحظة', type: ColType.long),
        ],
        row: (a, r) => [
          r.requestedAt,
          _pj(a, r.projectId),
          a.formDefs.where((f) => f.key == r.formKey).map((f) => f.name).firstOrNull ?? r.formKey,
          r.fromStatus.label,
          r.toStatus.label,
          _who(a, r.requestedBy),
          r.state.label,
          _who(a, r.decidedBy),
          [r.note, r.decisionNote].where((s) => s.trim().isNotEmpty).join(' — '),
        ],
      ),
      _src<Project>(
        id: 'cycle:finance',
        section: 'cycle',
        title: 'الموقف المالي للعقود',
        icon: Icons.account_balance_rounded,
        items: (a) => a.projects,
        project: (p) => p.id,
        columns: const [
          _C('contract', 'العقد', flex: 2.2),
          _C('value', 'القيمة التعاقدية', type: ColType.money),
          _C('variations', 'صافي أوامر التغيير', type: ColType.money),
          _C('executed', 'المنفذ', type: ColType.money),
          _C('gross', 'إجمالي المستخلصات', type: ColType.money),
          _C('net', 'صافي المستخلصات', type: ColType.money),
          _C('paid', 'المدفوع', type: ColType.money),
          _C('outstanding', 'المستحق غير المدفوع', type: ColType.money),
          _C('retention', 'التأمينات المحتجزة', type: ColType.money, on: false),
          _C('extracts', 'عدد المستخلصات', type: ColType.number, flex: 0.6, on: false),
          _C('paid_pct', 'نسبة المدفوع من القيمة', type: ColType.percent, flex: 0.7, on: false, formula: '{paid}/{value}*100'),
        ],
        row: (a, p) => [
          p.label,
          p.contractValue,
          p.variationsNet,
          p.executedValue,
          p.extractsGross,
          p.extractsNet,
          p.paidTotal,
          p.outstanding,
          p.retentionHeld,
          p.extractsCount,
          null,
        ],
        summary: (a, l) => [
          ('مجموع القيم', fmtNumber(l.fold<double>(0, (s, p) => s + (p.contractValue ?? 0)))),
          ('المدفوع', fmtNumber(l.fold<double>(0, (s, p) => s + p.paidTotal))),
          ('المستحق', fmtNumber(l.fold<double>(0, (s, p) => s + p.outstanding))),
        ],
      ),
      _src<ContractExtract>(
        id: 'cycle:extracts',
        section: 'cycle',
        title: 'سجل المستخلصات',
        icon: Icons.receipt_long_rounded,
        ready: (a) => a.v4Ready,
        items: (a) => a.extracts,
        project: (x) => x.projectId,
        date: (x) => x.submittedOn,
        dateLabel: 'تاريخ التقديم',
        columns: const [
          _C('contract', 'العقد', flex: 2),
          _C('seq', 'رقم المستخلص', type: ColType.number, flex: 0.6),
          _C('ref', 'المرجع', flex: 0.8),
          _C('from', 'من', type: ColType.date, flex: 0.9, on: false),
          _C('to', 'إلى', type: ColType.date, flex: 0.9, on: false),
          _C('submitted', 'تاريخ التقديم', type: ColType.date, flex: 0.9),
          _C('gross', 'الإجمالي', type: ColType.money),
          _C('retention', 'التأمين المحتجز', type: ColType.money, on: false),
          _C('advance', 'استرداد المقدمة', type: ColType.money, on: false),
          _C('penalties', 'الغرامات', type: ColType.money, on: false),
          _C('taxes', 'الضرائب', type: ColType.money, on: false),
          _C('net', 'الصافي', type: ColType.money),
          _C('paid', 'المدفوع', type: ColType.money),
          _C('unpaid', 'المتبقي من الصافي', type: ColType.money, on: false, formula: 'max({net}-{paid},0)'),
          _C('status', 'الحالة', flex: 0.9),
          _C('referral', 'رقم الإحالة', flex: 0.8, on: false),
        ],
        row: (a, x) => [
          _pj(a, x.projectId),
          x.seq,
          x.refNo,
          x.periodFrom,
          x.periodTo,
          x.submittedOn,
          x.gross,
          x.retention,
          x.advanceRecovery,
          x.penalties,
          x.taxes,
          x.net,
          x.paidAmount,
          null,
          x.statusLabel,
          x.referralNo,
        ],
        summary: (a, l) => [
          ('المستخلصات', '${l.length}'),
          ('الصافي', fmtNumber(l.fold<double>(0, (s, x) => s + x.net))),
          ('غير المدفوع', fmtNumber(l.fold<double>(0, (s, x) => s + x.unpaid))),
        ],
      ),
      _src<FinanceMonth>(
        id: 'cycle:monthly',
        section: 'cycle',
        title: 'التقرير المالي الشهري',
        icon: Icons.calendar_month_rounded,
        ready: (a) => a.v4Ready,
        items: (a) {
          final ids = {for (final p in a.scoped) p.id};
          return monthlyFinance(a.extracts.where((x) => ids.contains(x.projectId)), a.paymentsOf, DateTime.now());
        },
        columns: const [
          _C('month', 'الشهر', flex: 1.2),
          _C('count', 'عدد المستخلصات المعتمدة', type: ColType.number, flex: 0.8),
          _C('approved', 'صافي المعتمد', type: ColType.money),
          _C('referred', 'صافي المحال للصرف', type: ColType.money),
          _C('paid', 'المدفوع', type: ColType.money),
          _C('gap', 'الفرق (المعتمد − المدفوع)', type: ColType.money),
        ],
        row: (a, m) => ['${m.month.year}/${m.month.month.toString().padLeft(2, '0')}', m.approvedCount, m.approvedNet, m.referredNet, m.paid, m.gap],
        summary: (a, l) => [
          ('المعتمد', fmtNumber(l.fold<double>(0, (s, m) => s + m.approvedNet))),
          ('المدفوع', fmtNumber(l.fold<double>(0, (s, m) => s + m.paid))),
        ],
      ),
      _src<ContractorAccount>(
        id: 'cycle:contractors',
        section: 'cycle',
        title: 'كشف حساب المقاولين',
        icon: Icons.groups_2_outlined,
        ready: (a) => a.v4Ready,
        items: (a) => contractorAccounts(a.scoped, a.extracts, DateTime.now()),
        columns: const [
          _C('name', 'المقاول', flex: 2),
          _C('projects', 'عدد العقود', type: ColType.number, flex: 0.6),
          _C('contract', 'قيمة العقود', type: ColType.money),
          _C('variations', 'صافي أوامر التغيير', type: ColType.money, on: false),
          _C('adjusted', 'القيمة بعد التغيير', type: ColType.money),
          _C('executed', 'المنفذ', type: ColType.money),
          _C('paid', 'المدفوع', type: ColType.money),
          _C('unpaid', 'مستحق غير مدفوع', type: ColType.money),
          _C('remaining', 'المتبقي للدفع', type: ColType.money, on: false),
          _C('retention', 'التأمين المحتجز', type: ColType.money, on: false),
          _C('a30', 'حتى 30 يوماً', type: ColType.money, on: false),
          _C('a60', '31–60 يوماً', type: ColType.money, on: false),
          _C('a90', '61–90 يوماً', type: ColType.money, on: false),
          _C('a90p', 'أكثر من 90 يوماً', type: ColType.money, on: false),
          _C('aNone', 'بلا تاريخ اعتماد', type: ColType.money, on: false),
        ],
        row: (a, c) => [
          c.name,
          c.projects.length,
          c.contract,
          c.variationsNet,
          c.adjusted,
          c.executed,
          c.paid,
          c.unpaid,
          c.remainingToPay,
          c.retention,
          ...c.aging,
        ],
        summary: (a, l) => [
          ('المقاولون', '${l.length}'),
          ('المدفوع', fmtNumber(l.fold<double>(0, (s, c) => s + c.paid))),
          ('مستحق غير مدفوع', fmtNumber(l.fold<double>(0, (s, c) => s + c.unpaid))),
        ],
      ),
      _src<ExtractPayment>(
        id: 'cycle:payments',
        section: 'cycle',
        title: 'سجل الدفعات',
        icon: Icons.payments_rounded,
        ready: (a) => a.v5Ready,
        items: (a) => a.payments,
        project: (x) => x.projectId,
        date: (x) => x.paidOn,
        dateLabel: 'تاريخ الدفع',
        columns: const [
          _C('date', 'تاريخ الدفع', type: ColType.date, flex: 0.9),
          _C('contract', 'العقد', flex: 2),
          _C('extract', 'المستخلص', flex: 0.8),
          _C('amount', 'المبلغ', type: ColType.money),
          _C('method', 'الطريقة', flex: 0.9),
          _C('ref', 'المرجع', flex: 0.9),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) {
          final e = a.extracts.where((e) => e.id == x.extractId).firstOrNull;
          return [x.paidOn, _pj(a, x.projectId), e == null ? '' : 'رقم ${e.seq}', x.amount, x.methodLabel, x.refNo, x.notes];
        },
      ),
      _src<ContractVariation>(
        id: 'cycle:variations',
        section: 'cycle',
        title: 'أوامر التغيير',
        icon: Icons.change_circle_rounded,
        ready: (a) => a.v4Ready,
        items: (a) => a.variations,
        project: (x) => x.projectId,
        date: (x) => x.approvedOn,
        dateLabel: 'تاريخ الاعتماد',
        columns: const [
          _C('contract', 'العقد', flex: 2),
          _C('ref', 'المرجع', flex: 0.8),
          _C('title', 'البيان', flex: 2),
          _C('kind', 'النوع', flex: 0.7),
          _C('amount', 'القيمة', type: ColType.money),
          _C('added', 'الأعمال المضافة', type: ColType.money, on: false),
          _C('deducted', 'الأعمال الملغاة أو المخفضة', type: ColType.money, on: false),
          _C('status', 'الحالة', flex: 0.7),
          _C('date', 'تاريخ الاعتماد', type: ColType.date, flex: 0.9),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) => [_pj(a, x.projectId), x.refNo, x.title, x.isAdd ? 'إضافة' : 'خصم', x.isAdd ? x.amount : -x.amount,
          x.addedValue, x.deductedValue, x.statusLabel, x.approvedOn, x.notes],
      ),
      _src<ContractWork>(
        id: 'cycle:works',
        section: 'cycle',
        title: 'أعمال العقود',
        icon: Icons.construction_rounded,
        ready: (a) => a.v3Ready,
        items: (a) => a.works,
        project: (x) => x.projectId,
        columns: const [
          _C('contract', 'العقد', flex: 2),
          _C('title', 'العمل', flex: 2),
          _C('company', 'الشركة', flex: 1.3),
          _C('ref', 'الرقم المرجعي', flex: 0.9),
          _C('value', 'القيمة التعاقدية', type: ColType.money),
          _C('executed', 'المنفذ', type: ColType.money),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) => [_pj(a, x.projectId), x.title, x.company, x.refNo, x.contractValue, x.executedValue, x.notes],
      ),
      _src<ContractEngineer>(
        id: 'cycle:engineers',
        section: 'cycle',
        title: 'المهندسون والتكليفات',
        icon: Icons.engineering_rounded,
        ready: (a) => a.v3Ready,
        items: (a) => a.engineers,
        project: (x) => x.projectId,
        date: (x) => x.assignedOn,
        dateLabel: 'تاريخ التكليف',
        columns: const [
          _C('contract', 'العقد', flex: 2),
          _C('kind', 'الصفة', flex: 1),
          _C('name', 'الاسم', flex: 1.4),
          _C('assign', 'رقم التكليف', flex: 0.9),
          _C('date', 'تاريخ التكليف', type: ColType.date, flex: 0.9),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) => [_pj(a, x.projectId), engineerKindLabel(x.kind), x.name, x.assignNo, x.assignedOn, x.notes],
      ),
      _src<Idea>(
        id: 'cycle:ideas',
        section: 'cycle',
        title: 'الأفكار والتطوير',
        icon: Icons.lightbulb_rounded,
        ready: (a) => a.v2Ready,
        items: (a) => a.ideas,
        date: (x) => x.createdAt,
        columns: const [
          _C('date', 'التاريخ', type: ColType.date, flex: 0.9),
          _C('title', 'الفكرة', flex: 2),
          _C('category', 'التصنيف', flex: 0.9),
          _C('priority', 'الأولوية', flex: 0.7),
          _C('status', 'الحالة', flex: 0.8),
          _C('place', 'المكان', flex: 1.3),
          _C('by', 'المقترِح', flex: 1.1),
          _C('body', 'التفاصيل', type: ColType.long, on: false),
          _C('response', 'الرد', type: ColType.long, on: false),
        ],
        row: (a, x) => [
          x.createdAt,
          x.title,
          ideaCategoryLabels[x.category] ?? x.category,
          ideaPriorityLabels[x.priority] ?? x.priority,
          ideaStatusLabels[x.status] ?? x.status,
          x.section == null
              ? 'عامة للمنظومة'
              : [
                  (a.layout.sections[x.section]?.name ?? '').trim().isNotEmpty
                      ? a.layout.sections[x.section]!.name.trim()
                      : (sectionDefaultNames[x.section] ?? ''),
                  if (x.pageLabel.isNotEmpty) x.pageLabel,
                ].join(' · '),
          _who(a, x.createdBy),
          x.body,
          x.response,
        ],
      ),
      _src<Profile>(
        id: 'cycle:users',
        section: 'cycle',
        title: 'مستخدمو المنظومة',
        icon: Icons.people_alt_rounded,
        ready: (a) => a.isDirector || a.isAuditor,
        items: (a) => a.people.values.toList()..sort((x, y) => x.displayName.compareTo(y.displayName)),
        columns: const [
          _C('name', 'الاسم', flex: 1.5),
          _C('email', 'البريد', flex: 1.8),
          _C('role', 'الدور', flex: 1.1),
          _C('department', 'القسم', flex: 1.1),
          _C('unit', 'الوحدة', flex: 1.1),
          _C('active', 'الحالة', flex: 0.6),
        ],
        row: (a, p) => [
          p.displayName,
          p.email,
          p.role?.label ?? 'بانتظار التفعيل',
          a.departmentName(p.department),
          p.unit == null ? '' : '${unitNames[p.unit] ?? p.unit}${p.unitHead ? ' (رئيس)' : ''}',
          p.active ? 'مفعّل' : 'موقوف',
        ],
      ),

      // ============================================================ المخاطر ومتابعة المشاريع
      _src<Risk>(
        id: 'risks:register',
        section: 'risks',
        title: 'سجل المخاطر',
        icon: Icons.list_alt_rounded,
        ready: (a) => a.v6Ready,
        items: (a) => a.risks,
        project: (r) => r.projectId,
        date: (r) => r.registeredOn,
        dateLabel: 'تاريخ التسجيل',
        columns: const [
          _C('code', 'الرمز', flex: 0.6),
          _C('description', 'وصف الخطر', type: ColType.long, flex: 1.6),
          _C('project', 'المشروع', flex: 1.4),
          _C('category', 'التصنيف', flex: 0.9),
          _C('probability', 'الاحتمال', type: ColType.number, flex: 0.5),
          _C('impact', 'الأثر', type: ColType.number, flex: 0.5),
          _C('score', 'الدرجة', type: ColType.number, flex: 0.5, formula: '{probability}*{impact}'),
          _C('level', 'المستوى', flex: 0.8),
          _C('owner', 'المالك', flex: 1),
          _C('response', 'الاستجابة', flex: 0.8, on: false),
          _C('mitigation', 'إجراءات المعالجة', type: ColType.long, on: false),
          _C('next', 'المراجعة القادمة', type: ColType.date, flex: 0.9),
          _C('status', 'الحالة', flex: 0.8),
          _C('origin', 'المصدر', flex: 0.9, on: false),
        ],
        row: (a, r) => [
          r.code,
          r.description,
          r.projectId == null ? r.projectGroup : _pj(a, r.projectId),
          r.category,
          r.probability,
          r.impact,
          r.score,
          a.riskConfig.level(r.score)?.name ?? '',
          r.owner,
          r.responseLabel,
          r.mitigation,
          r.nextReview,
          r.statusLabel,
          r.section != null ? 'تلقائي: ${riskSectionLabels[r.section]}' : (r.isAuto ? 'تلقائي: البرنامج الزمني' : (r.isOffice ? 'المكتب' : 'مشروع')),
        ],
        summary: (a, l) => [
          ('المخاطر', '${l.length}'),
          ('مرتفعة نشطة', '${l.where((r) => !r.isClosed && a.riskConfig.isHigh(r.score)).length}'),
          ('مغلقة', '${l.where((r) => r.isClosed).length}'),
        ],
      ),
      _src<RiskReview>(
        id: 'risks:reviews',
        section: 'risks',
        title: 'مراجعات المخاطر',
        icon: Icons.rate_review_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.riskReviews,
        date: (r) => r.reviewedOn,
        dateLabel: 'تاريخ المراجعة',
        columns: const [
          _C('date', 'تاريخ المراجعة', type: ColType.date, flex: 0.9),
          _C('risk', 'الخطر', flex: 1.8),
          _C('probability', 'الاحتمال', type: ColType.number, flex: 0.5),
          _C('impact', 'الأثر', type: ColType.number, flex: 0.5),
          _C('progress', 'التقدم', type: ColType.percent, flex: 0.6),
          _C('reviewer', 'المراجع', flex: 1),
          _C('actions', 'الإجراءات المنفذة', type: ColType.long),
        ],
        row: (a, r) {
          final risk = a.risks.where((x) => x.id == r.riskId).firstOrNull;
          return [r.reviewedOn, risk == null ? '' : '${risk.code} · ${risk.description}', r.probability, r.impact, _pct(r.progress), r.reviewer, r.actionsDone];
        },
      ),
      _src<RiskAction>(
        id: 'risks:actions',
        section: 'risks',
        title: 'إجراءات الاستجابة للمخاطر',
        icon: Icons.checklist_rounded,
        ready: (a) => a.v27Ready,
        items: (a) => a.riskActions,
        date: (r) => r.dueDate,
        dateLabel: 'موعد التنفيذ',
        columns: const [
          _C('risk', 'الخطر', flex: 1.8),
          _C('title', 'الإجراء', type: ColType.long, flex: 1.8),
          _C('owner', 'المسؤول', flex: 1),
          _C('due', 'الموعد', type: ColType.date, flex: 0.9),
          _C('status', 'الحالة', flex: 0.7),
          _C('done', 'تاريخ الإنجاز', type: ColType.date, flex: 0.9, on: false),
          _C('note', 'ملاحظة', type: ColType.long, on: false),
        ],
        row: (a, r) {
          final risk = a.risks.where((x) => x.id == r.riskId).firstOrNull;
          return [
            risk == null ? '' : '${risk.code} · ${risk.description}',
            r.title,
            r.owner,
            r.dueDate,
            riskActionStatusLabels[r.status] ?? r.status,
            r.doneOn,
            r.note,
          ];
        },
        summary: (a, l) => [
          ('الإجراءات', '${l.length}'),
          ('مفتوحة', '${l.where((r) => r.isOpen).length}'),
          ('متأخرة', '${l.where((r) => r.isLate(DateTime.now())).length}'),
        ],
      ),
      _src<PmMilestone>(
        id: 'risks:milestones',
        section: 'risks',
        title: 'معالم المشاريع',
        icon: Icons.flag_rounded,
        ready: (a) => a.v29Ready,
        items: (a) => a.milestones,
        project: (m) => m.projectId,
        date: (m) => m.planned,
        dateLabel: 'التاريخ المخطط',
        columns: const [
          _C('project', 'المشروع', flex: 2),
          _C('title', 'المعلم', type: ColType.long, flex: 1.8),
          _C('planned', 'المخطط', type: ColType.date, flex: 0.9),
          _C('forecast', 'المتوقع', type: ColType.date, flex: 0.9),
          _C('actual', 'الفعلي', type: ColType.date, flex: 0.9),
          _C('status', 'الحالة', flex: 0.8),
          _C('late', 'أيام التأخر', type: ColType.number, flex: 0.7),
          _C('note', 'ملاحظة', type: ColType.long, on: false),
        ],
        row: (a, m) => [
          a.pm.track(m.projectId)?.displayName ?? a.projects.where((p) => p.id == m.projectId).firstOrNull?.name ?? '',
          m.title,
          m.planned,
          m.forecast,
          m.actual,
          m.isDone ? 'منجز' : (m.isCancelled ? 'ملغى' : (m.isOverdue(DateTime.now()) ? 'متأخر' : 'قادم')),
          m.lateDays(DateTime.now()),
          m.note,
        ],
        summary: (a, l) => [
          ('المعالم', '${l.length}'),
          ('منجزة', '${l.where((m) => m.isDone).length}'),
          ('متأخرة', '${l.where((m) => m.isOverdue(DateTime.now())).length}'),
        ],
      ),
      _src<ProjectTrack>(
        id: 'risks:projects',
        section: 'risks',
        title: 'سجل المشاريع والأداء الزمني',
        icon: Icons.view_timeline_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.pm.tracks.values.toList(),
        project: (t) => t.project.id,
        columns: const [
          _C('project', 'المشروع', flex: 2),
          _C('status', 'الحالة التشغيلية', flex: 0.9),
          _C('start', 'البداية', type: ColType.date, flex: 0.9),
          _C('end', 'النهاية المعدلة', type: ColType.date, flex: 0.9),
          _C('planned', 'المخطط', type: ColType.percent, flex: 0.6),
          _C('actual', 'الفعلي', type: ColType.percent, flex: 0.6),
          _C('spi', 'SPI', type: ColType.number, flex: 0.5),
          _C('perf', 'الأداء', flex: 0.9),
          _C('delay', 'أيام التأخير', type: ColType.number, flex: 0.6, on: false),
          _C('risks', 'مخاطر نشطة', type: ColType.number, flex: 0.6, on: false),
          _C('issues', 'مشاكل مفتوحة', type: ColType.number, flex: 0.6, on: false),
        ],
        row: (a, t) => [
          t.displayName,
          opStatusLabels[t.opStatus] ?? t.opStatus,
          t.start,
          t.revisedEnd,
          _pct(t.planned),
          _pct(t.actual),
          t.spi == null ? null : (t.spi! * 100).round() / 100,
          perfLabels[t.perf] ?? t.perf,
          t.delayDays,
          t.activeRisks,
          t.openIssues,
        ],
        summary: (a, l) => [
          ('المشاريع', '${l.length}'),
          ('متأخرة', '${l.where((t) => t.isLate).length}'),
          ('منجزة', '${l.where((t) => t.isDone).length}'),
        ],
      ),
      _src<ItemCalc>(
        id: 'risks:schedule',
        section: 'risks',
        title: 'بنود العقود والبرامج الزمنية والانحرافات',
        icon: Icons.date_range_rounded,
        ready: (a) => a.v14Ready,
        items: (a) => [for (final t in a.schedule.tracks.values) ...t.calcs],
        project: (c) => c.item.projectId,
        date: (c) => c.item.plannedEnd,
        dateLabel: 'النهاية المخططة',
        columns: const [
          _C('project', 'المشروع', flex: 1.6),
          _C('code', 'رقم البند', flex: 0.5),
          _C('title', 'البند', flex: 2),
          _C('unit', 'الوحدة', flex: 0.5, on: false),
          _C('qty', 'الكمية', type: ColType.number, flex: 0.6, on: false, sum: false),
          _C('start', 'البداية المخططة', type: ColType.date, flex: 0.9),
          _C('end', 'النهاية المخططة', type: ColType.date, flex: 0.9),
          _C('duration', 'المدة (يوم)', type: ColType.number, flex: 0.6, sum: false),
          _C('weight', 'الوزن', type: ColType.number, flex: 0.6, on: false),
          _C('planned', 'المخطط', type: ColType.percent, flex: 0.6),
          _C('actual', 'الفعلي', type: ColType.percent, flex: 0.6),
          _C('variance', 'الانحراف (نقطة)', type: ColType.number, flex: 0.7, formula: '{actual}-{planned}', sum: false),
          _C('days', 'الانحراف بالأيام', type: ColType.number, flex: 0.7, sum: false),
          _C('status', 'الحالة', flex: 0.8),
          _C('astart', 'البداية الفعلية', type: ColType.date, flex: 0.9, on: false),
          _C('aend', 'النهاية الفعلية', type: ColType.date, flex: 0.9, on: false),
          _C('forecast', 'الإنهاء المتوقع', type: ColType.date, flex: 0.9, on: false),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, c) => [
          _pj(a, c.item.projectId),
          c.item.code,
          c.item.title,
          c.item.unit,
          c.item.qty,
          c.item.plannedStart,
          c.item.plannedEnd,
          c.duration,
          c.item.weight,
          (c.planned * 10).round() / 10,
          (c.actual * 10).round() / 10,
          (c.variance * 10).round() / 10,
          c.daysVariance.round(),
          perfLabels[c.status] ?? c.status,
          c.item.actualStart,
          c.item.actualEnd,
          c.forecastEnd,
          c.item.notes,
        ],
        summary: (a, l) => [
          ('البنود', '${l.length}'),
          ('متأخرة', '${l.where((c) => c.isLate).length}'),
          ('منجزة', '${l.where((c) => c.status == 'done').length}'),
        ],
      ),
      _src<PmProgress>(
        id: 'risks:progress',
        section: 'risks',
        title: 'التقدم الدوري',
        icon: Icons.show_chart_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.measurements,
        project: (x) => x.projectId,
        date: (x) => x.measuredOn,
        dateLabel: 'تاريخ القياس',
        columns: const [
          _C('date', 'تاريخ القياس', type: ColType.date, flex: 0.9),
          _C('project', 'المشروع', flex: 2),
          _C('planned', 'المخطط', type: ColType.percent, flex: 0.6),
          _C('actual', 'الفعلي', type: ColType.percent, flex: 0.6),
          _C('deviation', 'الانحراف', type: ColType.percent, flex: 0.6, formula: '{actual}-{planned}'),
          _C('works', 'الأعمال المنفذة', type: ColType.long),
          _C('obstacles', 'المعوقات', type: ColType.long, on: false),
          _C('by', 'المُعِد', flex: 0.9, on: false),
        ],
        row: (a, x) => [x.measuredOn, _pj(a, x.projectId), _pct(x.planned), _pct(x.actual), _pct(x.deviation), x.works, x.obstacles, x.preparedBy],
      ),
      _src<PmIssue>(
        id: 'risks:issues',
        section: 'risks',
        title: 'سجل المشاكل',
        icon: Icons.report_problem_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.pmIssues,
        project: (x) => x.projectId,
        date: (x) => x.detectedOn,
        dateLabel: 'تاريخ الرصد',
        columns: const [
          _C('code', 'الرمز', flex: 0.6),
          _C('date', 'تاريخ الرصد', type: ColType.date, flex: 0.9),
          _C('project', 'المشروع', flex: 1.6),
          _C('description', 'الوصف', type: ColType.long, flex: 1.6),
          _C('priority', 'الأولوية', flex: 0.6),
          _C('party', 'الجهة', flex: 0.8),
          _C('action', 'الإجراء', type: ColType.long, on: false),
          _C('target', 'الموعد المستهدف', type: ColType.date, flex: 0.9),
          _C('status', 'الحالة', flex: 0.7),
        ],
        row: (a, x) => [
          x.code,
          x.detectedOn,
          _pj(a, x.projectId),
          x.description,
          pmPriorityLabels[x.priority] ?? x.priority,
          pmPartyLabels[x.party] ?? x.party,
          x.action,
          x.targetDate,
          issueStatusLabels[x.status] ?? x.status,
        ],
      ),
      _src<PmDelay>(
        id: 'risks:delays',
        section: 'risks',
        title: 'التأخيرات وأسبابها',
        icon: Icons.hourglass_bottom_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.pmDelays,
        project: (x) => x.projectId,
        date: (x) => x.startDate,
        dateLabel: 'تاريخ البداية',
        columns: const [
          _C('code', 'الرمز', flex: 0.6),
          _C('project', 'المشروع', flex: 1.6),
          _C('description', 'الوصف', type: ColType.long, flex: 1.6),
          _C('cause', 'السبب', flex: 1),
          _C('party', 'الجهة', flex: 0.8),
          _C('class', 'التصنيف', flex: 0.9),
          _C('start', 'من', type: ColType.date, flex: 0.9),
          _C('end', 'إلى', type: ColType.date, flex: 0.9),
          _C('days', 'الأيام', type: ColType.number, flex: 0.5),
          _C('eot_req', 'التمديد المطلوب', type: ColType.number, flex: 0.6, on: false),
          _C('eot_ok', 'التمديد المعتمد', type: ColType.number, flex: 0.6),
        ],
        row: (a, x) => [
          x.code,
          _pj(a, x.projectId),
          x.description,
          x.cause,
          pmPartyLabels[x.party] ?? x.party,
          delayClassLabels[x.delayClass] ?? x.delayClass,
          x.startDate,
          x.endDate,
          x.days(_today()),
          x.eotRequested,
          x.eotApproved,
        ],
      ),
      _src<PmChange>(
        id: 'risks:changes',
        section: 'risks',
        title: 'سجل التغييرات',
        icon: Icons.change_circle_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.pmChanges,
        project: (x) => x.projectId,
        date: (x) => x.submittedOn,
        dateLabel: 'تاريخ التقديم',
        columns: const [
          _C('code', 'الرمز', flex: 0.6),
          _C('date', 'تاريخ التقديم', type: ColType.date, flex: 0.9),
          _C('project', 'المشروع', flex: 1.6),
          _C('description', 'الوصف', type: ColType.long, flex: 1.6),
          _C('type', 'النوع', flex: 0.9),
          _C('source', 'المصدر', flex: 0.8, on: false),
          _C('estimate', 'التكلفة التقديرية', type: ColType.money),
          _C('approved', 'التكلفة المعتمدة', type: ColType.money),
          _C('time', 'المدة المعتمدة (يوم)', type: ColType.number, flex: 0.6, on: false),
          _C('status', 'الحالة', flex: 0.7),
        ],
        row: (a, x) => [
          x.code,
          x.submittedOn,
          _pj(a, x.projectId),
          x.description,
          x.changeType,
          changeSourceLabels[x.source] ?? x.source,
          x.costEstimate,
          x.costApproved,
          x.timeApproved,
          changeStatusLabels[x.status] ?? x.status,
        ],
      ),
      _src<PmLesson>(
        id: 'risks:lessons',
        section: 'risks',
        title: 'الدروس المستفادة',
        icon: Icons.school_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.pmLessons,
        project: (x) => x.projectId,
        date: (x) => x.documentedOn,
        dateLabel: 'تاريخ التوثيق',
        columns: const [
          _C('code', 'الرمز', flex: 0.6),
          _C('date', 'التاريخ', type: ColType.date, flex: 0.9),
          _C('project', 'المشروع', flex: 1.4),
          _C('type', 'النوع', flex: 1),
          _C('situation', 'الموقف', type: ColType.long),
          _C('lesson', 'الدرس', type: ColType.long),
          _C('apply', 'آلية التطبيق', type: ColType.long, on: false),
          _C('status', 'الحالة', flex: 0.7),
        ],
        row: (a, x) => [
          x.code,
          x.documentedOn,
          _pj(a, x.projectId),
          lessonTypeLabels[x.lessonType] ?? x.lessonType,
          x.situation,
          x.lesson,
          x.applyMechanism,
          lessonStatusLabels[x.status] ?? x.status,
        ],
      ),
      _src<PmEvaluation>(
        id: 'risks:evaluations',
        section: 'risks',
        title: 'تقييم الشركات المنفذة',
        icon: Icons.engineering_rounded,
        ready: (a) => a.v7Ready,
        items: (a) => a.pmEvaluations,
        project: (x) => x.projectId,
        date: (x) => x.evaluatedOn,
        dateLabel: 'تاريخ التقييم',
        columns: const [
          _C('date', 'تاريخ التقييم', type: ColType.date, flex: 0.9),
          _C('company', 'الشركة', flex: 1.4),
          _C('project', 'المشروع', flex: 1.6),
          _C('average', 'متوسط الدرجات (من 5)', type: ColType.number, flex: 0.8),
          _C('evaluator', 'المقيِّم', flex: 1),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) => [
          x.evaluatedOn,
          x.company,
          _pj(a, x.projectId),
          x.average == null ? null : (x.average! * 100).round() / 100,
          x.evaluator,
          x.notes,
        ],
      ),

      // ============================================================ تحليل SWOT
      _src<SwotFactor>(
        id: 'swot:factors',
        section: 'swot',
        title: 'سجل عوامل SWOT',
        icon: Icons.format_list_numbered_rounded,
        ready: (a) => a.v6Ready,
        items: (a) => a.swotFactors,
        columns: const [
          _C('code', 'الرمز', flex: 0.5),
          _C('kind', 'النوع', flex: 0.6),
          _C('factor', 'العامل', type: ColType.long, flex: 1.8),
          _C('department', 'القسم', flex: 1),
          _C('importance', 'الأهمية', type: ColType.number, flex: 0.5),
          _C('urgency', 'الإلحاح', type: ColType.number, flex: 0.5),
          _C('rating', 'التقدير', type: ColType.number, flex: 0.5),
          _C('evidence', 'الدليل', type: ColType.long, on: false),
        ],
        row: (a, x) => [x.code, swotKindLabels[x.kind] ?? x.kind, x.factor, x.department, x.importance, x.urgency, x.rating, x.evidence],
      ),
      _src<SwotStrategy>(
        id: 'swot:strategies',
        section: 'swot',
        title: 'استراتيجيات TOWS',
        icon: Icons.alt_route_rounded,
        ready: (a) => a.v6Ready,
        items: (a) => a.swotStrategies,
        columns: const [
          _C('code', 'الرمز', flex: 0.5),
          _C('kind', 'النوع', flex: 0.8),
          _C('strategy', 'الاستراتيجية', type: ColType.long, flex: 2),
          _C('factors', 'العوامل', flex: 1),
          _C('priority', 'الأولوية', flex: 0.6),
          _C('lead', 'القسم القائد', flex: 1),
        ],
        row: (a, x) => [
          x.code,
          strategyKindLabels[x.kind] ?? x.kind,
          x.strategy,
          [...x.internal, ...x.external].join('، '),
          swotPriorityLabels[x.priority] ?? x.priority,
          x.leadDepartment,
        ],
      ),
      _src<SwotAction>(
        id: 'swot:plan',
        section: 'swot',
        title: 'خطة تنفيذ SWOT',
        icon: Icons.event_note_rounded,
        ready: (a) => a.v6Ready,
        items: (a) => a.swotActions,
        date: (x) => x.startDate,
        dateLabel: 'تاريخ البدء',
        columns: const [
          _C('code', 'الرمز', flex: 0.5),
          _C('action', 'الإجراء', type: ColType.long, flex: 2),
          _C('strategy', 'الاستراتيجية', flex: 0.6),
          _C('department', 'القسم', flex: 1),
          _C('owner', 'المسؤول', flex: 1),
          _C('priority', 'الأولوية', flex: 0.6),
          _C('start', 'البدء', type: ColType.date, flex: 0.9),
          _C('months', 'المدة (شهر)', type: ColType.number, flex: 0.5),
          _C('progress', 'الإنجاز', type: ColType.percent, flex: 0.6),
          _C('status', 'الحالة', flex: 0.8),
          _C('kpi', 'مؤشر القياس', type: ColType.long, on: false),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) => [
          x.code,
          x.action,
          x.strategyCode ?? '',
          x.department,
          x.owner,
          swotPriorityLabels[x.priority] ?? x.priority,
          x.startDate,
          x.durationMonths,
          _pct(x.progress),
          x.statusLabel,
          x.kpi,
          x.notes,
        ],
      ),

      // ============================================================ الشؤون الفنية والإشراف
      for (final kind in const ['boq', 'letter', 'design'])
        _src<DocItem>(
          id: 'docs:$kind',
          section: 'docs',
          title: docKindLabels[kind]!,
          icon: switch (kind) { 'boq' => Icons.request_quote_rounded, 'letter' => Icons.mark_email_read_rounded, _ => Icons.architecture_rounded },
          ready: (a) => a.v8Ready,
          items: (a) => a.docs.ofKind(kind),
          project: (x) => x.projectId,
          date: (x) => x.docDate,
          columns: [
            const _C('ref', 'الرقم', flex: 0.8),
            const _C('date', 'التاريخ', type: ColType.date, flex: 0.9),
            const _C('title', 'العنوان', flex: 2),
            const _C('project', 'العقد', flex: 1.6),
            if (kind == 'letter') const _C('direction', 'الاتجاه', flex: 0.6),
            const _C('category', 'التصنيف', flex: 0.9),
            const _C('party', 'الجهة', flex: 1),
            if (kind == 'boq') const _C('amount', 'القيمة', type: ColType.money),
            if (kind == 'letter') const _C('due', 'موعد الرد', type: ColType.date, flex: 0.9),
            const _C('status', 'الحالة', flex: 0.8),
            const _C('revisions', 'الإصدارات', type: ColType.number, flex: 0.5, on: false),
            const _C('files', 'الملفات', type: ColType.number, flex: 0.5, on: false),
            const _C('notes', 'ملاحظات', type: ColType.long, on: false),
          ],
          row: (a, x) => [
            x.refNo,
            x.docDate,
            x.title,
            _pj(a, x.projectId),
            if (kind == 'letter') letterDirectionLabels[x.direction] ?? '',
            x.categoryLabel,
            x.party,
            if (kind == 'boq') x.amount,
            if (kind == 'letter') x.dueDate,
            x.statusLabel,
            a.docs.revisionsOf(x.id).length,
            a.docs.currentFiles(x.id).length,
            x.notes,
          ],
        ),
      for (final withPrices in const [true, false])
        _src<BoqLine>(
          id: withPrices ? 'docs:boq_sheet' : 'docs:boq_sheet_qty',
          section: 'docs',
          title: withPrices ? 'مقايسة من لائحة الأسعار' : 'مقايسة كميات (دون أسعار)',
          icon: Icons.calculate_rounded,
          ready: (a) => a.v14Ready,
          items: (a) => [for (final s in a.boqSheets) ...s.lines],
          project: (x) => x.projectId,
          columns: [
            const _C('code', 'رقم البند', flex: 0.6),
            const _C('desc', 'وصف البند', type: ColType.long, flex: 2.4),
            const _C('unit', 'الوحدة', flex: 0.5),
            const _C('qty', 'الكمية', type: ColType.number, flex: 0.7, sum: false),
            _C('price', 'سعر الوحدة', type: ColType.money, flex: 0.8, on: withPrices, sum: false),
            _C('total', 'الإجمالي', type: ColType.money, flex: 0.9, on: withPrices, formula: '{qty}*{price}'),
            const _C('notes', 'ملاحظات', type: ColType.long, flex: 1),
            const _C('sheet', 'المقايسة', flex: 1, on: false),
          ],
          row: (a, x) => [x.code, x.desc, x.unit, x.qty, x.price, x.total, x.notes, a.boqSheet(x.sheetId)?.title ?? ''],
          summary: (a, l) => [
            ('البنود', '${l.length}'),
            if (withPrices) ('الإجمالي', fmtMoney(l.fold<double>(0, (s, x) => s + (x.total ?? 0)))),
          ],
        ),
      _src<PriceItem>(
        id: 'docs:prices',
        section: 'docs',
        title: 'لائحة الأسعار الاسترشادية',
        icon: Icons.price_change_rounded,
        ready: (a) => a.v14Ready,
        items: (a) => a.priceResults,
        columns: const [
          _C('chapter', 'الفصل', flex: 1, on: false),
          _C('code', 'رقم البند', flex: 0.6),
          _C('desc', 'وصف البند', type: ColType.long, flex: 2.6),
          _C('unit', 'الوحدة', flex: 0.5),
          _C('price', 'سعر الوحدة', type: ColType.money, flex: 0.8, sum: false),
          _C('section', 'القسم', flex: 1, on: false),
          _C('group', 'مجموعة الأعمال', flex: 1, on: false),
        ],
        row: (a, x) => [
          a.activePriceList?.chapterName(x.chapter) ?? x.chapter,
          x.code,
          x.isItem ? x.fullDesc : x.description,
          x.unit,
          x.price,
          x.section,
          x.group,
        ],
      ),
      _src<SiteReport>(
        id: 'supervision:reports',
        section: 'supervision',
        title: 'التقارير اليومية',
        icon: Icons.assignment_rounded,
        ready: (a) => a.v8Ready,
        items: (a) => a.docs.reports,
        project: (x) => x.projectId,
        date: (x) => x.reportDate,
        dateLabel: 'تاريخ التقرير',
        columns: const [
          _C('date', 'التاريخ', type: ColType.date, flex: 0.9),
          _C('project', 'العقد', flex: 1.6),
          _C('workers', 'العمالة', type: ColType.number, flex: 0.5),
          _C('progress', 'الإنجاز', type: ColType.percent, flex: 0.6),
          _C('works', 'الأعمال المنفذة', type: ColType.long, flex: 1.8),
          _C('issues', 'المعوقات', type: ColType.long),
          _C('safety', 'السلامة', type: ColType.long, on: false),
          _C('equipment', 'المعدات', type: ColType.long, on: false),
          _C('weather', 'الطقس', flex: 0.6, on: false),
          _C('by', 'المُعِد', flex: 0.9),
          _C('reviewed', 'اطلاع المدير', flex: 0.7),
          _C('photos', 'الصور', type: ColType.number, flex: 0.5, on: false),
        ],
        row: (a, x) => [
          x.reportDate,
          _pj(a, x.projectId),
          x.workers,
          x.progressPct,
          x.worksDone,
          x.issues,
          x.safety,
          x.equipment,
          x.weather,
          _who(a, x.createdBy),
          x.reviewed ? 'اطّلع' : 'لم يطّلع بعد',
          a.docs.filesOfReport(x.id).where((f) => f.isImage).length,
        ],
        summary: (a, l) => [
          ('التقارير', '${l.length}'),
          ('بمعوقات', '${l.where((r) => r.hasIssues).length}'),
          ('بانتظار الاطلاع', '${l.where((r) => !r.reviewed).length}'),
        ],
      ),

      // ============================================================ سجلات الأقسام (13 نوعاً)
      for (final k in unitKinds.values) _unitSource(k),

      // ============================================================ المخازن والأصول (الترحيل 38)
      _src<StItem>(
        id: 'stores:items',
        section: 'stores',
        title: 'الأصناف وأرصدتها',
        icon: Icons.inventory_2_rounded,
        ready: (a) => a.v22Ready,
        items: (a) => a.stores.items,
        columns: const [
          _C('code', 'الرمز', flex: 0.8),
          _C('name', 'الصنف', flex: 2),
          _C('category', 'التصنيف', flex: 1.1),
          _C('unit', 'الوحدة', flex: 0.6),
          _C('on_hand', 'الفعلي', type: ColType.number, flex: 0.7, sum: false),
          _C('reserved', 'المحجوز', type: ColType.number, flex: 0.7, sum: false, on: false),
          _C('available', 'المتاح', type: ColType.number, flex: 0.7, sum: false),
          _C('min', 'الحد الأدنى', type: ColType.number, flex: 0.7, sum: false),
          _C('reorder', 'نقطة الطلب', type: ColType.number, flex: 0.7, sum: false),
          _C('critical', 'الاحتياطي الحرج', type: ColType.number, flex: 0.7, sum: false, on: false),
          _C('level', 'المستوى', flex: 0.9),
          _C('barcode', 'الباركود', flex: 0.9, on: false),
          _C('expiry', 'الصلاحية', flex: 0.6, on: false),
          _C('active', 'الحالة', flex: 0.6, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          return [
            x.code,
            x.name,
            s.category(x.categoryId)?.name ?? '',
            s.unitName(x.baseUnitId),
            s.onHand(x.id),
            s.reserved(x.id),
            s.available(x.id),
            x.minQty,
            x.reorderQty,
            x.criticalQty,
            stockLevelLabels[s.levelOf(x)] ?? '',
            x.barcode,
            x.tracksExpiry ? 'تُتتبع' : '',
            x.active ? 'نشط' : 'موقوف',
          ];
        },
        summary: (a, l) => [
          ('الأصناف', '${l.length}'),
          ('تحتاج توريداً', '${l.where((x) => const {'out', 'min', 'reorder'}.contains(a.stores.levelOf(x))).length}'),
        ],
      ),
      _src<StStock>(
        id: 'stores:balances',
        section: 'stores',
        title: 'أرصدة المخازن',
        icon: Icons.stacked_bar_chart_rounded,
        ready: (a) => a.v22Ready,
        items: (a) => [for (final st in a.stores.stock) if (st.onHand > 0 || st.reserved > 0) st],
        columns: const [
          _C('warehouse', 'المخزن', flex: 1.2),
          _C('code', 'الرمز', flex: 0.8),
          _C('item', 'الصنف', flex: 2),
          _C('unit', 'الوحدة', flex: 0.6),
          _C('on_hand', 'الفعلي', type: ColType.number, flex: 0.7, sum: false),
          _C('reserved', 'المحجوز', type: ColType.number, flex: 0.7, sum: false),
          _C('available', 'المتاح', type: ColType.number, flex: 0.7, sum: false),
          _C('level', 'المستوى', flex: 0.9),
        ],
        row: (a, x) {
          final s = a.stores;
          final it = s.item(x.itemId);
          return [
            s.warehouseName(x.warehouseId),
            it?.code ?? '',
            it?.name ?? '',
            s.unitName(it?.baseUnitId),
            x.onHand,
            x.reserved,
            x.available,
            it == null ? '' : stockLevelLabels[s.levelOf(it, warehouseId: x.warehouseId)] ?? '',
          ];
        },
        summary: (a, l) => [('الأرصدة', '${l.length}'), ('المخازن', '${l.map((x) => x.warehouseId).toSet().length}')],
      ),
      _src<StDoc>(
        id: 'stores:docs',
        section: 'stores',
        title: 'مستندات المخزون',
        icon: Icons.receipt_long_rounded,
        ready: (a) => a.v22Ready,
        items: (a) => a.stores.docs,
        date: (x) => x.docDate,
        dateLabel: 'تاريخ المستند',
        columns: const [
          _C('no', 'الرقم', flex: 0.9),
          _C('kind', 'النوع', flex: 0.8),
          _C('status', 'الحالة', flex: 0.9),
          _C('date', 'التاريخ', type: ColType.date, flex: 0.8),
          _C('warehouse', 'المخزن', flex: 1.1),
          _C('to', 'إلى المخزن', flex: 1.1, on: false),
          _C('party', 'المستلم أو المورد', flex: 1.5),
          _C('ref', 'رقم الفاتورة أو المحضر', flex: 0.9, on: false),
          _C('lines', 'البنود', type: ColType.number, flex: 0.5),
          _C('by', 'أنشأه', flex: 0.9, on: false),
          _C('approved', 'اعتمده', flex: 0.9, on: false),
          _C('posted', 'تاريخ الترحيل', type: ColType.date, flex: 0.8, on: false),
          _C('note', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          return [
            x.docNo,
            x.isReversal ? 'عكس ${x.kindLabel}' : x.kindLabel,
            x.statusLabel,
            x.docDate,
            s.warehouseName(x.warehouseId),
            s.warehouseName(x.toWarehouseId),
            x.hasRecipient ? s.recipientOf(x) : x.party,
            x.refNo,
            s.linesOf(x.id).length,
            _who(a, x.createdBy),
            _who(a, x.approvedBy),
            x.postedAt,
            x.note,
          ];
        },
        summary: (a, l) => [
          ('المستندات', '${l.length}'),
          ('مرحَّلة', '${l.where((d) => d.isPosted).length}'),
          ('مفتوحة', '${l.where((d) => d.isOpen).length}'),
        ],
      ),
      _src<StDocLine>(
        id: 'stores:lines',
        section: 'stores',
        title: 'بنود مستند مخزون',
        icon: Icons.list_alt_rounded,
        ready: (a) => a.v22Ready,
        items: (a) => a.stores.lines,
        columns: const [
          _C('doc', 'المستند', flex: 0.9),
          _C('no', 'م', type: ColType.number, flex: 0.3, sum: false),
          _C('code', 'الرمز', flex: 0.8),
          _C('item', 'الصنف', flex: 2),
          _C('qty', 'الكمية', type: ColType.number, flex: 0.6, sum: false),
          _C('unit', 'الوحدة', flex: 0.6),
          _C('base', 'بالوحدة الأساسية', type: ColType.number, flex: 0.7, sum: false, on: false),
          _C('expiry', 'تاريخ الانتهاء', type: ColType.date, flex: 0.8, on: false),
          _C('batch', 'الدفعة', flex: 0.6, on: false),
          _C('note', 'ملاحظة', type: ColType.long, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          final it = s.item(x.itemId);
          return [
            s.doc(x.docId)?.docNo ?? '',
            x.lineNo,
            it?.code ?? '',
            it?.name ?? '',
            x.qty,
            s.unitName(x.unitId),
            x.baseQty,
            x.expiryDate,
            x.batchNo,
            x.note,
          ];
        },
        summary: (a, l) {
          final d = l.isEmpty ? null : a.stores.doc(l.first.docId);
          if (d == null || l.any((x) => x.docId != d.id)) return [('البنود', '${l.length}')];
          final s = a.stores;
          return [
            ('المستند', '${d.title} ${d.docNo}'),
            ('المخزن', d.kind == 'transfer' ? '${s.warehouseName(d.warehouseId)} ← ${s.warehouseName(d.toWarehouseId)}' : s.warehouseName(d.warehouseId)),
            if (d.hasRecipient) (d.kind == 'issue' ? 'المصروف له' : 'المُرجِع', s.recipientOf(d)),
            if (d.party.isNotEmpty) ('المورد أو الجهة', d.party),
            ('الحالة', d.statusLabel),
          ];
        },
      ),
      _src<StMove>(
        id: 'stores:moves',
        section: 'stores',
        title: 'بطاقة حركة صنف',
        icon: Icons.swap_vert_rounded,
        ready: (a) => a.v22Ready,
        items: (a) => a.storeMoves,
        date: (x) => x.at,
        columns: const [
          _C('date', 'التاريخ', type: ColType.date, flex: 0.8),
          _C('doc', 'المستند', flex: 0.9),
          _C('kind', 'النوع', flex: 0.8),
          _C('warehouse', 'المخزن', flex: 1.1),
          _C('item', 'الصنف', flex: 1.6),
          _C('qty', 'الكمية', type: ColType.number, flex: 0.6, sum: false),
          _C('balance', 'الرصيد بعده', type: ColType.number, flex: 0.7, sum: false),
          _C('expiry', 'تاريخ الانتهاء', type: ColType.date, flex: 0.8, on: false),
          _C('batch', 'الدفعة', flex: 0.6, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          final d = s.doc(x.docId);
          return [x.at, d?.docNo ?? '', d?.kindLabel ?? '', s.warehouseName(x.warehouseId), s.itemName(x.itemId), x.qty, x.balanceAfter, x.expiryDate, x.batchNo];
        },
      ),
      _src<StEmployee>(
        id: 'stores:employees',
        section: 'stores',
        title: 'سجل الموظفين',
        icon: Icons.badge_rounded,
        ready: (a) => a.v22Ready && a.storesStaff,
        items: (a) => a.stores.employees,
        columns: const [
          _C('no', 'الرقم الوظيفي', flex: 0.8),
          _C('name', 'الاسم', flex: 1.8),
          _C('department', 'الإدارة', flex: 1.5),
          _C('title', 'الوظيفة', flex: 1),
          _C('phone', 'الهاتف', flex: 0.9, on: false),
          _C('email', 'البريد', flex: 1.2, on: false),
          _C('account', 'الحساب', flex: 1, on: false),
          _C('active', 'الحالة', flex: 0.6),
        ],
        row: (a, x) => [
          x.empNo,
          x.fullName,
          a.stores.departmentPath(x.departmentId),
          x.jobTitle,
          x.phone,
          x.email,
          _who(a, x.profileId),
          x.active ? 'نشط' : 'موقوف',
        ],
        summary: (a, l) => [('الموظفون', '${l.length}'), ('بحساب', '${l.where((e) => e.profileId != null).length}')],
      ),

      // ============================================================ الأصول والعهد (الترحيل 39)
      _src<StAsset>(
        id: 'stores:assets',
        section: 'stores',
        title: 'سجل الأصول',
        icon: Icons.chair_alt_rounded,
        ready: (a) => a.storesAssetsSees,
        items: (a) => a.storeAssets.active,
        columns: const [
          _C('tag', 'رقم الأصل', flex: 0.9),
          _C('name', 'الوصف', flex: 1.8),
          _C('category', 'التصنيف', flex: 1),
          _C('maker', 'المصنع والموديل', flex: 1.2, on: false),
          _C('serial', 'الرقم التسلسلي', flex: 1, on: false),
          _C('status', 'الوضع', flex: 0.8),
          _C('condition', 'الحالة', flex: 0.6, on: false),
          _C('place', 'المكان', flex: 1.4),
          _C('holder', 'في عهدة', flex: 1.2),
          _C('purchase', 'تاريخ الشراء', type: ColType.date, flex: 0.8, on: false),
          _C('cost', 'التكلفة', type: ColType.money, flex: 0.9),
          _C('accumulated', 'الإهلاك المتراكم', type: ColType.money, flex: 0.9, on: false),
          _C('book', 'القيمة الدفترية', type: ColType.money, flex: 0.9),
          _C('warranty', 'نهاية الضمان', type: ColType.date, flex: 0.8, on: false),
          _C('supplier', 'المورد', flex: 1, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          final today = DateTime.now();
          return [
            x.tag,
            x.name,
            s.category(x.categoryId)?.name ?? '',
            [x.manufacturer, x.model].where((v) => v.isNotEmpty).join(' '),
            x.serialNo,
            x.statusLabel,
            x.conditionLabel,
            x.warehouseId != null ? 'مخزن ${s.warehouseName(x.warehouseId)}' : s.locationPath(x.locationId),
            s.employee(x.employeeId)?.fullName ?? '',
            x.purchaseDate,
            x.cost,
            x.accumulated(today),
            x.bookValue(today),
            x.warrantyUntil,
            x.supplier,
          ];
        },
        summary: (a, l) {
          final t = a.storeAssets.totals(DateTime.now(), of: l);
          return [
            ('الأصول', '${l.length}'),
            ('في العهدة', '${l.where((x) => x.inCustody).length}'),
            ('التكلفة', fmtMoney(t.cost)),
            ('القيمة الدفترية', fmtMoney(t.book)),
          ];
        },
      ),
      _src<StCustody>(
        id: 'stores:custody',
        section: 'stores',
        title: 'محاضر العهد',
        icon: Icons.assignment_ind_rounded,
        ready: (a) => a.storesAssetsSees,
        items: (a) => a.storeAssets.custody,
        columns: const [
          _C('no', 'المحضر', flex: 0.9),
          _C('employee', 'الموظف', flex: 1.5),
          _C('emp_no', 'الرقم الوظيفي', flex: 0.8, on: false),
          _C('department', 'الإدارة', flex: 1.2),
          _C('tag', 'رقم الأصل', flex: 0.9),
          _C('asset', 'الأصل', flex: 1.6),
          _C('handed', 'التسليم', type: ColType.date, flex: 0.8),
          _C('cond_out', 'الحالة عند التسليم', flex: 0.7, on: false),
          _C('accessories', 'الملحقات', flex: 1.1, on: false),
          _C('confirmed', 'تأكيد الموظف', flex: 0.7),
          _C('returned', 'الإرجاع', type: ColType.date, flex: 0.8),
          _C('cond_in', 'الحالة عند الإرجاع', flex: 0.7, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          final e = s.employee(x.employeeId);
          final asset = a.storeAssets.asset(x.assetId);
          return [
            x.custodyNo,
            e?.fullName ?? '',
            e?.empNo ?? '',
            s.departmentPath(x.departmentId),
            asset?.tag ?? '',
            asset?.name ?? '',
            x.handedOn,
            assetConditionLabels[x.conditionOut] ?? '',
            x.accessoriesOut,
            x.confirmedAt == null ? 'لم يؤكد' : 'أكّد',
            x.returnedOn,
            assetConditionLabels[x.conditionIn] ?? '',
          ];
        },
        summary: (a, l) => [('المحاضر', '${l.length}'), ('القائمة', '${l.where((x) => x.isOpen).length}')],
      ),

      // ============================================================ الجرد والتقارير (الترحيل 42)
      _src<MovementRow>(
        id: 'stores:movement',
        section: 'stores',
        title: 'حركة الأصناف والاستهلاك (آخر 90 يوماً)',
        icon: Icons.swap_vert_rounded,
        ready: (a) => a.v22Ready,
        items: (a) {
          final now = DateTime.now();
          return a.stores.movement(now.subtract(const Duration(days: 89)), now);
        },
        columns: const [
          _C('code', 'الرمز', flex: 0.8),
          _C('item', 'الصنف', flex: 2),
          _C('unit', 'الوحدة', flex: 0.6),
          _C('received', 'وارد', type: ColType.number, flex: 0.7, sum: false),
          _C('issued', 'صادر', type: ColType.number, flex: 0.7, sum: false),
          _C('consumed', 'صافي الاستهلاك', type: ColType.number, flex: 0.8, sum: false),
          _C('on_hand', 'الرصيد الآن', type: ColType.number, flex: 0.8, sum: false),
        ],
        row: (a, x) => [
          x.item.code,
          x.item.name,
          a.stores.unitName(x.item.baseUnitId),
          x.received,
          x.issued,
          x.consumed,
          a.stores.onHand(x.item.id),
        ],
        summary: (a, l) => [('الأصناف', '${l.length}')],
      ),
      _src<StCount>(
        id: 'stores:counts',
        section: 'stores',
        title: 'جلسات الجرد',
        icon: Icons.fact_check_rounded,
        ready: (a) => a.v26Ready,
        items: (a) => a.stocktake.counts,
        date: (x) => x.createdAt,
        dateLabel: 'تاريخ البدء',
        columns: const [
          _C('no', 'الجلسة', flex: 0.9),
          _C('warehouse', 'المخزن', flex: 1.2),
          _C('category', 'التصنيف', flex: 1, on: false),
          _C('status', 'الحالة', flex: 0.9),
          _C('started', 'البدء', type: ColType.date, flex: 0.8),
          _C('decided', 'القرار', type: ColType.date, flex: 0.8),
          _C('lines', 'البنود', type: ColType.number, flex: 0.5),
          _C('variance', 'بنود بفرق', type: ColType.number, flex: 0.6),
          _C('doc', 'مستند التسوية', flex: 0.9),
          _C('by', 'أنشأها', flex: 0.9, on: false),
        ],
        row: (a, x) {
          final s = a.stores;
          final sum = a.stocktake.summary(x, (id) => s.onHand(id, warehouseId: x.warehouseId));
          return [
            x.countNo,
            s.warehouseName(x.warehouseId),
            s.category(x.categoryId)?.name ?? '',
            x.statusLabel,
            x.createdAt,
            x.decidedAt,
            sum.total,
            sum.withVariance,
            s.doc(x.adjustDocId)?.docNo ?? '',
            _who(a, x.createdBy),
          ];
        },
        summary: (a, l) => [('الجلسات', '${l.length}'), ('المغلقة', '${l.where((x) => x.isClosed).length}')],
      ),

      // ============================================================ الصيانة (الترحيل 40)
      _src<MtRequest>(
        id: 'maintenance:requests',
        section: 'maintenance',
        title: 'بلاغات الصيانة',
        icon: Icons.build_circle_rounded,
        ready: (a) => a.v24Ready && a.mtSeesAll,
        items: (a) => a.maint.requests,
        columns: const [
          _C('no', 'رقم البلاغ', flex: 0.9),
          _C('title', 'العنوان', flex: 1.8),
          _C('category', 'التصنيف', flex: 0.9),
          _C('priority', 'الأولوية', flex: 0.7),
          _C('status', 'الحالة', flex: 0.8),
          _C('source', 'المصدر', flex: 0.7, on: false),
          _C('asset', 'الأصل', flex: 1.3),
          _C('place', 'الموقع', flex: 1.3),
          _C('reporter', 'صاحب البلاغ', flex: 1.2),
          _C('executor', 'المنفّذ', flex: 1.2),
          _C('reported', 'تاريخ الرفع', type: ColType.date, flex: 0.9),
          _C('due', 'الموعد المستهدف', type: ColType.date, flex: 0.9),
          _C('done', 'تاريخ الإنجاز', type: ColType.date, flex: 0.9, on: false),
          _C('rating', 'التقييم', flex: 0.5, on: false),
        ],
        row: (a, x) => [
          x.reqNo,
          x.title,
          mtCategoryLabels[x.category] ?? x.category,
          mtPriorityLabels[x.priority] ?? x.priority,
          mtStatusLabels[x.status] ?? x.status,
          x.isPlan ? 'صيانة دورية' : 'بلاغ',
          x.assetText,
          a.maint.locationPath(x.locationId),
          x.reporterName,
          x.executor,
          x.reportedAt,
          x.dueAt,
          x.doneAt,
          x.rating == null ? '' : '${x.rating}/5',
        ],
        summary: (a, l) {
          final now = DateTime.now();
          return [('البلاغات', '${l.length}'), ('المفتوحة', '${l.where((x) => x.isOpen).length}'), ('المتأخرة', '${l.where((x) => x.isOverdue(now)).length}')];
        },
      ),
      _src<MtPlan>(
        id: 'maintenance:plans',
        section: 'maintenance',
        title: 'خطط الصيانة الدورية',
        icon: Icons.event_repeat_rounded,
        ready: (a) => a.v24Ready && a.mtStaff,
        items: (a) => a.maint.plans,
        columns: const [
          _C('no', 'رقم الخطة', flex: 0.8),
          _C('title', 'الخطة', flex: 1.8),
          _C('category', 'التصنيف', flex: 0.9),
          _C('every', 'التكرار', flex: 0.8),
          _C('asset', 'الأصل', flex: 1.2),
          _C('next', 'الموعد القادم', type: ColType.date, flex: 0.9),
          _C('last', 'آخر تنفيذ', type: ColType.date, flex: 0.9),
          _C('active', 'الحالة', flex: 0.6),
        ],
        row: (a, x) => [
          x.planNo,
          x.title,
          mtCategoryLabels[x.category] ?? x.category,
          x.intervalText,
          x.assetTag.isEmpty ? '' : '${x.assetTag} — ${x.assetName}',
          x.nextDue,
          x.lastDone,
          x.active ? 'نشطة' : 'موقوفة',
        ],
        summary: (a, l) => [('الخطط', '${l.length}'), ('النشطة', '${l.where((x) => x.active).length}')],
      ),

      // ============================================================ المشتريات (الترحيل 41)
      _src<PrRequest>(
        id: 'procurement:requests',
        section: 'procurement',
        title: 'طلبات الاحتياج',
        icon: Icons.shopping_cart_checkout_rounded,
        ready: (a) => a.v25Ready && a.prStaff,
        items: (a) => a.proc.requests.where((r) => r.status != 'draft').toList(),
        columns: const [
          _C('no', 'رقم الطلب', flex: 0.9),
          _C('title', 'العنوان', flex: 1.8),
          _C('requester', 'مقدّم الطلب', flex: 1.2),
          _C('priority', 'الأولوية', flex: 0.7),
          _C('status', 'الحالة', flex: 1.1),
          _C('lines', 'البنود', type: ColType.number, flex: 0.5),
          _C('tobuy', 'بنود للشراء', type: ColType.number, flex: 0.6),
          _C('needed', 'مطلوب قبل', type: ColType.date, flex: 0.9),
          _C('submitted', 'تاريخ التقديم', type: ColType.date, flex: 0.9),
          _C('decided', 'تاريخ القرار', type: ColType.date, flex: 0.9, on: false),
          _C('order', 'أمر الشراء', flex: 0.9),
        ],
        row: (a, x) {
          final ls = a.proc.linesOf(x.id);
          final o = a.proc.orderOfRequest(x.id);
          return [
            x.reqNo,
            x.title,
            x.requesterName,
            prPriorityLabels[x.priority] ?? x.priority,
            prStatusLabels[x.status] ?? x.status,
            ls.length,
            ls.where((l) => l.toBuy > 0).length,
            x.neededBy,
            x.submittedAt,
            x.decidedAt,
            o == null || o.status == 'cancelled' ? '' : o.poNo,
          ];
        },
        summary: (a, l) => [('الطلبات', '${l.length}'), ('الجارية', '${l.where((x) => x.isOpen).length}'), ('المستلَمة', '${l.where((x) => x.status == 'received').length}')],
      ),
      _src<PrOrder>(
        id: 'procurement:orders',
        section: 'procurement',
        title: 'أوامر الشراء',
        icon: Icons.receipt_long_rounded,
        ready: (a) => a.v25Ready && a.prStaff,
        items: (a) => a.proc.orders,
        columns: const [
          _C('no', 'رقم الأمر', flex: 0.9),
          _C('request', 'الطلب', flex: 0.9),
          _C('supplier', 'المورّد', flex: 1.5),
          _C('status', 'الحالة', flex: 0.8),
          _C('total', 'الإجمالي', type: ColType.money, flex: 0.9),
          _C('expected', 'التوريد المتوقع', type: ColType.date, flex: 0.9),
          _C('issued', 'تاريخ الإصدار', type: ColType.date, flex: 0.9),
          _C('waiver', 'استثناء العروض', flex: 1.4, on: false),
        ],
        row: (a, x) => [
          x.poNo,
          a.proc.request(x.requestId)?.reqNo ?? '',
          a.proc.supplier(x.supplierId)?.name ?? '',
          prOrderStatusLabels[x.status] ?? x.status,
          x.total,
          x.expectedDate,
          x.issuedAt,
          x.waiverNote,
        ],
        summary: (a, l) => [
          ('الأوامر', '${l.length}'),
          ('القائمة', '${l.where((x) => x.isLive).length}'),
          ('إجمالي القائمة', fmtMoney(l.where((x) => x.isLive).fold<double>(0, (t, x) => t + x.total))),
        ],
      ),

      // ============================================================ الوسائط والملفات
      _src<DocFile>(
        id: 'media:files',
        section: 'print',
        title: 'سجل الملفات المرفوعة',
        icon: Icons.perm_media_rounded,
        ready: (a) => a.v8Ready,
        items: (a) => a.docs.files,
        project: (f) => mediaProjectOf(app, f),
        date: (f) => f.createdAt,
        dateLabel: 'تاريخ الرفع',
        columns: const [
          _C('date', 'تاريخ الرفع', type: ColType.date, flex: 0.9),
          _C('name', 'اسم الملف', flex: 1.8),
          _C('type', 'النوع', flex: 0.6),
          _C('size', 'الحجم (ك.ب)', type: ColType.number, flex: 0.6),
          _C('where', 'المصدر', flex: 1.8),
          _C('project', 'العقد', flex: 1.4),
          _C('by', 'رفعه', flex: 1),
        ],
        row: (a, f) => [
          f.createdAt,
          f.name,
          mediaTypeLabel(f),
          (f.sizeBytes / 1024).round(),
          mediaOwnerLabel(a, f),
          _pj(a, mediaProjectOf(a, f)),
          _who(a, f.createdBy),
        ],
        summary: (a, l) => [
          ('الملفات', '${l.length}'),
          ('الصور', '${l.where((f) => f.isImage).length}'),
          ('الفيديو', '${l.where((f) => f.isVideo).length}'),
        ],
      ),
    ];

ExportSource _unitSource(UnitKind k) {
  final section = switch (unitSectionOf[k.unit]) { 'technical' => 'docs', final s? => s, null => 'docs' };
  final parent = k.parent == null ? null : unitKinds[k.parent!];
  return _src<UnitRecord>(
    id: 'unit:${k.key}',
    section: section,
    title: k.label,
    icon: Icons.folder_special_rounded,
    ready: (a) => a.v9Ready,
    items: (a) => a.units.ofKind(k.key),
    project: (r) => r.projectId,
    date: (r) => r.recDate,
    dateLabel: k.dateLabel,
    columns: [
      _C('ref', k.refLabel, flex: 0.8),
      _C('title', k.titleLabel, flex: 2),
      _C('date', k.dateLabel, type: ColType.date, flex: 0.9),
      const _C('project', 'العقد', flex: 1.5),
      if (parent != null) _C('parent', parent.single, flex: 1.4),
      if (k.hasLevels) _C('level', k.levelLabel, flex: 0.9),
      const _C('status', 'الحالة', flex: 0.9),
      if (k.dueLabel != null) _C('due', k.dueLabel!, type: ColType.date, flex: 0.9),
      if (k.progress) const _C('progress', 'نسبة الإنجاز', type: ColType.percent, flex: 0.6),
      if (k.ownerLabel != null) _C('owner', k.ownerLabel!, flex: 1.1),
      for (final f in k.fields)
        _C('f_${f.key}', f.label, type: f.type == UnitFieldType.long ? ColType.long : (f.type == UnitFieldType.number ? ColType.number : ColType.text), on: f.type != UnitFieldType.long),
      const _C('closed', 'تاريخ الإغلاق', type: ColType.date, flex: 0.9, on: false),
      const _C('notes', 'ملاحظات', type: ColType.long, on: false),
    ],
    row: (a, r) {
      final p = r.parentId == null ? null : a.units.byId(r.parentId!);
      return [
        r.refNo,
        r.title,
        r.recDate,
        _pj(a, r.projectId),
        if (parent != null) p == null ? '' : [p.refNo, p.title].where((s) => s.isNotEmpty).join(' · '),
        if (k.hasLevels) k.levelLabelOf(r.level),
        k.statusLabel(r.status),
        if (k.dueLabel != null) r.dueDate,
        if (k.progress) r.progress,
        if (k.ownerLabel != null) r.ownerText,
        for (final f in k.fields)
          () {
            final v = r.data[f.key];
            if (v == null) return null;
            if (f.type == UnitFieldType.number) return v is num ? v : num.tryParse(v.toString());
            return v.toString();
          }(),
        r.closedAt,
        r.notes,
      ];
    },
    summary: (a, l) {
      final today = _today();
      return [
        (k.label, '${l.length}'),
        ('مفتوحة', '${l.where((r) => !r.isClosed).length}'),
        if (k.dueLabel != null) ('متأخرة', '${l.where((r) => r.overdue(today)).length}') else ('مغلقة', '${l.where((r) => r.isClosed).length}'),
      ];
    },
  );
}

// ---------------------------------------------------------------------
// الوسائط: مصدر الملف (مستند، تقرير يومي، سجل قسم) وعقده
// ---------------------------------------------------------------------
String mediaTypeLabel(DocFile f) => f.typeLabel;

String? mediaProjectOf(AppState app, DocFile f) {
  if (f.reportId != null) return app.docs.reports.where((r) => r.id == f.reportId).firstOrNull?.projectId;
  if (f.recordId != null) return app.units.byId(f.recordId!)?.projectId;
  if (f.revisionId != null) {
    final rev = app.docs.revisions.where((r) => r.id == f.revisionId).firstOrNull;
    if (rev == null) return null;
    return app.docs.items.where((i) => i.id == rev.itemId).firstOrNull?.projectId;
  }
  return null;
}

/// القسم الذي يتبعه الملف (مفتاح الشاشة الرئيسية).
String mediaSectionOf(AppState app, DocFile f) {
  if (f.reportId != null) return 'supervision';
  if (f.recordId != null) {
    final r = app.units.byId(f.recordId!);
    final s = r == null ? null : unitSectionOf[r.unit];
    return s == null || s == 'technical' ? 'docs' : s;
  }
  return 'docs';
}

String mediaOwnerLabel(AppState app, DocFile f) {
  if (f.reportId != null) {
    final r = app.docs.reports.where((x) => x.id == f.reportId).firstOrNull;
    return r == null ? 'تقرير يومي' : 'تقرير يومي ${dayText(r.reportDate)}';
  }
  if (f.recordId != null) {
    final r = app.units.byId(f.recordId!);
    if (r == null) return 'سجل قسم';
    return '${unitKinds[r.kind]?.single ?? 'سجل'}: ${r.title}';
  }
  final rev = app.docs.revisions.where((r) => r.id == f.revisionId).firstOrNull;
  final item = rev == null ? null : app.docs.items.where((i) => i.id == rev.itemId).firstOrNull;
  if (item == null) return 'مستند';
  return '${docKindSingle[item.kind] ?? 'مستند'}: ${item.title} (${rev!.label})';
}

/// السجل المناسب للصفحة المفتوحة (لزر «تصدير وطباعة» في الشريط العلوي)، أو null لاختياره يدوياً.
String? exportSourceForTab(int tab) => switch (tab) {
      0 || 1 => 'cycle:contracts',
      2 => 'cycle:requests',
      3 || 8 => 'cycle:forms',
      4 || >= 171 && <= 182 => 'cycle:ideas',
      7 => 'cycle:finance',
      20 || 21 || 22 => 'risks:register',
      40 || 41 || 48 || 51 => 'risks:projects',
      42 => 'risks:progress',
      52 || 67 || 72 || 73 => 'risks:schedule',
      43 => 'risks:issues',
      44 => 'risks:delays',
      45 => 'risks:changes',
      46 => 'risks:lessons',
      47 => 'risks:evaluations',
      30 || 31 || 32 || 33 || 36 || 37 => 'swot:factors',
      34 => 'swot:strategies',
      35 => 'swot:plan',
      60 => 'docs:boq',
      61 => 'docs:letter',
      62 => 'docs:design',
      63 || 132 => 'media:files',
      64 => 'unit:material_approval',
      65 => 'docs:prices',
      66 => 'docs:boq_sheet',
      70 || 71 => 'supervision:reports',
      90 || 91 => 'unit:heritage_building',
      92 => 'unit:heritage_assessment',
      100 || 101 => 'unit:plan',
      102 => 'unit:qa_audit',
      103 => 'unit:followup_task',
      110 || 111 => 'unit:safety_inspection',
      112 => 'unit:safety_incident',
      113 => 'unit:safety_violation',
      120 || 121 => 'unit:handover',
      122 => 'unit:qc_test',
      200 || 201 => 'stores:items',
      202 => 'stores:docs',
      203 => 'stores:balances',
      205 => 'stores:employees',
      207 => 'stores:assets',
      210 => 'stores:custody',
      211 => 'stores:counts',
      212 => 'stores:movement',
      _ => null,
    };
