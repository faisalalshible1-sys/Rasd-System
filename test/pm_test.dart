import 'package:dc_app/models.dart';
import 'package:dc_app/pm.dart';
import 'package:dc_app/registers.dart';
import 'package:flutter_test/flutter_test.dart';

/// قواعد الإصدار 2.3 من «سجل المخاطر ومتابعة المشاريع».
void main() {
  Project project(String id, String company, int sort) =>
      Project.fromMap({'id': id, 'assign_no': id, 'name': 'عقد $id', 'company': company, 'sort_order': sort});
  PmSchedule schedule(String id, String status, String start, String end, [String display = '']) => PmSchedule.fromMap(
      {'project_id': id, 'op_status': status, 'start_date': start, 'end_date': end, 'display_name': display});
  PmProgress measure(String id, String on, double planned, double actual) =>
      PmProgress.fromMap({'id': '$id-$on', 'project_id': id, 'measured_on': on, 'planned': planned, 'actual': actual});

  final projects = [
    project('p1', 'شركة أ', 1), // جارٍ بقياسين
    project('p2', 'شركة ب', 2), // منجز دون قياس نهائي 100%
    project('p3', 'شركة ج', 3), // بلا برنامج زمني، وتقييم ميداني فقط
    project('p4', 'شركة د', 4), // جارٍ دون قياسات ولا تقييم
    project('p5', 'شركة هـ', 5), // لم يبدأ
  ];
  final schedules = {
    'p1': schedule('p1', 'running', '2026-06-01', '2026-12-31', 'طريق الصابري'),
    'p2': schedule('p2', 'completed', '2026-06-01', '2026-09-30'),
    'p4': schedule('p4', 'running', '2026-05-01', '2027-05-01'),
    'p5': schedule('p5', 'not_started', '2026-12-01', '2027-06-01'),
  };
  final progress = [
    measure('p1', '2026-10-01', 0.5, 0.45),
    measure('p1', '2026-11-01', 0.7, 0.6),
    measure('p2', '2026-10-01', 1, 0.9),
  ];
  final evaluations = [
    PmEvaluation.fromMap({'id': 'e1', 'project_id': 'p3', 'evaluated_on': '2026-10-15', 'quality': 4, 'safety': 4}),
  ];

  PmAnalysis analyse([Map<String, dynamic> extra = const {}]) => PmAnalysis(
        projects: projects,
        schedules: schedules,
        progress: progress,
        risks: const [],
        reviews: const [],
        issues: const [],
        delays: const [],
        changes: const [],
        lessons: const [],
        evaluations: evaluations,
        riskCfg: RiskConfig.defaults,
        cfg: PmConfig.fromJson({'ref_date': '2026-11-12', ...extra}),
      );

  test('المنجز أو المستلم: لا سرعة مطلوبة ولا تاريخ إنجاز متوقع، وتنبيه القياس النهائي', () {
    final a = analyse();
    final done = a.track('p2')!;
    expect(done.isDone, isTrue);
    expect(done.requiredSpeed, isNull);
    expect(done.forecastEnd, isNull);
    expect(done.doneWithoutFinal, isTrue);
    expect(a.track('p1')!.requiredSpeed, isNotNull);
    expect(a.track('p1')!.forecastEnd, isNotNull);
    expect(a.alerts.firstWhere((x) => x.key == 'final').count, 1);
  });

  test('الاسم المختصر للعرض', () {
    final a = analyse();
    expect(a.track('p1')!.displayName, 'طريق الصابري');
    expect(a.track('p2')!.displayName, 'عقد p2');
  });

  test('الدرجة المركّبة تتطلب مكونين على الأقل ومعهما الجدول أو التقييم الميداني', () {
    final a = analyse();
    ContractorKpi k(String n) => a.contractors.firstWhere((x) => x.name == n);
    expect(a.cfg.kpiMinComponents, 2);
    expect(k('شركة أ').composite, isNotNull); // الالتزام الزمني + التأخير المنسوب
    expect(k('شركة ج').composite, isNull); // تقييم ميداني فقط
    expect(k('شركة ج').gradeName, ContractorKpi.insufficientLabel);
    expect(k('شركة ج').gradeRec, ContractorKpi.insufficientRec);
    expect(k('شركة د').composite, isNull); // تأخير منسوب فقط
  });

  test('الحد الأدنى قابل للتعديل، وشرط الجدول أو التقييم الميداني ثابت', () {
    final a = analyse({'kpi_min_components': 1});
    ContractorKpi k(String n) => a.contractors.firstWhere((x) => x.name == n);
    expect(k('شركة ج').composite, isNotNull);
    expect(k('شركة د').composite, isNull);
    expect(PmConfig.fromJson({'kpi_min_components': 9}).kpiMinComponents, 4);
  });

  test('الجارية خلال الفترة تشمل ما اكتمل خلالها ولا تشمل ما لم يبدأ', () {
    final a = analyse();
    final r = a.report(false, DateTime(2026, 11, 4)); // الأسبوع 1–7 نوفمبر
    expect(r.start, DateTime(2026, 11, 1));
    expect(r.end, DateTime(2026, 11, 7));
    expect(r.runningIn(a.track('p1')!), isTrue);
    expect(r.runningIn(a.track('p2')!), isTrue); // لم يبلغ 100% قبل بداية الفترة
    expect(r.runningIn(a.track('p3')!), isFalse); // بلا تاريخ بداية
    expect(r.runningIn(a.track('p5')!), isFalse); // لم يبدأ
    expect(r.runningProjects, 3);
  });

  test('نوعا المشروع الجديدان في القوائم الافتراضية', () {
    expect(PmConfig.defaults.projectTypes, containsAll(['إزالة الركام والمخلفات والهدم', 'توريد وتركيب']));
  });
}
