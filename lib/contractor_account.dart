// كشف حساب المقاولين (الإصدار 2.2.0، بلا ترحيل): تجميع عقود كل مقاول ومستخلصاته.
//
// المقاول هو اسم الشركة المسجَّل في المشروع (بعد تنظيف الفراغات). الحسابات تطابق فصل «المالية» في الدليل.

import 'models.dart';

/// تسميات شرائح أعمار المستحقات (كما في صفحة المالية).
const List<String> contractorAgingLabels = ['حتى 30 يوماً', '31–60 يوماً', '61–90 يوماً', 'أكثر من 90 يوماً', 'بلا تاريخ اعتماد'];

/// أعمار غير المدفوع من المستخلصات منذ الاعتماد، بترتيب [contractorAgingLabels].
List<double> agingBuckets(Iterable<ContractExtract> extracts, DateTime now) {
  final b = List<double>.filled(5, 0);
  final today = DateTime(now.year, now.month, now.day);
  for (final x in extracts) {
    final u = x.unpaid;
    if (u <= 0) continue;
    final d = x.approvedOn;
    if (d == null) {
      b[4] += u;
      continue;
    }
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    b[days <= 30 ? 0 : days <= 60 ? 1 : days <= 90 ? 2 : 3] += u;
  }
  return b;
}

/// حساب مقاول واحد.
class ContractorAccount {
  ContractorAccount(this.name);

  final String name;
  final List<Project> projects = [];
  final List<ContractExtract> extracts = [];
  double contract = 0, variationsNet = 0, executed = 0, paid = 0, unpaid = 0, retention = 0, pending = 0;
  List<double> aging = List<double>.filled(5, 0);

  /// القيمة بعد التغيير.
  double get adjusted => contract + variationsNet;

  /// المتبقي من القيمة بعد التغيير للدفع (لا ينزل عن صفر).
  double get remainingToPay => (adjusted - paid).clamp(0, double.infinity).toDouble();

  /// نسبة المدفوع من القيمة بعد التغيير.
  double? get paidRatio => adjusted <= 0 ? null : paid / adjusted;

  /// أقدم شريحة فيها مستحق غير مدفوع (للفرز والتنبيه).
  bool get hasOldDue => aging[3] > 0;
}

/// يجمّع [projects] و[extracts] حسب المقاول، ويرتّبهم بالأكبر مستحقاً غير مدفوع.
/// المشروع بلا اسم شركة لا يدخل.
List<ContractorAccount> contractorAccounts(Iterable<Project> projects, Iterable<ContractExtract> extracts, DateTime now) {
  final by = <String, ContractorAccount>{};
  final owner = <String, ContractorAccount>{};
  for (final p in projects) {
    final name = p.company.trim();
    if (name.isEmpty) continue;
    final a = by[name] ??= ContractorAccount(name);
    owner[p.id] = a;
    a.projects.add(p);
    a.contract += p.contractValue ?? 0;
    a.variationsNet += p.variationsNet;
    a.executed += p.executedValue ?? 0;
    a.paid += p.paidTotal;
    a.unpaid += p.outstanding;
    a.retention += p.retentionHeld;
  }
  for (final x in extracts) {
    final a = owner[x.projectId];
    if (a == null) continue;
    a.extracts.add(x);
    if (x.status == 'submitted') a.pending += x.net;
  }
  for (final a in by.values) {
    a.aging = agingBuckets(a.extracts, now);
  }
  return by.values.toList()
    ..sort((a, b) {
      final c = b.unpaid.compareTo(a.unpaid);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
}
