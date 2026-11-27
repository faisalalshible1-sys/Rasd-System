import 'package:dc_app/procurement.dart';
import 'package:flutter_test/flutter_test.dart';

/// قسم المشتريات (الترحيل 41): معادلات الكميات والإجماليات والتنبيهات كما في الدليل (الفصل 36).
void main() {
  PrRequest req(String id, String status, {DateTime? submitted, DateTime? reviewed, DateTime? decided, DateTime? needed}) => PrRequest(
        id: id,
        reqNo: 'PR-2026-$id',
        title: 'طلب $id',
        status: status,
        submittedAt: submitted,
        reviewedAt: reviewed,
        decidedAt: decided,
        neededBy: needed,
      );

  test('الكمية المطلوب شراؤها وإجمالي الأمر (مثال الدليل)', () {
    const l = PrLine(id: 'l1', requestId: 'r1', lineNo: 1, qty: 100, stockQty: 40);
    expect(l.toBuy, 60);
    const o = PrOrderLine(id: 'o1', orderId: 'p1', lineId: 'l1', itemId: 'i1', unitId: 'u1', qty: 60, unitPrice: 12.5);
    expect(o.amount, 750);
    expect(const PrOrderLine(id: 'o2', orderId: 'p1', lineId: 'l1', itemId: 'i1', unitId: 'u1', qty: 3, unitPrice: 0.3333).amount, 1);
    expect(const PrOrderLine(id: 'o3', orderId: 'p1', lineId: 'l1', itemId: 'i1', unitId: 'u1', qty: 10, received: 4).remaining, 6);
  });

  test('الحالات والإعدادات الافتراضية', () {
    expect(req('1', 'draft').isDraft, isTrue);
    expect(req('1', 'draft').isOpen, isTrue);
    expect(req('2', 'received').isOpen, isFalse);
    expect(req('3', 'fulfilled').isOpen, isFalse);
    expect(const PrSettings().minQuotes, 3);
    final s = PrSettings.fromRows([
      {'key': 'min_quotes', 'value': 2},
      {'key': 'grace_days', 'value': 5},
      {'key': 'ignored', 'value': 9},
    ]);
    expect(s.minQuotes, 2);
    expect(s.graceDays, 5);
    expect(s.reviewDays, 3);
  });

  test('البحث في الطلبات', () {
    final r = req('7', 'submitted');
    expect(r.matches(''), isTrue);
    expect(r.matches('pr-2026-7'), isTrue);
    expect(r.matches('طلب 7'), isTrue);
    expect(r.matches('غير موجود'), isFalse);
  });

  test('وحدات الصنف والمتاح بوحدة البند', () {
    final d = ProcurementData(
      items: const [PrItemRef(id: 'i1', code: 'A', name: 'ورق', baseUnitId: 'u-sheet', available: 1000)],
      units: const [PrUnitRef(id: 'u-sheet', name: 'ورقة'), PrUnitRef(id: 'u-box', name: 'علبة')],
      itemUnits: const [PrItemUnit(itemId: 'i1', unitId: 'u-box', factor: 500)],
    );
    expect(d.factorOf('i1', 'u-sheet'), 1);
    expect(d.factorOf('i1', 'u-box'), 500);
    expect(d.availableIn('i1', 'u-box'), 2);
    expect(d.availableIn('i1', null), 1000);
    expect(d.unitsOf('i1').map((u) => u.id), ['u-sheet', 'u-box']);
    expect(const ProcurementData().availableIn('x', null), isNull);
  });

  test('التنبيهات بمهل الإعدادات', () {
    final now = DateTime(2026, 11, 27, 10);
    final d = ProcurementData(
      requests: [
        req('a', 'submitted', submitted: DateTime(2026, 11, 20)), // 7 أيام ≥ 3
        req('b', 'submitted', submitted: DateTime(2026, 11, 26)), // يوم واحد: لا تنبيه
        req('c', 'reviewed', reviewed: DateTime(2026, 11, 22)), // 5 أيام ≥ 3
        req('d', 'approved', decided: DateTime(2026, 11, 21)), // 6 أيام ≥ 3
        req('e', 'ordered', needed: DateTime(2026, 11, 25)), // فات موعد الحاجة
        req('f', 'received', needed: DateTime(2026, 11, 1)), // مغلق: لا تنبيه
      ],
      orders: [
        PrOrder(id: 'p1', poNo: 'PO-1', requestId: 'e', supplierId: 's', status: 'issued', expectedDate: DateTime(2026, 11, 20)), // 7 − 3 = 4
        PrOrder(id: 'p2', poNo: 'PO-2', requestId: 'e', supplierId: 's', status: 'issued', expectedDate: DateTime(2026, 11, 26)), // لم يتأخر
      ],
    );
    final a = d.alerts(now);
    final kinds = a.map((x) => '${x.kind}:${x.requestId}').toList();
    expect(kinds, containsAll(['review_late:a', 'approve_late:c', 'order_late:d', 'needed_late:e', 'delivery_late:e']));
    expect(kinds.contains('review_late:b'), isFalse);
    expect(a.any((x) => x.requestId == 'f'), isFalse);
    expect(a.where((x) => x.kind == 'delivery_late').length, 1);
    // الأشد أولاً: التوريد المتأخر قبل غيره
    expect(a.first.kind, 'delivery_late');
    expect(a.first.isCritical, isTrue);
  });

  test('الأوامر القائمة وقيمة غير المستلَم', () {
    final d = ProcurementData(
      orders: const [
        PrOrder(id: 'p1', poNo: 'PO-1', requestId: 'r', supplierId: 's', status: 'issued'),
        PrOrder(id: 'p2', poNo: 'PO-2', requestId: 'r2', supplierId: 's', status: 'received'),
      ],
      orderLines: const [
        PrOrderLine(id: 'x', orderId: 'p1', lineId: 'l', itemId: 'i', unitId: 'u', qty: 10, unitPrice: 5, received: 4),
        PrOrderLine(id: 'y', orderId: 'p2', lineId: 'l', itemId: 'i', unitId: 'u', qty: 10, unitPrice: 5, received: 10),
      ],
    );
    expect(d.liveOrders.map((o) => o.id), ['p1']);
    expect(d.outstandingValue, 30);
    expect(d.orderOfRequest('r')?.id, 'p1');
  });

  test('كل حالة وحدث وتنبيه له وصف عربي', () {
    for (final s in ['draft', 'submitted', 'reviewed', 'approved', 'ordered', 'partial', 'received', 'fulfilled', 'rejected', 'cancelled']) {
      expect(prStatusLabels[s], isNotNull, reason: s);
    }
    for (final k in prAlertOrder) {
      expect(prAlertLabels[k], isNotNull, reason: k);
    }
    expect(prPriorityOrder.toSet(), prPriorityLabels.keys.toSet());
  });
}
