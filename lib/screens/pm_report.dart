import 'package:flutter/material.dart';

import '../app_state.dart';
import '../pm.dart';
import '../services/export.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;
import 'pm_common.dart';

// =====================================================================
// التقرير الدوري (أسبوعي من الأحد إلى السبت، أو شهري) لمتابعة المشاريع
// =====================================================================
class PmReportPage extends StatefulWidget {
  const PmReportPage({super.key});

  @override
  State<PmReportPage> createState() => _PmReportPageState();
}

class _PmReportPageState extends State<PmReportPage> {
  bool _monthly = false;
  DateTime? _date;
  final _notes = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _export(AppState app, PeriodicReport r) async {
    setState(() => _exporting = true);
    try {
      final res = await exportPmReportXlsx(app, r, _notes.text.trim());
      if (mounted && res != null) showToast(context, 'صُدّر ${r.title}');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'التقرير الدوري');
    final sem = Sem.of(context);
    final pm = app.pm;
    final r = pm.report(_monthly, _date ?? pm.ref);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return PageBody(
      maxWidth: 1200,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: r.title,
          subtitle: 'مكتب الشؤون الهندسية · ${r.periodLabel} · من ${pmDay(r.start)} إلى ${pmDay(r.end)}',
          icon: Icons.summarize_rounded,
          actions: [
            FilledButton.icon(
              onPressed: _exporting ? null : () => _export(app, r),
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined),
              label: const Text('تصدير Excel'),
            ),
          ],
        ),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('أسبوعي'), icon: Icon(Icons.view_week_outlined)),
              ButtonSegment(value: true, label: Text('شهري'), icon: Icon(Icons.calendar_month_outlined)),
            ],
            selected: {_monthly},
            onSelectionChanged: (s) => setState(() => _monthly = s.first),
          ),
          SizedBox(
            width: 240,
            child: DayField(label: 'تاريخ الإسناد (فارغ = اليوم)', value: _date, onChanged: (d) => setState(() => _date = d)),
          ),
          Text(_monthly ? 'الشهر من أوله إلى آخره' : 'الأسبوع من الأحد إلى السبت', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'أولاً: ملخص الفترة',
          icon: Icons.insights_outlined,
          subtitle: 'بنود «حالياً» تعكس الوضع في تاريخ الإسناد؛ بقية البنود محصورة بين بداية الفترة ونهايتها.',
          child: ResponsiveGrid(minItemWidth: narrow ? 260 : 330, spacing: 0, children: [
            // هامش بين الأعمدة حتى لا تلتصق قيمة عمود بعنوان العمود المجاور
            for (final kv in <Widget>[
              PmKv('المشاريع الجارية', '${r.runningProjects}'),
              PmKv('مشاريع متأخرة في نهاية الفترة (بسيط + حرج)', '${r.lateAtEnd}', color: r.lateAtEnd > 0 ? sem.danger : null),
              PmKv('متوسط الإنجاز المخطط للجارية (موزون)', pctOrDash(r.plannedW, digits: 1)),
              PmKv('متوسط الإنجاز الفعلي للجارية (موزون)', pctOrDash(r.actualW, digits: 1)),
              PmKv('الإنجاز المحقق خلال الفترة (موزون)', pctOrDash(r.gainW, digits: 1)),
              PmKv('مؤشر أداء الجدول للمحفظة SPI', spiText(r.spiW)),
              PmKv('مخاطر جديدة سُجلت خلال الفترة', '${r.newRisks}'),
              PmKv('مخاطر أُغلقت خلال الفترة', '${r.closedRisks}'),
              PmKv('مراجعات مخاطر نُفذت خلال الفترة', '${r.reviewsDone}'),
              PmKv('مخاطر مرتفعة/مرتفعة جداً نشطة حالياً', '${r.highNow}', color: r.highNow > 0 ? sem.danger : null),
              PmKv('مشاكل جديدة رُصدت خلال الفترة', '${r.newIssues}'),
              PmKv('مشاكل أُغلقت خلال الفترة', '${r.closedIssues}'),
              PmKv('مشاكل مفتوحة متأخرة عن موعد الحل', '${r.overdueIssues}', color: r.overdueIssues > 0 ? sem.danger : null),
              PmKv('أحداث تأخير بدأت خلال الفترة', '${r.delaysStarted}'),
              PmKv('أحداث تأخير قائمة حالياً', '${r.ongoingDelays}'),
              PmKv('طلبات تغيير قُدمت خلال الفترة', '${r.changesSubmitted}'),
              PmKv('تغييرات اعتُمدت خلال الفترة', '${r.changesApproved}'),
              PmKv('قيمة التغييرات المعتمدة خلال الفترة', moneyOrDash(r.approvedValue)),
              PmKv('دروس مستفادة وُثقت خلال الفترة', '${r.lessonsDocumented}'),
              PmKv('تقييمات ميدانية للشركات خلال الفترة', '${r.evaluationsDone}'),
            ])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: kv),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'ثانياً: تقدم المشاريع خلال الفترة',
          icon: Icons.show_chart_rounded,
          child: PmTable(
            columns: const ['م', 'العقد', 'الشركة', 'المخطط نهاية الفترة', 'الفعلي بداية الفترة', 'الفعلي نهاية الفترة', 'الإنجاز خلال الفترة', 'الانحراف', 'SPI', 'مؤشر الأداء', 'المعوقات'],
            rows: [
              for (var i = 0; i < r.rows.length; i++)
                [
                  '${i + 1}',
                  pmProjectName(app, r.rows[i].track.project.id),
                  r.rows[i].track.project.company,
                  pctOrDash(r.rows[i].planned, digits: 1),
                  pctOrDash(r.rows[i].actualStart, digits: 1),
                  pctOrDash(r.rows[i].actualEnd, digits: 1),
                  pctOrDash(r.rows[i].gain, digits: 1),
                  pctOrDash(r.rows[i].deviation, digits: 1),
                  spiText(r.rows[i].spi),
                  perfLabels[r.rows[i].perf(app.pmConfig)] ?? '',
                  r.rows[i].obstacles,
                ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'ثالثاً: أعلى 5 مخاطر نشطة حسب الدرجة الحالية',
          icon: Icons.local_fire_department_outlined,
          child: PmTable(
            columns: const ['الرمز', 'وصف الخطر', 'المشروع', 'الدرجة الحالية', 'المستوى', 'الاتجاه', 'مالك الخطر', 'المتابعة', 'الاستجابة ومسار التصعيد'],
            rows: [
              for (final s in r.topRisks)
                [
                  s.risk.code,
                  s.risk.description,
                  s.risk.projectId == null ? s.risk.projectGroup : pmProjectName(app, s.risk.projectId),
                  '${s.currentScore}',
                  s.currentLevel.name,
                  trendLabels[s.trend] ?? '',
                  s.risk.owner,
                  _follow(s.followUp),
                  s.escalation,
                ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'رابعاً: المشاكل المتأخرة عن موعد الحل (الأكثر تجاوزاً)',
          icon: Icons.report_problem_outlined,
          child: PmTable(
            columns: const ['الرمز', 'وصف المشكلة', 'المشروع', 'الأولوية', 'الجهة المسؤولة', 'الموعد المستهدف', 'أيام التجاوز', 'القسم المتابع', 'الإجراء'],
            rows: [
              for (final i in r.lateIssues)
                [
                  i.code,
                  i.description,
                  pmProjectName(app, i.projectId),
                  pmPriorityLabels[i.priority] ?? '',
                  pmPartyLabels[i.party] ?? '',
                  pmDay(i.targetDate),
                  '${i.overdueDays(pm.ref)}',
                  i.department,
                  i.action,
                ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'خامساً: ملاحظات وتوصيات المكتب',
          icon: Icons.edit_note_rounded,
          subtitle: 'تُضاف إلى ملف Excel المصدَّر. أعدّه: مكتب المدير · يعتمد: مدير المكتب الهندسي المكلف.',
          child: TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 10,
            decoration: fieldDeco('الملاحظات والتوصيات'),
          ),
        ),
      ],
    );
  }

  static String _follow(String f) => switch (f) {
        'overdue' => 'متأخرة',
        'soon' => 'مستحقة قريباً',
        'ontime' => 'ضمن الموعد',
        'none' => 'بلا موعد',
        _ => 'مغلق',
      };
}
