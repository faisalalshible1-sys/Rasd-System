// =====================================================================
// مصادر التصدير: كل سجل في المنظومة بأعمدته وتصفيته ومؤشراته، ليُستخرج بأي صيغة ويُطبع بأي قالب.
// المصدر يعرف عناصره (العقود، المستخلصات، سجلات الأقسام…)، وكيف يصير العنصر صفاً، وعقده وتاريخه للتصفية.
// =====================================================================

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart';
import '../models.dart';
import '../pm.dart';
import '../registers.dart';
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
      );
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

/// كل المصادر المتاحة لهذا المستخدم الآن (ما لم تُطبَّق ترحيلاته لا يظهر).
List<ExportSource> exportSources(AppState app) => [for (final s in _all(app)) if (s.ready(app)) s];

ExportSource? exportSource(AppState app, String id) {
  for (final s in _all(app)) {
    if (s.id == id) return s.ready(app) ? s : null;
  }
  return null;
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
          _C('assign_no', 'رقم التكليف', flex: 0.8),
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
          x.statusLabel,
          x.referralNo,
        ],
        summary: (a, l) => [
          ('المستخلصات', '${l.length}'),
          ('الصافي', fmtNumber(l.fold<double>(0, (s, x) => s + x.net))),
          ('غير المدفوع', fmtNumber(l.fold<double>(0, (s, x) => s + x.unpaid))),
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
          _C('date', 'تاريخ الاعتماد', type: ColType.date, flex: 0.9),
          _C('notes', 'ملاحظات', type: ColType.long, on: false),
        ],
        row: (a, x) => [_pj(a, x.projectId), x.refNo, x.title, x.isAdd ? 'إضافة' : 'خصم', x.isAdd ? x.amount : -x.amount, x.approvedOn, x.notes],
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
          _C('score', 'الدرجة', type: ColType.number, flex: 0.5),
          _C('level', 'المستوى', flex: 0.8),
          _C('owner', 'المالك', flex: 1),
          _C('response', 'الاستجابة', flex: 0.8, on: false),
          _C('mitigation', 'إجراءات المعالجة', type: ColType.long, on: false),
          _C('next', 'المراجعة القادمة', type: ColType.date, flex: 0.9),
          _C('status', 'الحالة', flex: 0.8),
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
          _C('deviation', 'الانحراف', type: ColType.percent, flex: 0.6),
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
String mediaTypeLabel(DocFile f) => f.isVideo ? 'فيديو' : (f.isImage ? 'صورة' : (f.isPdf ? 'PDF' : 'ملف'));

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
      4 => 'cycle:ideas',
      7 => 'cycle:finance',
      20 || 21 || 22 => 'risks:register',
      40 || 41 || 48 || 51 => 'risks:projects',
      42 => 'risks:progress',
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
      _ => null,
    };
