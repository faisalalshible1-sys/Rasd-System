// =====================================================================
// قسم المخازن: الأصول والعُهد والإهلاك (الإصدار 1.8.0، الترحيل 39): نماذج البيانات والحسابات.
//
// الإهلاك يُحسب ولا يُقيَّد، بالقسط الثابت شهرياً من تاريخ بدء الاستخدام (أو الشراء)، كدالة st_accumulated:
//   الأشهر المنقضية = فرق السنين × 12 + فرق الأشهر، ناقص شهر إن لم يبلغ اليوم يوم البداية
//   المتراكم = أقل من (التكلفة − الخردة) و(التكلفة − الخردة) × الأشهر ÷ العمر بالأشهر، مقرّباً إلى ثلاث خانات
//   القيمة الدفترية = التكلفة − المتراكم، وتتوقف عند تاريخ الاستبعاد.
// =====================================================================

String _s(Object? v) => v == null ? '' : '$v';
String? _id(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _nn(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// تاريخ بلا وقت (من «2026-01-15» أو طابع زمني).
DateTime? _day(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

const Map<String, String> assetStatusLabels = {
  'available': 'متاح',
  'in_use': 'مستخدم',
  'custody': 'في العهدة',
  'maintenance': 'تحت الصيانة',
  'damaged': 'معطّل',
  'disposal': 'بانتظار الاستبعاد',
  'disposed': 'مستبعد',
};

const Map<String, String> assetConditionLabels = {
  'new': 'جديد',
  'good': 'جيد',
  'fair': 'مقبول',
  'poor': 'سيئ',
  'damaged': 'تالف',
};

const Map<String, String> disposalKindLabels = {
  'scrap': 'إتلاف',
  'sale': 'بيع',
  'donate': 'إهداء',
  'lost': 'فقد',
  'other': 'غير ذلك',
};

const Map<String, String> depMethodLabels = {'straight': 'القسط الثابت', 'none': 'بلا إهلاك'};

const Map<String, String> assetEventLabels = {
  'create': 'تسجيل الأصل',
  'update': 'تعديل البيانات',
  'transfer': 'نقل',
  'status': 'تغيير الوضع',
  'custody_out': 'تسليم عهدة',
  'custody_in': 'إرجاع عهدة',
  'dispose_request': 'طلب استبعاد',
  'dispose': 'اعتماد الاستبعاد',
  'dispose_reject': 'رفض الاستبعاد',
};

double _r3(double v) => (v * 1000).roundToDouble() / 1000;

/// الأشهر الكاملة المنقضية بين تاريخين (صفر قبل البداية)، كدالة st_months_between.
int monthsBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  if (b.isBefore(a)) return 0;
  final m = (b.year - a.year) * 12 + b.month - a.month - (b.day < a.day ? 1 : 0);
  return m < 0 ? 0 : m;
}

/// الإهلاك المتراكم بالقسط الثابت حتى تاريخ، كدالة st_accumulated.
double accumulatedDepreciation({
  required double cost,
  required double salvage,
  required String method,
  required int? lifeMonths,
  required DateTime? start,
  required DateTime asOf,
}) {
  if (method != 'straight' || lifeMonths == null || lifeMonths <= 0 || start == null || cost <= salvage) return 0;
  final base = cost - salvage;
  final v = base * monthsBetween(start, asOf) / lifeMonths;
  return _r3(v < base ? v : base);
}

/// سياسة الإهلاك الافتراضية لتصنيف أصول (تُقترح للأصل الجديد وحده).
class StAssetPolicy {
  const StAssetPolicy({required this.categoryId, this.depMethod = 'straight', this.lifeMonths, this.salvagePct = 0});

  factory StAssetPolicy.fromMap(Map<String, dynamic> m) => StAssetPolicy(
        categoryId: _s(m['category_id']),
        depMethod: _s(m['dep_method']).isEmpty ? 'straight' : _s(m['dep_method']),
        lifeMonths: (m['life_months'] as num?)?.toInt(),
        salvagePct: _n(m['salvage_pct']),
      );

  final String categoryId;
  final String depMethod;
  final int? lifeMonths;
  final double salvagePct;

  String get label => depMethod == 'none'
      ? 'بلا إهلاك'
      : '${lifeMonths ?? '-'} شهراً${salvagePct > 0 ? ' · خردة ${salvagePct.toStringAsFixed(salvagePct == salvagePct.roundToDouble() ? 0 : 2)}%' : ''}';
}

class StAsset {
  const StAsset({
    required this.id,
    required this.tag,
    required this.name,
    required this.categoryId,
    this.itemId,
    this.manufacturer = '',
    this.model = '',
    this.serialNo = '',
    this.purchaseDate,
    this.inServiceDate,
    this.cost = 0,
    this.supplier = '',
    this.invoiceNo = '',
    this.warrantyUntil,
    this.depMethod = 'straight',
    this.lifeMonths,
    this.salvage = 0,
    this.status = 'available',
    this.condition = 'good',
    this.warehouseId,
    this.locationId,
    this.departmentId,
    this.employeeId,
    this.disposalKind,
    this.disposalReason = '',
    this.disposalValue,
    this.disposalDate,
    this.disposalRequestedAt,
    this.disposalRequestedBy,
    this.disposedAt,
    this.disposedBy,
    this.decisionNote = '',
    this.note = '',
    this.createdAt,
    this.createdBy,
    this.updatedAt,
  });

  factory StAsset.fromMap(Map<String, dynamic> m) => StAsset(
        id: _s(m['id']),
        tag: _s(m['tag']),
        name: _s(m['name']),
        categoryId: _s(m['category_id']),
        itemId: _id(m['item_id']),
        manufacturer: _s(m['manufacturer']),
        model: _s(m['model']),
        serialNo: _s(m['serial_no']),
        purchaseDate: _day(m['purchase_date']),
        inServiceDate: _day(m['in_service_date']),
        cost: _n(m['cost']),
        supplier: _s(m['supplier']),
        invoiceNo: _s(m['invoice_no']),
        warrantyUntil: _day(m['warranty_until']),
        depMethod: _s(m['dep_method']).isEmpty ? 'straight' : _s(m['dep_method']),
        lifeMonths: (m['life_months'] as num?)?.toInt(),
        salvage: _n(m['salvage']),
        status: _s(m['status']).isEmpty ? 'available' : _s(m['status']),
        condition: _s(m['condition']).isEmpty ? 'good' : _s(m['condition']),
        warehouseId: _id(m['warehouse_id']),
        locationId: _id(m['location_id']),
        departmentId: _id(m['department_id']),
        employeeId: _id(m['employee_id']),
        disposalKind: _id(m['disposal_kind']),
        disposalReason: _s(m['disposal_reason']),
        disposalValue: _nn(m['disposal_value']),
        disposalDate: _day(m['disposal_date']),
        disposalRequestedAt: _d(m['disposal_requested_at']),
        disposalRequestedBy: _id(m['disposal_requested_by']),
        disposedAt: _d(m['disposed_at']),
        disposedBy: _id(m['disposed_by']),
        decisionNote: _s(m['decision_note']),
        note: _s(m['note']),
        createdAt: _d(m['created_at']),
        createdBy: _id(m['created_by']),
        updatedAt: _d(m['updated_at']),
      );

  final String id;
  final String tag;
  final String name;
  final String categoryId;
  final String? itemId;
  final String manufacturer;
  final String model;
  final String serialNo;
  final DateTime? purchaseDate;
  final DateTime? inServiceDate;
  final double cost;
  final String supplier;
  final String invoiceNo;
  final DateTime? warrantyUntil;
  final String depMethod;
  final int? lifeMonths;
  final double salvage;
  final String status;
  final String condition;
  final String? warehouseId;
  final String? locationId;
  final String? departmentId;
  final String? employeeId;
  final String? disposalKind;
  final String disposalReason;
  final double? disposalValue;
  final DateTime? disposalDate;
  final DateTime? disposalRequestedAt;
  final String? disposalRequestedBy;
  final DateTime? disposedAt;
  final String? disposedBy;
  final String decisionNote;
  final String note;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;

  bool get isDisposed => status == 'disposed';
  bool get isDisposal => status == 'disposal';
  bool get inCustody => status == 'custody';

  /// يُسلَّم عهدةً: متاح أو مستخدم.
  bool get canHandOver => status == 'available' || status == 'in_use';

  /// يتغير وضعه أو يُطلب استبعاده: غير مسلَّم وغير مستبعد.
  bool get isFree => const {'available', 'in_use', 'maintenance', 'damaged'}.contains(status);

  /// تُعدَّل بياناته وينقل: غير مستبعد ولا بانتظار استبعاده.
  bool get isEditable => !isDisposed && !isDisposal;

  String get statusLabel => assetStatusLabels[status] ?? status;
  String get conditionLabel => assetConditionLabels[condition] ?? condition;

  /// بداية الإهلاك: بدء الاستخدام، وإلا تاريخ الشراء.
  DateTime? get depStart => inServiceDate ?? purchaseDate;

  /// تاريخ احتساب الإهلاك: اليوم، أو تاريخ الاستبعاد للأصل المستبعد.
  DateTime _asOf(DateTime d) => isDisposed && disposalDate != null && disposalDate!.isBefore(d) ? disposalDate! : d;

  double accumulated(DateTime asOf) => accumulatedDepreciation(
      cost: cost, salvage: salvage, method: depMethod, lifeMonths: lifeMonths, start: depStart, asOf: _asOf(asOf));

  double bookValue(DateTime asOf) => _r3(cost - accumulated(asOf));

  /// القسط الشهري: (التكلفة − الخردة) ÷ العمر بالأشهر.
  double get monthlyDepreciation =>
      depMethod != 'straight' || (lifeMonths ?? 0) <= 0 || cost <= salvage ? 0 : _r3((cost - salvage) / lifeMonths!);

  /// الأشهر المتبقية من العمر (صفر بعد اكتماله).
  int monthsLeft(DateTime asOf) {
    if (depMethod != 'straight' || lifeMonths == null || depStart == null) return 0;
    final left = lifeMonths! - monthsBetween(depStart!, _asOf(asOf));
    return left < 0 ? 0 : left;
  }

  /// الضمان ساري في تاريخ.
  bool underWarranty(DateTime d) => warrantyUntil != null && !warrantyUntil!.isBefore(DateTime(d.year, d.month, d.day));

  bool matches(String q) {
    if (q.isEmpty) return true;
    final x = q.toLowerCase();
    return name.toLowerCase().contains(x) ||
        tag.toLowerCase().contains(x) ||
        serialNo.toLowerCase().contains(x) ||
        model.toLowerCase().contains(x) ||
        manufacturer.toLowerCase().contains(x);
  }
}

/// محضر عهدة: التسليم ثم الإرجاع على السطر نفسه.
class StCustody {
  const StCustody({
    required this.id,
    required this.custodyNo,
    required this.assetId,
    required this.employeeId,
    this.departmentId,
    this.locationId,
    required this.handedOn,
    this.handedBy,
    this.conditionOut = 'good',
    this.accessoriesOut = '',
    this.noteOut = '',
    this.confirmedAt,
    this.returnedOn,
    this.receivedBy,
    this.conditionIn,
    this.accessoriesIn = '',
    this.noteIn = '',
    this.returnConfirmedAt,
  });

  factory StCustody.fromMap(Map<String, dynamic> m) => StCustody(
        id: _s(m['id']),
        custodyNo: _s(m['custody_no']),
        assetId: _s(m['asset_id']),
        employeeId: _s(m['employee_id']),
        departmentId: _id(m['department_id']),
        locationId: _id(m['location_id']),
        handedOn: _day(m['handed_on']) ?? DateTime(2000),
        handedBy: _id(m['handed_by']),
        conditionOut: _s(m['condition_out']),
        accessoriesOut: _s(m['accessories_out']),
        noteOut: _s(m['note_out']),
        confirmedAt: _d(m['confirmed_at']),
        returnedOn: _day(m['returned_on']),
        receivedBy: _id(m['received_by']),
        conditionIn: _id(m['condition_in']),
        accessoriesIn: _s(m['accessories_in']),
        noteIn: _s(m['note_in']),
        returnConfirmedAt: _d(m['return_confirmed_at']),
      );

  final String id;
  final String custodyNo;
  final String assetId;
  final String employeeId;
  final String? departmentId;
  final String? locationId;
  final DateTime handedOn;
  final String? handedBy;
  final String conditionOut;
  final String accessoriesOut;
  final String noteOut;
  final DateTime? confirmedAt;
  final DateTime? returnedOn;
  final String? receivedBy;
  final String? conditionIn;
  final String accessoriesIn;
  final String noteIn;
  final DateTime? returnConfirmedAt;

  bool get isOpen => returnedOn == null;

  /// أيام العهدة حتى الإرجاع أو حتى اليوم.
  int days(DateTime today) {
    final end = returnedOn ?? today;
    return DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(handedOn.year, handedOn.month, handedOn.day)).inDays;
  }
}

/// حدث في سجل حياة الأصل.
class StAssetEvent {
  const StAssetEvent({required this.id, required this.assetId, required this.kind, this.at, this.byUser, this.data = const {}, this.note = ''});

  factory StAssetEvent.fromMap(Map<String, dynamic> m) => StAssetEvent(
        id: (m['id'] as num?)?.toInt() ?? 0,
        assetId: _s(m['asset_id']),
        kind: _s(m['kind']),
        at: _d(m['at']),
        byUser: _id(m['by_user']),
        data: m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : const {},
        note: _s(m['note']),
      );

  final int id;
  final String assetId;
  final String kind;
  final DateTime? at;
  final String? byUser;
  final Map<String, dynamic> data;
  final String note;

  String get label => assetEventLabels[kind] ?? kind;
}

/// عهدة الموظف كما تصله في صفحته (st_my_custody): وصف الأصل دون تكلفته.
class MyCustody {
  const MyCustody({
    required this.id,
    required this.custodyNo,
    required this.tag,
    required this.name,
    this.category = '',
    this.manufacturer = '',
    this.model = '',
    this.serialNo = '',
    required this.handedOn,
    this.conditionOut = 'good',
    this.accessoriesOut = '',
    this.noteOut = '',
    this.confirmedAt,
    this.returnedOn,
    this.conditionIn,
    this.accessoriesIn = '',
    this.returnConfirmedAt,
  });

  factory MyCustody.fromMap(Map<String, dynamic> m) => MyCustody(
        id: _s(m['id']),
        custodyNo: _s(m['custody_no']),
        tag: _s(m['tag']),
        name: _s(m['name']),
        category: _s(m['category']),
        manufacturer: _s(m['manufacturer']),
        model: _s(m['model']),
        serialNo: _s(m['serial_no']),
        handedOn: _day(m['handed_on']) ?? DateTime(2000),
        conditionOut: _s(m['condition_out']),
        accessoriesOut: _s(m['accessories_out']),
        noteOut: _s(m['note_out']),
        confirmedAt: _d(m['confirmed_at']),
        returnedOn: _day(m['returned_on']),
        conditionIn: _id(m['condition_in']),
        accessoriesIn: _s(m['accessories_in']),
        returnConfirmedAt: _d(m['return_confirmed_at']),
      );

  final String id;
  final String custodyNo;
  final String tag;
  final String name;
  final String category;
  final String manufacturer;
  final String model;
  final String serialNo;
  final DateTime handedOn;
  final String conditionOut;
  final String accessoriesOut;
  final String noteOut;
  final DateTime? confirmedAt;
  final DateTime? returnedOn;
  final String? conditionIn;
  final String accessoriesIn;
  final DateTime? returnConfirmedAt;

  bool get isOpen => returnedOn == null;

  /// بانتظار تأكيد الموظف: استلام لم يؤكده، أو إرجاع سُجّل ولم يؤكده.
  bool get needsReceipt => confirmedAt == null;
  bool get needsReturnConfirm => returnedOn != null && returnConfirmedAt == null;

  String get description => [manufacturer, model].where((x) => x.isNotEmpty).join(' ');
}

/// السياسات نصاً للدليل (القيمة الحية STR_DEP_POLICIES): «الأجهزة المكتبية» 60 شهراً، و«الأثاث» 120 شهراً وخردة 10%.
String depPoliciesText(List<(String, StAssetPolicy)> named) {
  if (named.isEmpty) return 'لم تُحدَّد بعد';
  String pct(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return named
      .map((x) => x.$2.depMethod == 'none'
          ? '«${x.$1}» بلا إهلاك'
          : '«${x.$1}» ${x.$2.lifeMonths ?? '-'} شهراً${x.$2.salvagePct > 0 ? ' وخردة ${pct(x.$2.salvagePct)}%' : ''}')
      .join('، ');
}

/// سجل الأصول والعهد محمّلاً.
class AssetsData {
  AssetsData({this.assets = const [], this.custody = const [], this.policies = const []}) {
    for (final a in assets) {
      _asset[a.id] = a;
    }
    for (final c in custody) {
      (_byAsset[c.assetId] ??= []).add(c);
      (_byEmployee[c.employeeId] ??= []).add(c);
      if (c.isOpen) _open[c.assetId] = c;
    }
    for (final l in _byAsset.values) {
      l.sort((a, b) => b.handedOn != a.handedOn ? b.handedOn.compareTo(a.handedOn) : b.custodyNo.compareTo(a.custodyNo));
    }
    for (final l in _byEmployee.values) {
      l.sort((a, b) => a.isOpen != b.isOpen ? (a.isOpen ? -1 : 1) : b.handedOn.compareTo(a.handedOn));
    }
    for (final p in policies) {
      _policy[p.categoryId] = p;
    }
  }

  factory AssetsData.empty() => AssetsData();

  final List<StAsset> assets;
  final List<StCustody> custody;
  final List<StAssetPolicy> policies;

  final Map<String, StAsset> _asset = {};
  final Map<String, List<StCustody>> _byAsset = {};
  final Map<String, List<StCustody>> _byEmployee = {};
  final Map<String, StCustody> _open = {};
  final Map<String, StAssetPolicy> _policy = {};

  StAsset? asset(String? id) => id == null ? null : _asset[id];
  StAssetPolicy? policyOf(String? categoryId) => categoryId == null ? null : _policy[categoryId];

  /// العهدة المفتوحة للأصل.
  StCustody? openCustodyOf(String assetId) => _open[assetId];

  /// محاضر الأصل، الأحدث أولاً.
  List<StCustody> custodyOfAsset(String assetId) => _byAsset[assetId] ?? const [];

  /// عهد الموظف: المفتوحة أولاً ثم الأحدث.
  List<StCustody> custodyOfEmployee(String employeeId) => _byEmployee[employeeId] ?? const [];

  /// الأصول القائمة (غير المستبعدة).
  List<StAsset> get active => [for (final a in assets) if (!a.isDisposed) a];

  int countStatus(String s) => assets.where((a) => a.status == s).length;

  /// العهد المفتوحة التي لم يؤكد الموظف استلامها.
  List<StCustody> get unconfirmed => [for (final c in custody) if (c.isOpen && c.confirmedAt == null) c];

  /// طلبات الاستبعاد بانتظار الاعتماد.
  List<StAsset> get pendingDisposal => [for (final a in assets) if (a.isDisposal) a];

  /// مجموع التكلفة والقيمة الدفترية للأصول القائمة في تاريخ.
  ({double cost, double book}) totals(DateTime asOf, {Iterable<StAsset>? of}) {
    var c = 0.0, b = 0.0;
    for (final a in of ?? active) {
      if (a.isDisposed) continue;
      c += a.cost;
      b += a.bookValue(asOf);
    }
    return (cost: _r3(c), book: _r3(b));
  }

  /// أصول ينتهي ضمانها خلال مدة (من اليوم).
  List<StAsset> warrantyEnding(DateTime today, int days) {
    final t = DateTime(today.year, today.month, today.day);
    final limit = t.add(Duration(days: days));
    return [
      for (final a in active)
        if (a.warrantyUntil != null && !a.warrantyUntil!.isBefore(t) && !a.warrantyUntil!.isAfter(limit)) a
    ]..sort((a, b) => a.warrantyUntil!.compareTo(b.warrantyUntil!));
  }
}

/// أعمدة استيراد سجل الأصول من Excel (st_import_assets).
const Map<String, List<String>> assetImportColumns = {
  'tag': ['رقم الأصل', 'رمز الأصل', 'الرقم', 'tag', 'asset no'],
  'name': ['الوصف', 'اسم الأصل', 'الأصل', 'البيان', 'name'],
  'category': ['التصنيف', 'الفئة', 'category'],
  'manufacturer': ['المصنع', 'الشركة المصنعة', 'الماركة', 'manufacturer', 'brand'],
  'model': ['الموديل', 'الطراز', 'model'],
  'serial_no': ['الرقم التسلسلي', 'السيريال', 'serial', 'serial no'],
  'purchase_date': ['تاريخ الشراء', 'الشراء', 'purchase date'],
  'cost': ['التكلفة', 'القيمة', 'سعر الشراء', 'cost'],
  'supplier': ['المورد', 'supplier'],
  'invoice_no': ['رقم الفاتورة', 'الفاتورة', 'invoice'],
  'warranty_until': ['نهاية الضمان', 'الضمان', 'warranty'],
  'life_months': ['العمر بالأشهر', 'العمر', 'life'],
  'salvage': ['الخردة', 'قيمة الخردة', 'salvage'],
  'condition': ['الحالة', 'condition'],
  'location': ['الموقع', 'رمز الموقع', 'location'],
  'department': ['الإدارة', 'الادارة', 'department'],
  'emp_no': ['الرقم الوظيفي', 'رقم الموظف', 'المستلم', 'emp_no'],
  'note': ['ملاحظات', 'ملاحظة', 'note'],
};

/// حالة الأصل من خلية في ملف الاستيراد (بالعربية أو بالرمز).
String? parseAssetCondition(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (assetConditionLabels.containsKey(s)) return s;
  for (final e in assetConditionLabels.entries) {
    if (e.value == raw.trim()) return e.key;
  }
  return switch (s) {
    'ممتاز' || 'ممتازة' || 'جديدة' => 'new',
    'جيدة' => 'good',
    'متوسط' || 'متوسطة' || 'مقبولة' => 'fair',
    'رديء' || 'رديئة' || 'سيئة' => 'poor',
    'تالفة' || 'عاطل' || 'معطل' => 'damaged',
    _ => null,
  };
}
