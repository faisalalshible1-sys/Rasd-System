import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lifecycle.dart';
import '../models.dart';
import '../pm.dart';
import '../schedule.dart';
import '../ui/theme.dart';

// =====================================================================
// عناصر مشتركة للبرنامج الزمني والإشراف: ألوان الحالة الموحّدة، والمخطط الزمني من اليمين،
// والخط الزمني لدورة حياة العقد.
// =====================================================================

/// حالة البند بالألوان الموحّدة: «لا ينطبق»، أو «تم» عند 100%، أو «قيد التنفيذ» إن بدأ، وإلا «لم يتم».
FormStatus itemStatus(PmItem i) {
  if (i.notApplicable) return FormStatus.na;
  if (i.progress >= 100) return FormStatus.done;
  if (i.progress > 0 || i.actualStart != null) return FormStatus.wip;
  return FormStatus.todo;
}

/// شارة حالة ممتلئة بالألوان الموحّدة (تم أخضر، قيد التنفيذ برتقالي، لم يتم أحمر، لا ينطبق أسود/أبيض).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label, this.small = false, this.soft = false});

  final FormStatus status;
  final String? label;
  final bool small;

  /// خلفية فاتحة ونص ملوّن بدل الخلفية الممتلئة.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = sem.statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 1.5 : 3),
      decoration: BoxDecoration(
        color: soft ? sem.statusSoft(status) : c,
        borderRadius: BorderRadius.circular(99),
        border: soft && status == FormStatus.na ? Border.all(color: c) : null,
      ),
      child: Text(label ?? status.label,
          style: TextStyle(
              color: soft ? c : sem.onStatus(status), fontWeight: FontWeight.w800, fontSize: small ? 11 : 12, height: 1.3)),
    );
  }
}

/// وسيلة إيضاح الحالات الموحّدة.
class StatusLegend extends StatelessWidget {
  const StatusLegend({super.key, this.counts});

  final Map<FormStatus, int>? counts;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Wrap(spacing: 14, runSpacing: 6, children: [
      for (final s in FormStatus.values)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: sem.statusColor(s), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(counts == null ? s.label : '${s.label} ${counts![s] ?? 0}', style: TextStyle(fontSize: 12, color: sem.muted)),
        ]),
    ]);
  }
}

String daysWord(int n) => switch (n) {
      0 => '0 يوم',
      1 => 'يوم واحد',
      2 => 'يومان',
      <= 10 => '$n أيام',
      _ => '$n يوماً',
    };

// =====================================================================
// المخطط الزمني من اليمين إلى اليسار: صف لكل مرحلة (شريط امتدادها) ولكل بند (المدة والإنجاز)
// =====================================================================
class GanttRow {
  const GanttRow({
    required this.label,
    required this.start,
    required this.end,
    this.progress,
    this.color,
    this.phase = false,
    this.overdue = false,
    this.muted = false,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final DateTime start;
  final DateTime end;

  /// الإنجاز 0–100 (فارغ للمراحل وللإعداد).
  final double? progress;
  final Color? color;
  final bool phase;

  /// بند تجاوز نهايته ولم يكتمل: خط أحمر حتى تاريخ الإسناد.
  final bool overdue;

  /// «لا ينطبق»: شريط مخطّط باهت.
  final bool muted;
  final String? tooltip;
  final VoidCallback? onTap;
}

/// صفوف المخطط من جدول عقد ومراحله: المراحل بامتدادها، ثم بنود كل مرحلة.
List<GanttRow> ganttRows(BuildContext context, ScheduleTrack t, {bool progress = true, void Function(PmItem)? onTap}) {
  final sem = Sem.of(context);
  final rows = <GanttRow>[];
  final byPhase = <String?, List<PmItem>>{};
  final phaseIds = {for (final p in t.phases) p.id};
  for (final i in t.allItems) {
    (byPhase[phaseIds.contains(i.phaseId) ? i.phaseId : null] ??= []).add(i);
  }
  GanttRow itemRow(PmItem i) {
    final c = t.calcOf(i.id);
    final st = itemStatus(i);
    return GanttRow(
      label: [if (i.code.isNotEmpty) i.code, i.title].join(' '),
      start: i.plannedStart,
      end: i.plannedEnd,
      progress: progress ? i.progress : null,
      color: progress ? (c != null && c.isLate ? sem.statusColor(FormStatus.todo) : sem.statusColor(st == FormStatus.todo ? FormStatus.wip : st)) : null,
      overdue: progress && c?.overdueDays != null,
      muted: i.notApplicable,
      tooltip: '${i.title}\n${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)} · ${daysWord(i.days)}'
          '${progress ? ' · الإنجاز ${i.progress.toStringAsFixed(0)}%' : ''}',
      onTap: onTap == null ? null : () => onTap(i),
    );
  }

  for (final i in byPhase[null] ?? const <PmItem>[]) {
    rows.add(itemRow(i));
  }
  for (final p in t.phases) {
    final items = byPhase[p.id] ?? const <PmItem>[];
    if (items.isEmpty) continue;
    final s = items.map((i) => i.plannedStart).reduce((a, b) => a.isBefore(b) ? a : b);
    final e = items.map((i) => i.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b);
    rows.add(GanttRow(label: p.name, start: s, end: e, phase: true, tooltip: '${p.name}\n${pmDay(s)} إلى ${pmDay(e)} · ${daysWord(daysBetween(e, s))}'));
    for (final i in items) {
      rows.add(itemRow(i));
    }
  }
  return rows;
}

class PlanGantt extends StatelessWidget {
  const PlanGantt({super.key, required this.rows, this.ref});

  final List<GanttRow> rows;

  /// خط تاريخ الإسناد (للمتابعة).
  final DateTime? ref;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    var from = rows.map((r) => r.start).reduce((a, b) => a.isBefore(b) ? a : b);
    var to = rows.map((r) => r.end).reduce((a, b) => a.isAfter(b) ? a : b);
    if (ref != null && ref!.isBefore(from)) from = ref!;
    if (ref != null && ref!.isAfter(to)) to = ref!;
    from = DateTime(from.year, from.month, 1);
    to = DateTime(to.year, to.month + 1, 1);
    final span = math.max(1, daysBetween(to, from));
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final labelW = narrow ? 118.0 : 230.0;
    final accent = Theme.of(context).colorScheme.primary;
    final style = (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(fontSize: 10.5, color: sem.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SizedBox(width: labelW),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CustomPaint(painter: _RtlAxisPainter(from: from, to: to, span: span, grid: sem.rule, style: style)),
          ),
        ),
      ]),
      for (final r in rows)
        InkWell(
          onTap: r.onTap,
          child: SizedBox(
            height: r.phase ? 28 : 30,
            child: Row(children: [
              SizedBox(
                width: labelW,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8, start: 2),
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: r.phase ? 12.5 : 12,
                      fontWeight: r.phase ? FontWeight.w800 : FontWeight.w500,
                      color: r.phase ? accent : (r.muted ? sem.muted : null),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: r.tooltip ?? r.label,
                  child: CustomPaint(
                    painter: _RtlBarPainter(
                      row: r,
                      from: from,
                      span: span,
                      ref: ref,
                      plan: r.phase ? accent.withValues(alpha: 0.22) : sem.muted.withValues(alpha: 0.26),
                      phaseEdge: accent,
                      over: sem.danger,
                      refColor: accent,
                      grid: sem.rule,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// المحور: الأشهر من اليمين (أقدم) إلى اليسار (أحدث).
class _RtlAxisPainter extends CustomPainter {
  _RtlAxisPainter({required this.from, required this.to, required this.span, required this.style, required this.grid});

  final DateTime from, to;
  final int span;
  final TextStyle style;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final months = <DateTime>[];
    for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month + 1, 1)) {
      months.add(d);
    }
    final perMonth = size.width / math.max(1, months.length);
    final step = math.max(1, (46 / perMonth).ceil());
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k < months.length; k++) {
      final x = size.width - daysBetween(months[k], from) / span * size.width;
      canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), line);
      if (k % step != 0) continue;
      final m = months[k];
      final tp = TextPainter(text: TextSpan(text: '${m.month}/${m.year % 100}', style: style), textDirection: TextDirection.ltr)..layout();
      final lx = x - tp.width - 2;
      if (lx >= 0) tp.paint(canvas, Offset(lx, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RtlAxisPainter old) => old.from != from || old.to != to || old.style != style;
}

class _RtlBarPainter extends CustomPainter {
  _RtlBarPainter({
    required this.row,
    required this.from,
    required this.span,
    required this.ref,
    required this.plan,
    required this.phaseEdge,
    required this.over,
    required this.refColor,
    required this.grid,
  });

  final GanttRow row;
  final DateTime from;
  final int span;
  final DateTime? ref;
  final Color plan, phaseEdge, over, refColor, grid;

  double _x(DateTime d, double w) => (w - daysBetween(d, from) / span * w).clamp(0, w).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bar = row.phase ? h * 0.30 : h * 0.42;
    final top = (h - bar) / 2;
    final xs = _x(row.start, w); // البداية يميناً
    final xe = math.min(xs - 3, _x(row.end, w)); // النهاية يساراً
    final r = Radius.circular(bar / 2);
    canvas.drawLine(Offset(0, h - 0.5), Offset(w, h - 0.5), Paint()..color = grid.withValues(alpha: 0.5));
    canvas.drawRRect(RRect.fromLTRBR(xe, top, xs, top + bar, r), Paint()..color = row.muted ? plan.withValues(alpha: 0.10) : plan);
    if (row.phase) {
      final edge = Paint()
        ..color = phaseEdge
        ..strokeWidth = 2;
      canvas.drawLine(Offset(xs, top - 3), Offset(xs, top + bar + 3), edge);
      canvas.drawLine(Offset(xe, top - 3), Offset(xe, top + bar + 3), edge);
    }
    final p = row.progress;
    if (p != null && p > 0 && row.color != null && !row.muted) {
      final done = (xs - xe) * (p / 100).clamp(0, 1);
      canvas.drawRRect(RRect.fromLTRBR(xs - done, top + 1.5, xs, top + bar - 1.5, r), Paint()..color = row.color!);
    }
    if (row.overdue && ref != null) {
      final xr = _x(ref!, w);
      canvas.drawLine(Offset(xe, h / 2), Offset(xr, h / 2), Paint()
        ..color = over
        ..strokeWidth = 2.5);
    }
    if (ref != null) {
      final xr = _x(ref!, w);
      canvas.drawLine(Offset(xr, 0), Offset(xr, h), Paint()
        ..color = refColor
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _RtlBarPainter old) => old.row != row || old.span != span || old.ref != ref;
}

// =====================================================================
// الخط الزمني لدورة حياة العقد: من اليمين، بمسافات واضحة بين المراحل
// =====================================================================
class LifecycleTimeline extends StatelessWidget {
  const LifecycleTimeline({super.key, required this.phases, this.onTap, this.compact = false});

  final List<LifePhase> phases;
  final void Function(int index)? onTap;

  /// شريط نقاط مختصر (لجداول اللوحة).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final current = currentPhaseIndex(phases);
    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < phases.length; i++) ...[
          if (i > 0) Container(width: 8, height: 2, color: sem.rule),
          Tooltip(
            message: '${phases[i].name}: ${phases[i].status.label}${phases[i].pct == null ? '' : ' ${phases[i].pct!.toStringAsFixed(0)}%'}',
            child: Container(
              width: i == current ? 14 : 11,
              height: i == current ? 14 : 11,
              decoration: BoxDecoration(
                color: sem.statusColor(phases[i].status),
                shape: BoxShape.circle,
                border: i == current ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
              ),
            ),
          ),
        ],
      ]);
    }
    return LayoutBuilder(builder: (context, box) {
      const gap = 26.0;
      final n = phases.length;
      final cardW = math.max(150.0, (box.maxWidth - gap * (n - 1)) / n);
      final total = cardW * n + gap * (n - 1);
      final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) _Connector(width: gap, done: phases[i - 1].status == FormStatus.done),
          SizedBox(width: cardW, child: _PhaseCard(index: i, phase: phases[i], current: i == current, onTap: onTap == null ? null : () => onTap!(i))),
        ],
      ]);
      return total <= box.maxWidth + 0.5 ? row : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
    });
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.width, required this.done});

  final double width;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return SizedBox(
      width: width,
      height: 40,
      child: Center(
        child: Row(children: [
          Expanded(child: Container(height: 2, color: done ? sem.ok : sem.rule)),
          // سهم «التالي» يتبع اتجاه النص: نحو اليسار في الواجهة العربية
          Icon(Icons.chevron_right_rounded, size: 16, color: done ? sem.ok : sem.muted),
        ]),
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({required this.index, required this.phase, required this.current, this.onTap});

  final int index;
  final LifePhase phase;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = sem.statusColor(phase.status);
    final p = phase;
    String dates() {
      final a = p.start ?? p.plannedStart, b = p.end ?? p.plannedEnd;
      if (a == null && b == null) return 'دون تواريخ بعد';
      return '${a == null ? '—' : pmDay(a)} إلى ${b == null ? '—' : pmDay(b)}';
    }

    return Material(
      color: sem.statusSoft(p.status),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: current ? cs.primary : c.withValues(alpha: 0.55), width: current ? 2.2 : 1.2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: c,
                child: p.status == FormStatus.done
                    ? Icon(Icons.check_rounded, size: 16, color: sem.onStatus(p.status))
                    : Text('${index + 1}', style: TextStyle(color: sem.onStatus(p.status), fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.name, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.3)),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusChip(p.status, small: true),
              if (p.late) StatusChip(FormStatus.todo, label: 'متأخر', small: true, soft: true),
              if (current) Text('المرحلة الحالية', style: TextStyle(color: cs.primary, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((p.pct ?? 0) / 100).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: c,
                backgroundColor: sem.surface,
              ),
            ),
            const SizedBox(height: 6),
            Text(p.pct == null ? 'لا نسبة' : '${p.pct!.toStringAsFixed(p.pct! % 1 == 0 ? 0 : 1)}%',
                style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 13)),
            const SizedBox(height: 2),
            Text(dates(), style: TextStyle(color: sem.muted, fontSize: 11.5, height: 1.35)),
          ]),
        ),
      ),
    );
  }
}
