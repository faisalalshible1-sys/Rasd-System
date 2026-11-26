import 'package:dc_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// الإصدار 1.6.0 (الترحيل 37): ضمانات العقد وتأميناته، ولوحة معلومات العقد، وأوامر التغيير ببنودها، ولجان الاستلام.
void main() {
  test('ضمانات العقد: نسبتاه الثابتتان و«لا ينطبق» وخصم التأمينات', () {
    final p = Project.fromMap({
      'id': 'p',
      'executed_value': 500000,
      'guarantee_initial_rate': 0.03,
      'guarantee_final_rate': 0.05,
      'guarantee_final_na': true,
      'guarantee_final': null,
      'retention_deduct': false,
      'retention_rate': 0.05,
    });
    expect(p.initialRate, 0.03);
    expect(p.finalRate, 0.05);
    expect(p.guaranteeFinalNa, isTrue);
    expect(p.guaranteeFinal, isNull);
    expect(p.retentionDeduct, isFalse);
    expect(p.retentionRateOr(0.1), 0, reason: 'الخصم معطّل: لا تأمين مقترح');
    final q = Project.fromMap({'id': 'q', 'retention_rate': 0.05});
    expect(q.retentionDeduct, isTrue, reason: 'الافتراضي مفعّل كما كان قبل الترحيل');
    expect(q.retentionRateOr(0.1), 0.05);
    expect(Project.fromMap({'id': 'r'}).retentionRateOr(0.1), 0.1, reason: 'قبل الترحيل: النسبة العامة');
    expect(Project.fromMap({'id': 'r'}).initialRate, guaranteeInitialRate);
  });

  test('لوحة معلومات العقد: مثال الفصل 7 المحلول', () {
    // عقد 1,000,000 · أمران معتمدان +80,000 و−30,000 · دفعة مقدمة 100,000 مصروفة
    // المستخلص 1: 200,000 صافيه 170,000 مدفوع · المستخلص 2: 300,000 صافيه 250,000 محال
    final p = Project.fromMap({
      'id': 'p',
      'contract_value': 1000000,
      'variations_net': 50000,
      'variations_add': 80000,
      'variations_deduct': 30000,
      'executed_value': 500000,
      'extracts_count': 2,
      'extracts_gross': 500000,
      'extracts_net': 420000,
      'extracts_paid': 170000,
      'extracts_submitted': 500000,
      'retention_held': 25000,
      'advance_amount': 100000,
      'advance_paid_on': '2026-01-10',
      'advance_recovered': 50000,
    });
    expect(p.adjustedValue, 1050000);
    expect(p.variationsAdd - p.variationsDeduct, p.variationsNet);
    expect(p.paidTotal, 270000);
    expect(p.unpaidGross, 330000);
    expect(p.extractDeductions, 30000, reason: 'تأمين 25,000 وغرامات 5,000، دون استرداد الدفعة المقدمة');
    expect(p.outstanding, 250000);
    expect(p.unpaidGross - p.extractDeductions - p.advanceRecovered, p.outstanding);
    expect(p.financialProgress, closeTo(0.4762, 1e-4));
    expect(Project.fromMap({'id': 'z'}).financialProgress, isNull);
  });

  test('أمر التغيير: الحالة والقيمتان والصافي، والأوامر القديمة من نوعها وقيمتها', () {
    final v = ContractVariation.fromMap({
      'id': 'v',
      'project_id': 'p',
      'title': 'زيادة الحفر وإلغاء جزء من الخرسانة',
      'kind': 'deduct',
      'amount': 550,
      'added_value': 4200,
      'deducted_value': 4750,
      'status': 'draft',
    });
    expect(v.isDraft, isTrue);
    expect(v.statusLabel, 'مسودة');
    expect(v.signed, -550);
    final old = ContractVariation.fromMap({'id': 'o', 'project_id': 'p', 'title': 'قديم', 'kind': 'add', 'amount': 20000});
    expect(old.isApproved, isTrue, reason: 'ما قبل الترحيل محتسب كما كان');
    expect(old.addedValue, 20000);
    expect(old.deductedValue, 0);
    expect(old.signed, 20000);
  });

  test('بند أمر التغيير: القيمة = الكمية × السعر، وإلا المكتوبة', () {
    expect(VariationItem.valueOf(120, 35, null), 4200);
    expect(VariationItem.valueOf(5, 950, 1), 4750, reason: 'الكمية والسعر يغلبان القيمة المكتوبة');
    expect(VariationItem.valueOf(null, 35, 1000), 1000);
    const it = VariationItem(direction: 'deduct', boqSheetId: 's', boqLine: 1, description: 'إلغاء خرسانة', qty: 5, unitPrice: 950, amount: 4750);
    expect(it.isAdd, isFalse);
    expect(it.linkedToBoq, isTrue);
    expect(it.toJson(), containsPair('boq_line', 1));
    expect(it.toJson(), containsPair('direction', 'deduct'));
  });

  test('لجنة الاستلام: مطابقة الأسماء كقاعدة البيانات ونص المحضر', () {
    expect(nameKey('م. أحمد علي'), nameKey('م.  احمد علي'));
    expect(nameKey('فاطمة'), nameKey('فاطمه'));
    expect(nameKey('مُصطفى'), nameKey('مصطفي'));
    expect(nameKey('سالم'), isNot(nameKey('سليم')));
    final c = const ContractCommittee(id: 'c', projectId: 'p', kind: 'initial').withMembers(const [
      CommitteeMember(role: 'chair', name: 'م. سالم', title: 'رئيس قسم المطابقة'),
      CommitteeMember(name: 'م. علي'),
    ]);
    expect(c.chair?.name, 'م. سالم');
    expect(c.others.length, 1);
    expect(c.text, 'رئيس اللجنة: م. سالم (رئيس قسم المطابقة)، م. علي');
    expect(c.label, 'لجنة الاستلام الابتدائي');
    expect(committeeFormKeys['initial'], 'f25');
  });
}
