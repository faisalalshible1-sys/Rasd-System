import 'package:dc_app/pm.dart';
import 'package:dc_app/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// البرنامج الزمني من المقايسة (الترحيل 36): العلاقات الأربع، والمسار الحرج، ومعدلات الإنتاجية، ومقارنة الإصدارات.
void main() {
  final d0 = DateTime(2026, 3, 1);
  DateTime d(int n) => addDays(d0, n);
  PmItem item(String id, int dur, {int sort = 0, String? phase, int offset = 0, String? dependsOn, DateTime? snb}) => PmItem(
      id: id,
      projectId: 'p',
      title: id,
      sort: sort,
      plannedStart: d0,
      plannedEnd: d0,
      durationDays: dur,
      phaseId: phase,
      offsetDays: offset,
      dependsOn: dependsOn,
      startNotBefore: snb);

  test('العلاقات الأربع وانتظارها كما في قاعدة البيانات', () {
    final items = [item('a', 10, sort: 1), item('b', 4, sort: 2)];
    (DateTime, DateTime) b(String kind, int lag) =>
        PlanLayout(d0, const [], items, links: [PmLink(id: 'l', predId: 'a', succId: 'b', kind: kind, lagDays: lag)]).dates['b']!;
    expect(b('FS', 2), (d(12), d(16)), reason: 'يبدأ بعد نهاية السابق بيومين');
    expect(b('SS', 3), (d(3), d(7)));
    expect(b('FF', 1), (d(7), d(11)), reason: 'ينتهي بعد نهاية السابق بيوم');
    expect(b('SF', 6), (d(2), d(6)), reason: 'ينتهي بعد بداية السابق بستة أيام');
    expect(b('FS', -3), (d(7), d(11)), reason: 'الانتظار السالب تداخل');
    expect(b('SF', 1).$1, d0, reason: 'ولا يسبق أساسه');
  });

  test('«لا يبدأ قبل» والإزاحة و«يتبع البند» القديم', () {
    final l = PlanLayout(d0, const [], [
      item('a', 5, sort: 1),
      item('b', 2, sort: 2, dependsOn: 'a', offset: 1),
      item('c', 3, sort: 3, snb: d(20)),
    ]);
    expect(l.dates['b'], (d(6), d(8)), reason: 'نهاية السابق ثم الإزاحة');
    expect(l.dates['c'], (d(20), d(23)));
    // علاقة مقابلة لـ«يتبع البند» تحل محله
    final l2 = PlanLayout(d0, const [], [item('a', 5, sort: 1), item('b', 2, sort: 2, dependsOn: 'a')],
        links: const [PmLink(id: 'l', predId: 'a', succId: 'b', kind: 'SS')]);
    expect(l2.dates['b'], (d0, d(2)));
  });

  test('المسار الحرج: المرونة لكل نشاط ومن يحدد نهاية البرنامج', () {
    final items = [item('a', 5, sort: 1), item('b', 3, sort: 2), item('c', 2, sort: 3)];
    const links = [PmLink(id: 'l', predId: 'a', succId: 'b')];
    final l = PlanLayout(d0, const [], items, links: links);
    expect(l.end, d(8));
    final f = PlanFloat(l, const [], links);
    expect(f.total['a'], 0);
    expect(f.total['b'], 0);
    expect(f.total['c'], 6);
    expect(f.criticalIds.toSet(), {'a', 'b'});
    expect(f.latest['c'], (d(6), d(8)));
  });

  test('المسار الحرج عبر المراحل وفواصلها والإزاحات', () {
    const phases = [
      PmPhase(id: 'p1', projectId: 'p', sort: 1, name: 'الأولى', lagDays: 0),
      PmPhase(id: 'p2', projectId: 'p', sort: 2, name: 'الثانية', lagDays: 2),
    ];
    final items = [
      item('a', 4, sort: 1, phase: 'p1'),
      item('c', 1, sort: 2, phase: 'p1'),
      item('b', 3, sort: 3, phase: 'p2', offset: 1),
    ];
    final l = PlanLayout(d0, phases, items);
    expect(l.dates['b'], (d(7), d(10)), reason: 'المرحلة الثانية بعد نهاية الأولى بيومين، والنشاط بعد إزاحته');
    final f = PlanFloat(l, phases, const []);
    expect(f.total['b'], 0);
    expect(f.total['a'], 0, reason: 'نهاية المرحلة الأولى تحدد بداية الثانية');
    expect(f.total['c'], 3);
  });

  test('المسار الحرج مع علاقة نهاية←نهاية وإزاحة التالي', () {
    final items = [item('a', 5, sort: 1), item('b', 2, sort: 2, offset: 1), item('z', 12, sort: 3)];
    const links = [PmLink(id: 'l', predId: 'a', succId: 'b', kind: 'FF')];
    final l = PlanLayout(d0, const [], items, links: links);
    expect(l.dates['b'], (d(4), d(6)));
    final f = PlanFloat(l, const [], links);
    // النهاية 12 من z؛ ب يتأخر حتى نهايته 12، فينتهي أ حتى 12 − 1 (الإزاحة)
    expect(f.total['b'], 6);
    expect(f.total['a'], 6);
    expect(f.criticalIds, ['z']);
  });

  test('معدلات الإنتاجية: الساري والمطابق والمدة', () {
    PmRate r(String unit, String kw, double rate, DateTime from, {bool active = true}) =>
        PmRate(id: '$unit$kw$rate', unit: unit, keyword: kw, rate: rate, validFrom: from, active: active);
    final all = [
      r('م3', '', 30, DateTime(2026, 1, 1)),
      r('م3', 'حفر', 50, DateTime(2026, 1, 1)),
      r('م3', 'حفر', 60, DateTime(2026, 6, 1)),
      r('م3', 'حفر', 80, DateTime(2027, 1, 1)),
      r('م3', 'ردم', 45, DateTime(2026, 1, 1), active: false),
      r('م3', 'خرسانة مسلحة', 12, DateTime(2026, 1, 1)),
    ];
    final cur = currentRates(all, DateTime(2026, 7, 1));
    expect(cur.length, 4);
    expect(rateFor(cur, 'م٣', 'أعمال الحفر: حفر خنادق')?.rate, 60);
    expect(rateFor(cur, 'م 3', 'ردم بالتربة')?.rate, 30, reason: 'غير المفعّل لا يُستعمل');
    expect(rateFor(cur, 'م3', 'خرسانه مسلحه للقواعد')?.rate, 12);
    expect(rateFor(cur, 'م2', 'حفر'), isNull);
    expect(rateDays(cur, 'م3', 'حفر', 240), 4);
    expect(rateDays(cur, 'م3', 'ردم', 181), 7);
    expect(rateDays(cur, 'م3', 'ردم', 0), isNull);
    expect(pmUnitNorm('م.ط'), 'مط');
    expect(pmTextNorm('أعمال الحفرة'), 'اعمال الحفره');
    expect(rateFor(currentRates(all, DateTime(2026, 3, 1)), 'م3', 'حفر')?.rate, 50, reason: 'قبل سريان الإصدار التالي');
  });

  test('مقارنة الإصدار بالحالي والفعلي', () {
    final v = PmPlanVersion.fromMap({
      'id': 'v',
      'project_id': 'p',
      'version': 1,
      'start_date': '2026-03-01',
      'end_date': '2026-03-20',
      'items': [
        {'id': 'a', 'title': 'أ', 'start': '2026-03-01', 'end': '2026-03-10', 'duration': 9},
        {'id': 'x', 'title': 'محذوف', 'start': '2026-03-01', 'end': '2026-03-02', 'duration': 1},
      ],
    });
    expect(v.totalDays, 19);
    final cur = [
      PmItem(id: 'a', projectId: 'p', title: 'أ', plannedStart: DateTime(2026, 3, 3), plannedEnd: DateTime(2026, 3, 14), actualEnd: DateTime(2026, 3, 16)),
      PmItem(id: 'n', projectId: 'p', title: 'جديد', plannedStart: DateTime(2026, 3, 5), plannedEnd: DateTime(2026, 3, 6)),
    ];
    final c = compareVersion(v, cur);
    expect(c.length, 3);
    expect(c[0].startShift, 2);
    expect(c[0].endShift, 4);
    expect(c[0].actualEndShift, 6);
    expect(c[1].removed, isTrue);
    expect(c[2].added, isTrue);
  });
}
