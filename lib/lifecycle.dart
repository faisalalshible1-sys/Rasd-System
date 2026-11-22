// =====================================================================
// دورة حياة العقد (الفصل 30 من الدليل): ست مراحل من اليمين إلى اليسار
//   أمر العمل ← التنفيذ ← الاستلام الابتدائي ← المستخلصات ← الاستلام النهائي ← إقفال العقد
// حالة كل مرحلة ونسبتها وتاريخاها من نماذج الدورة المستندية للعقد، ومن البرنامج الزمني المعتمد (التنفيذ)،
// ومن سجل المستخلصات (المستخلصات)، ومن حالة التشغيل في البرنامج الزمني للعقد (الاستلامان).
// =====================================================================

import 'models.dart';
import 'pm.dart';
import 'schedule.dart';

/// تعريف مرحلة: مفتاحها واسمها ونماذجها.
class LifeDef {
  const LifeDef(this.key, this.name, this.forms);

  final String key;
  final String name;
  final List<String> forms;
}

const List<LifeDef> lifeDefs = [
  LifeDef('work_order', 'أمر العمل', ['f02', 'f04', 'f05', 'f06', 'f07', 'f08', 'f09']),
  LifeDef('execution', 'التنفيذ', []),
  LifeDef('initial', 'الاستلام الابتدائي', ['f25', 'f16']),
  LifeDef('extracts', 'المستخلصات', ['f10', 'f11', 'f12', 'f13', 'f14', 'f22', 'f23', 'f24', 'f15']),
  LifeDef('final', 'الاستلام النهائي', ['f26', 'f17']),
  LifeDef('closure', 'إقفال العقد', ['f18']),
];

/// نموذج في مرحلة بحالته وتاريخ آخر تحديث.
class LifeForm {
  const LifeForm(this.def, this.status, this.at);

  final FormDef def;
  final FormStatus status;
  final DateTime? at;
}

/// مرحلة محسوبة لعقد.
class LifePhase {
  const LifePhase({
    required this.def,
    required this.status,
    this.pct,
    this.start,
    this.end,
    this.plannedStart,
    this.plannedEnd,
    this.forms = const [],
    this.note = '',
    this.late = false,
  });

  final LifeDef def;

  /// تم، أو قيد التنفيذ، أو لم يتم، أو لا ينطبق.
  final FormStatus status;

  /// النسبة 0–100 (فارغة إن لم تنطبق).
  final double? pct;
  final DateTime? start;
  final DateTime? end;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final List<LifeForm> forms;
  final String note;

  /// التنفيذ متأخر عن برنامجه.
  final bool late;

  String get name => def.name;
}

DateTime? _min(Iterable<DateTime?> xs) {
  DateTime? m;
  for (final x in xs) {
    if (x != null && (m == null || x.isBefore(m))) m = x;
  }
  return m;
}

DateTime? _max(Iterable<DateTime?> xs) {
  DateTime? m;
  for (final x in xs) {
    if (x != null && (m == null || x.isAfter(m))) m = x;
  }
  return m;
}

DateTime? _d(DateTime? t) => t == null ? null : DateTime(t.year, t.month, t.day);

/// حالة مجموعة نماذج: كلها «لا ينطبق» ← لا ينطبق؛ كل المنطبق «تم» ← تم؛ أي «تم» أو «قيد التنفيذ» ← قيد التنفيذ؛ وإلا لم يتم.
/// والنسبة = النماذج «تم» ÷ النماذج المنطبقة.
(FormStatus, double?) formsStatus(List<LifeForm> forms) {
  final applicable = forms.where((f) => f.status != FormStatus.na).toList();
  if (forms.isEmpty || applicable.isEmpty) return (FormStatus.na, null);
  final done = applicable.where((f) => f.status == FormStatus.done).length;
  final pct = done / applicable.length * 100;
  if (done == applicable.length) return (FormStatus.done, 100.0);
  if (applicable.any((f) => f.status == FormStatus.done || f.status == FormStatus.wip)) return (FormStatus.wip, pct);
  return (FormStatus.todo, pct);
}

/// مراحل دورة حياة عقد.
List<LifePhase> lifecycleOf({
  required List<FormDef> formDefs,
  required Map<String, FormStatus> statuses,
  Map<String, DateTime> formDates = const {},
  ScheduleTrack? track,
  PmSchedule? schedule,
  List<ContractExtract> extracts = const [],
}) {
  final defs = {for (final d in formDefs) d.key: d};
  List<LifeForm> formsOf(LifeDef l) => [
        for (final k in l.forms)
          if (defs[k] != null && defs[k]!.active) LifeForm(defs[k]!, statuses[k] ?? FormStatus.todo, _d(formDates[k])),
      ];
  final op = schedule?.opStatus ?? '';
  final out = <LifePhase>[];
  for (final l in lifeDefs) {
    final forms = formsOf(l);
    var (st, pct) = formsStatus(forms);
    DateTime? start = _min(forms.where((f) => f.status == FormStatus.done || f.status == FormStatus.wip).map((f) => f.at));
    DateTime? end = st == FormStatus.done ? _max(forms.where((f) => f.status == FormStatus.done).map((f) => f.at)) : null;
    DateTime? ps, pe;
    var note = '';
    var late = false;
    switch (l.key) {
      case 'execution':
        final t = track;
        ps = t?.planStart ?? schedule?.startDate;
        pe = t?.end ?? schedule?.endDate;
        if (t != null && t.calcs.isNotEmpty) {
          pct = t.actual;
          final a = t.actual ?? 0;
          st = a >= 100 ? FormStatus.done : (a > 0 || t.items.any((i) => i.actualStart != null) ? FormStatus.wip : FormStatus.todo);
          start = _min(t.items.map((i) => i.actualStart)) ?? (a > 0 ? ps : null);
          end = st == FormStatus.done ? (_max(t.items.map((i) => i.actualEnd)) ?? t.projectedEnd) : null;
          late = t.isLate;
          note = 'الإنجاز الكلي الموزون من البرنامج الزمني المعتمد';
        } else {
          pct = null;
          st = opDone.contains(op) ? FormStatus.done : (op == 'running' && ps != null && !ps.isAfter(pmToday()) ? FormStatus.wip : FormStatus.todo);
          start = st == FormStatus.todo ? null : ps;
          end = st == FormStatus.done ? pe : null;
          note = 'لا برنامج زمني معتمد؛ الحالة من حالة التشغيل في البرنامج الزمني للعقد';
        }
      case 'extracts':
        final xs = extracts;
        if (xs.isNotEmpty) {
          final finalPaid = xs.any((x) => x.kind == 'final' && (x.status == 'approved' || x.status == 'paid'));
          if (st == FormStatus.na || st == FormStatus.todo) st = FormStatus.wip;
          if (finalPaid && (pct == null || pct >= 100)) st = FormStatus.done;
          start = _min([start, ...xs.map((x) => x.submittedOn ?? x.periodFrom)]);
          if (st == FormStatus.done) end = _max([end, ...xs.map((x) => x.paidOn ?? x.approvedOn)]);
          final approved = xs.where((x) => x.status == 'approved' || x.status == 'paid').length;
          note = 'المستخلصات المسجلة ${xs.length}، المعتمد والمدفوع منها $approved';
        }
      case 'initial':
        if (op == 'prov_accepted' || op == 'final_accepted') {
          st = FormStatus.done;
          pct = 100.0;
        }
      case 'final':
        if (op == 'final_accepted') {
          st = FormStatus.done;
          pct = 100.0;
        }
    }
    out.add(LifePhase(
      def: l,
      status: st,
      pct: pct,
      start: start,
      end: end,
      plannedStart: ps,
      plannedEnd: pe,
      forms: forms,
      note: note,
      late: late,
    ));
  }
  return out;
}

/// المرحلة الحالية: أول مرحلة لم تتم (عدا ما لا ينطبق)، وإلا آخر مرحلة.
int currentPhaseIndex(List<LifePhase> phases) {
  for (var i = 0; i < phases.length; i++) {
    if (phases[i].status == FormStatus.wip) return i;
  }
  for (var i = 0; i < phases.length; i++) {
    if (phases[i].status == FormStatus.todo) return i;
  }
  return phases.length - 1;
}
