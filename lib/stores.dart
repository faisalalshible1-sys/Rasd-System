// =====================================================================
// قسم المخازن والأصول والخدمات العامة (الإصدار 1.7.0، الترحيل 38): نماذج البيانات والحسابات.
//
// المتاح = الفعلي − المحجوز. الاعتماد يحجز الكمية الخارجة، والترحيل وحده يغيّر الفعلي ويكتب دفتر الحركات.
// كل الحسابات هنا تطابق دوال قاعدة البيانات (st_doc_outgoing، st_reserve، st_post).
// =====================================================================

import 'models.dart' show normalizeArabic;

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _nn(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String _s(Object? v) => v == null ? '' : '$v';
String? _id(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;

/// كمية بفواصل الآلاف وحتى ثلاث خانات عشرية دون أصفار زائدة: 1,250 و12.5 و0.125.
String fmtQty(num v) {
  final milli = (v.abs() * 1000).round();
  final whole = milli ~/ 1000;
  final frac = milli % 1000;
  final ws = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  final fs = frac == 0 ? '' : '.${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${v < 0 && milli > 0 ? '-' : ''}$ws$fs';
}

/// العدد مع معدوده بالعربية: لا بنود، بند واحد، بندان، 3 بنود، 11 بنداً.
String arCount(int n, {required String one, required String two, required String few, required String many}) => switch (n) {
      0 => 'لا $few',
      1 => '$one واحد',
      2 => two,
      _ when n % 100 >= 3 && n % 100 <= 10 => '$n $few',
      _ => '$n $many',
    };

/// كمية بإشارتها (+50 أو -10) معزولة من اليسار لليمين، حتى لا تنتقل الإشارة إلى آخر الرقم في النص العربي.
String signedQty(num v) => '\u2066${v > 0 ? '+' : ''}${fmtQty(v)}\u2069';

/// تقريب الكمية إلى ثلاث خانات كما في قاعدة البيانات (numeric(…, 3)).
double roundQty(double v) => (v * 1000).roundToDouble() / 1000;

// ---------------------------------------------------------------------
// المسميات
// ---------------------------------------------------------------------

const Map<String, String> stDocKindLabels = {
  'opening': 'أرصدة أول المدة',
  'receipt': 'وارد',
  'issue': 'صرف',
  'return': 'مرتجع',
  'transfer': 'تحويل',
  'adjust': 'تسوية',
};

/// اسم المستند المفرد في العناوين («مستند صرف»).
const Map<String, String> stDocKindTitles = {
  'opening': 'مستند أرصدة أول المدة',
  'receipt': 'مستند وارد',
  'issue': 'مستند صرف',
  'return': 'مستند مرتجع',
  'transfer': 'مستند تحويل',
  'adjust': 'مستند تسوية',
};

const Map<String, String> stDocStatusLabels = {
  'draft': 'مسودة',
  'submitted': 'مقدَّم للاعتماد',
  'approved': 'معتمد بانتظار الترحيل',
  'posted': 'مرحَّل',
  'rejected': 'مرفوض',
  'cancelled': 'ملغى',
};

const Map<String, String> stLocationKindLabels = {'building': 'مبنى', 'floor': 'طابق', 'room': 'غرفة', 'area': 'مساحة'};
const Map<String, String> stCategoryKindLabels = {'consumable': 'استهلاكي', 'asset': 'أصل'};
const Map<String, String> stWarehouseKindLabels = {'main': 'رئيسي', 'sub': 'فرعي'};

/// مستوى رصيد الصنف مقارنةً بحدوده.
const Map<String, String> stockLevelLabels = {
  'out': 'نفد',
  'min': 'دون الحد الأدنى',
  'reorder': 'عند نقطة إعادة الطلب',
  'over': 'فوق الحد الأقصى',
  'ok': 'طبيعي',
};

/// نطاقات صلاحيات القسم (الترحيل 38).
const Map<String, String> storesScopeLabels = {
  'stores:admin': 'مدير النظام في المخازن',
  'stores:manager': 'مدير المخازن',
  'stores:audit': 'مراجع المخازن (اطلاع فقط)',
  'stores:assets': 'مسؤول الأصول والعهد',
};

String storesKeeperScope(String warehouseId) => 'stores:keeper:$warehouseId';

// ---------------------------------------------------------------------
// الهيكل
// ---------------------------------------------------------------------

class StDepartment {
  const StDepartment({required this.id, this.parentId, this.code = '', required this.name, this.active = true, this.sort = 0});

  factory StDepartment.fromMap(Map<String, dynamic> m) => StDepartment(
        id: _s(m['id']),
        parentId: _id(m['parent_id']),
        code: _s(m['code']),
        name: _s(m['name']),
        active: _b(m['active'], true),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String? parentId;
  final String code;
  final String name;
  final bool active;
  final int sort;
}

class StEmployee {
  const StEmployee({
    required this.id,
    this.empNo = '',
    required this.fullName,
    this.departmentId,
    this.jobTitle = '',
    this.phone = '',
    this.email = '',
    this.profileId,
    this.active = true,
    this.note = '',
  });

  factory StEmployee.fromMap(Map<String, dynamic> m) => StEmployee(
        id: _s(m['id']),
        empNo: _s(m['emp_no']),
        fullName: _s(m['full_name']),
        departmentId: _id(m['department_id']),
        jobTitle: _s(m['job_title']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        profileId: _id(m['profile_id']),
        active: _b(m['active'], true),
        note: _s(m['note']),
      );

  final String id;
  final String empNo;
  final String fullName;
  final String? departmentId;
  final String jobTitle;
  final String phone;
  final String email;
  final String? profileId;
  final bool active;
  final String note;

  String get label => empNo.isEmpty ? fullName : '$fullName ($empNo)';
}

class StLocation {
  const StLocation({required this.id, this.parentId, required this.kind, this.code = '', required this.name, this.active = true, this.sort = 0});

  factory StLocation.fromMap(Map<String, dynamic> m) => StLocation(
        id: _s(m['id']),
        parentId: _id(m['parent_id']),
        kind: _s(m['kind']),
        code: _s(m['code']),
        name: _s(m['name']),
        active: _b(m['active'], true),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String? parentId;
  final String kind;
  final String code;
  final String name;
  final bool active;
  final int sort;

  String get kindLabel => stLocationKindLabels[kind] ?? kind;
}

class StWarehouse {
  const StWarehouse({
    required this.id,
    required this.code,
    required this.name,
    this.kind = 'sub',
    this.parentId,
    this.locationId,
    this.active = true,
    this.note = '',
    this.sort = 0,
  });

  factory StWarehouse.fromMap(Map<String, dynamic> m) => StWarehouse(
        id: _s(m['id']),
        code: _s(m['code']),
        name: _s(m['name']),
        kind: _s(m['kind']).isEmpty ? 'sub' : _s(m['kind']),
        parentId: _id(m['parent_id']),
        locationId: _id(m['location_id']),
        active: _b(m['active'], true),
        note: _s(m['note']),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String code;
  final String name;
  final String kind;
  final String? parentId;
  final String? locationId;
  final bool active;
  final String note;
  final int sort;

  bool get isMain => kind == 'main';
}

// ---------------------------------------------------------------------
// الأصناف
// ---------------------------------------------------------------------

class StCategory {
  const StCategory({required this.id, this.parentId, required this.code, required this.name, this.kind = 'consumable', this.active = true, this.sort = 0});

  factory StCategory.fromMap(Map<String, dynamic> m) => StCategory(
        id: _s(m['id']),
        parentId: _id(m['parent_id']),
        code: _s(m['code']),
        name: _s(m['name']),
        kind: _s(m['kind']).isEmpty ? 'consumable' : _s(m['kind']),
        active: _b(m['active'], true),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String? parentId;
  final String code;
  final String name;
  final String kind;
  final bool active;
  final int sort;

  bool get isAsset => kind == 'asset';
}

class StUnit {
  const StUnit({required this.id, required this.name, this.active = true, this.sort = 0});

  factory StUnit.fromMap(Map<String, dynamic> m) =>
      StUnit(id: _s(m['id']), name: _s(m['name']), active: _b(m['active'], true), sort: (m['sort'] as num?)?.toInt() ?? 0);

  final String id;
  final String name;
  final bool active;
  final int sort;
}

/// وحدة أخرى للصنف: كم من الوحدة الأساسية فيها.
class StItemUnit {
  const StItemUnit({required this.itemId, required this.unitId, required this.factor});

  factory StItemUnit.fromMap(Map<String, dynamic> m) =>
      StItemUnit(itemId: _s(m['item_id']), unitId: _s(m['unit_id']), factor: _n(m['factor']));

  final String itemId;
  final String unitId;
  final double factor;
}

class StItem {
  const StItem({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    required this.categoryId,
    required this.baseUnitId,
    this.minQty = 0,
    this.maxQty,
    this.reorderQty = 0,
    this.criticalQty = 0,
    this.tracksExpiry = false,
    this.barcode = '',
    this.active = true,
  });

  factory StItem.fromMap(Map<String, dynamic> m) => StItem(
        id: _s(m['id']),
        code: _s(m['code']),
        name: _s(m['name']),
        description: _s(m['description']),
        categoryId: _s(m['category_id']),
        baseUnitId: _s(m['base_unit_id']),
        minQty: _n(m['min_qty']),
        maxQty: _nn(m['max_qty']),
        reorderQty: _n(m['reorder_qty']),
        criticalQty: _n(m['critical_qty']),
        tracksExpiry: _b(m['tracks_expiry']),
        barcode: _s(m['barcode']),
        active: _b(m['active'], true),
      );

  final String id;
  final String code;
  final String name;
  final String description;
  final String categoryId;
  final String baseUnitId;
  final double minQty;
  final double? maxQty;

  /// نقطة إعادة الطلب: عند بلوغ المتاح لها يُنبَّه لطلب التوريد.
  final double reorderQty;

  /// الاحتياطي الحرج: لا يُصرف منه إلا باستثناء من مدير المخازن بسبب مكتوب.
  final double criticalQty;
  final bool tracksExpiry;
  final String barcode;
  final bool active;

  bool matches(String q) {
    if (q.trim().isEmpty) return true;
    final n = normalizeArabic(q);
    return normalizeArabic(name).contains(n) || code.toLowerCase().contains(q.trim().toLowerCase()) || barcode == q.trim();
  }
}

/// مستوى الرصيد: نفد، دون الحد الأدنى، عند نقطة إعادة الطلب، فوق الحد الأقصى، طبيعي.
/// يُقارن المتاح (الفعلي − المحجوز) بالحدود، والفعلي بالحد الأقصى.
String stockLevel(StItem it, {required double onHand, required double available}) {
  if (onHand <= 0 && (it.minQty > 0 || it.reorderQty > 0)) return 'out';
  if (it.minQty > 0 && available < it.minQty) return 'min';
  if (it.reorderQty > 0 && available <= it.reorderQty) return 'reorder';
  if (it.maxQty != null && it.maxQty! > 0 && onHand > it.maxQty!) return 'over';
  return 'ok';
}

// ---------------------------------------------------------------------
// المستندات والأرصدة
// ---------------------------------------------------------------------

class StDoc {
  const StDoc({
    required this.id,
    required this.docNo,
    required this.kind,
    required this.status,
    required this.warehouseId,
    this.toWarehouseId,
    this.departmentId,
    this.employeeId,
    this.docDate,
    this.party = '',
    this.refNo = '',
    this.note = '',
    this.reversesId,
    this.overrideNote = '',
    this.decisionNote = '',
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.submittedAt,
    this.submittedBy,
    this.approvedAt,
    this.approvedBy,
    this.postedAt,
    this.postedBy,
    this.decidedAt,
    this.decidedBy,
    this.confirmedAt,
    this.confirmedBy,
  });

  factory StDoc.fromMap(Map<String, dynamic> m) => StDoc(
        id: _s(m['id']),
        docNo: _s(m['doc_no']),
        kind: _s(m['kind']),
        status: _s(m['status']).isEmpty ? 'draft' : _s(m['status']),
        warehouseId: _s(m['warehouse_id']),
        toWarehouseId: _id(m['to_warehouse_id']),
        departmentId: _id(m['department_id']),
        employeeId: _id(m['employee_id']),
        docDate: m['doc_date'] == null ? null : DateTime.tryParse('${m['doc_date']}'),
        party: _s(m['party']),
        refNo: _s(m['ref_no']),
        note: _s(m['note']),
        reversesId: _id(m['reverses_id']),
        overrideNote: _s(m['override_note']),
        decisionNote: _s(m['decision_note']),
        createdAt: _d(m['created_at']),
        createdBy: _id(m['created_by']),
        updatedAt: _d(m['updated_at']),
        submittedAt: _d(m['submitted_at']),
        submittedBy: _id(m['submitted_by']),
        approvedAt: _d(m['approved_at']),
        approvedBy: _id(m['approved_by']),
        postedAt: _d(m['posted_at']),
        postedBy: _id(m['posted_by']),
        decidedAt: _d(m['decided_at']),
        decidedBy: _id(m['decided_by']),
        confirmedAt: _d(m['confirmed_at']),
        confirmedBy: _id(m['confirmed_by']),
      );

  final String id;
  final String docNo;
  final String kind;
  final String status;
  final String warehouseId;
  final String? toWarehouseId;
  final String? departmentId;
  final String? employeeId;
  final DateTime? docDate;

  /// المورد أو الجهة (الوارد)، ورقم الفاتورة أو المرجع.
  final String party;
  final String refNo;
  final String note;

  /// المستند المرحَّل الذي يعكسه هذا المستند.
  final String? reversesId;

  /// سبب استثناء الاحتياطي الحرج عند الاعتماد.
  final String overrideNote;

  /// سبب الإعادة أو الرفض أو الإلغاء، أو ملاحظة الاعتماد.
  final String decisionNote;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final DateTime? submittedAt;
  final String? submittedBy;
  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? postedAt;
  final String? postedBy;
  final DateTime? decidedAt;
  final String? decidedBy;
  final DateTime? confirmedAt;
  final String? confirmedBy;

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved';
  bool get isPosted => status == 'posted';
  bool get isClosed => status == 'rejected' || status == 'cancelled';
  bool get isOpen => isDraft || isSubmitted || isApproved;
  bool get isReversal => reversesId != null;

  /// يُحذف المسودة التي لم تُقدَّم قط؛ وغيره يُلغى ليبقى أثره.
  bool get deletable => isDraft && submittedAt == null;

  String get kindLabel => stDocKindLabels[kind] ?? kind;
  String get statusLabel => stDocStatusLabels[status] ?? status;
  String get title => isReversal ? 'عكس ${stDocKindTitles[kind] ?? kind}' : (stDocKindTitles[kind] ?? kind);

  /// اتجاه أثر المستند على المخزن المصدر: 1 داخل، -1 خارج، 0 بإشارة كل بند (التسوية). العكسي بعكسه.
  int get direction {
    final d = switch (kind) {
      'opening' || 'receipt' || 'return' => 1,
      'issue' || 'transfer' => -1,
      _ => 0,
    };
    return isReversal ? -d : d;
  }

  /// يحتاج جهة مستلمة أو مُرجِعة.
  bool get hasRecipient => kind == 'issue' || kind == 'return';
}

class StDocLine {
  const StDocLine({
    required this.id,
    required this.docId,
    required this.lineNo,
    required this.itemId,
    required this.unitId,
    required this.qty,
    this.factor = 1,
    double? baseQty,
    this.expiryDate,
    this.batchNo = '',
    this.note = '',
  }) : _baseQty = baseQty;

  factory StDocLine.fromMap(Map<String, dynamic> m) => StDocLine(
        id: _s(m['id']),
        docId: _s(m['doc_id']),
        lineNo: (m['line_no'] as num?)?.toInt() ?? 0,
        itemId: _s(m['item_id']),
        unitId: _s(m['unit_id']),
        qty: _n(m['qty']),
        factor: m['factor'] == null ? 1 : _n(m['factor']),
        baseQty: _nn(m['base_qty']),
        expiryDate: m['expiry_date'] == null ? null : DateTime.tryParse('${m['expiry_date']}'),
        batchNo: _s(m['batch_no']),
        note: _s(m['note']),
      );

  final String id;
  final String docId;
  final int lineNo;
  final String itemId;
  final String unitId;
  final double qty;
  final double factor;
  final double? _baseQty;
  final DateTime? expiryDate;
  final String batchNo;
  final String note;

  /// الكمية بالوحدة الأساسية = الكمية × معامل الوحدة، مقرّبة لثلاث خانات (كالعمود المحسوب base_qty).
  double get baseQty => _baseQty ?? roundQty(qty * factor);
}

class StStock {
  const StStock({required this.warehouseId, required this.itemId, this.onHand = 0, this.reserved = 0});

  factory StStock.fromMap(Map<String, dynamic> m) =>
      StStock(warehouseId: _s(m['warehouse_id']), itemId: _s(m['item_id']), onHand: _n(m['on_hand']), reserved: _n(m['reserved']));

  final String warehouseId;
  final String itemId;
  final double onHand;
  final double reserved;

  /// المتاح = الفعلي − المحجوز.
  double get available => roundQty(onHand - reserved);
}

class StBatch {
  const StBatch({required this.id, required this.warehouseId, required this.itemId, required this.expiryDate, this.batchNo = '', this.qty = 0});

  factory StBatch.fromMap(Map<String, dynamic> m) => StBatch(
        id: _s(m['id']),
        warehouseId: _s(m['warehouse_id']),
        itemId: _s(m['item_id']),
        expiryDate: DateTime.tryParse('${m['expiry_date']}') ?? DateTime(2100),
        batchNo: _s(m['batch_no']),
        qty: _n(m['qty']),
      );

  final String id;
  final String warehouseId;
  final String itemId;
  final DateTime expiryDate;
  final String batchNo;
  final double qty;

  /// الأيام المتبقية حتى الانتهاء (سالبة بعده).
  int daysLeft(DateTime today) =>
      DateTime(expiryDate.year, expiryDate.month, expiryDate.day).difference(DateTime(today.year, today.month, today.day)).inDays;
}

/// سطر في دفتر الحركات (بطاقة الصنف).
class StMove {
  const StMove({
    required this.id,
    required this.docId,
    this.lineId,
    required this.warehouseId,
    required this.itemId,
    required this.qty,
    required this.balanceAfter,
    this.expiryDate,
    this.batchNo = '',
    this.at,
    this.byUser,
  });

  factory StMove.fromMap(Map<String, dynamic> m) => StMove(
        id: (m['id'] as num?)?.toInt() ?? 0,
        docId: _s(m['doc_id']),
        lineId: _id(m['line_id']),
        warehouseId: _s(m['warehouse_id']),
        itemId: _s(m['item_id']),
        qty: _n(m['qty']),
        balanceAfter: _n(m['balance_after']),
        expiryDate: m['expiry_date'] == null ? null : DateTime.tryParse('${m['expiry_date']}'),
        batchNo: _s(m['batch_no']),
        at: _d(m['at']),
        byUser: _id(m['by_user']),
      );

  final int id;
  final String docId;
  final String? lineId;
  final String warehouseId;
  final String itemId;
  final double qty;
  final double balanceAfter;
  final DateTime? expiryDate;
  final String batchNo;
  final DateTime? at;
  final String? byUser;
}

/// إعدادات القسم: فصل المهام (منشئ المستند لا يعتمده)، ومدة التنبيه قبل انتهاء الصلاحية بالأيام.
class StSettings {
  const StSettings({this.separation = true, this.expiryDays = 60});

  factory StSettings.fromRows(List<Map<String, dynamic>> rows) {
    var sep = true;
    var days = 60;
    for (final r in rows) {
      final v = r['value'];
      if (r['key'] == 'separation' && v is bool) sep = v;
      if (r['key'] == 'expiry_days' && v is num) days = v.toInt();
    }
    return StSettings(separation: sep, expiryDays: days);
  }

  final bool separation;
  final int expiryDays;
}

// ---------------------------------------------------------------------
// بيانات القسم المحمّلة وحساباتها
// ---------------------------------------------------------------------

/// تنبيه رصيد: الصنف ومستواه ومجموع فعليه ومتاحه في كل المخازن.
class StockAlert {
  const StockAlert(this.item, this.level, this.onHand, this.available);

  final StItem item;
  final String level;
  final double onHand;
  final double available;
}

class StoresData {
  StoresData({
    this.departments = const [],
    this.employees = const [],
    this.locations = const [],
    this.warehouses = const [],
    this.categories = const [],
    this.units = const [],
    this.items = const [],
    this.itemUnits = const [],
    this.docs = const [],
    this.lines = const [],
    this.stock = const [],
    this.batches = const [],
    this.settings = const StSettings(),
  }) {
    for (final x in departments) {
      _dep[x.id] = x;
    }
    for (final x in employees) {
      _emp[x.id] = x;
    }
    for (final x in locations) {
      _loc[x.id] = x;
    }
    for (final x in warehouses) {
      _wh[x.id] = x;
    }
    for (final x in categories) {
      _cat[x.id] = x;
    }
    for (final x in units) {
      _unit[x.id] = x;
    }
    for (final x in items) {
      _item[x.id] = x;
    }
    for (final x in itemUnits) {
      (_iu[x.itemId] ??= []).add(x);
    }
    for (final x in docs) {
      _doc[x.id] = x;
    }
    for (final x in lines) {
      (_lines[x.docId] ??= []).add(x);
    }
    for (final l in _lines.values) {
      l.sort((a, b) => a.lineNo.compareTo(b.lineNo));
    }
    for (final x in stock) {
      _stock['${x.warehouseId}|${x.itemId}'] = x;
      (_stockByItem[x.itemId] ??= []).add(x);
    }
  }

  factory StoresData.empty() => StoresData();

  final List<StDepartment> departments;
  final List<StEmployee> employees;
  final List<StLocation> locations;
  final List<StWarehouse> warehouses;
  final List<StCategory> categories;
  final List<StUnit> units;
  final List<StItem> items;
  final List<StItemUnit> itemUnits;
  final List<StDoc> docs;
  final List<StDocLine> lines;
  final List<StStock> stock;
  final List<StBatch> batches;
  final StSettings settings;

  final Map<String, StDepartment> _dep = {};
  final Map<String, StEmployee> _emp = {};
  final Map<String, StLocation> _loc = {};
  final Map<String, StWarehouse> _wh = {};
  final Map<String, StCategory> _cat = {};
  final Map<String, StUnit> _unit = {};
  final Map<String, StItem> _item = {};
  final Map<String, List<StItemUnit>> _iu = {};
  final Map<String, StDoc> _doc = {};
  final Map<String, List<StDocLine>> _lines = {};
  final Map<String, StStock> _stock = {};
  final Map<String, List<StStock>> _stockByItem = {};

  StDepartment? department(String? id) => id == null ? null : _dep[id];
  StEmployee? employee(String? id) => id == null ? null : _emp[id];
  StLocation? location(String? id) => id == null ? null : _loc[id];
  StWarehouse? warehouse(String? id) => id == null ? null : _wh[id];
  StCategory? category(String? id) => id == null ? null : _cat[id];
  StUnit? unit(String? id) => id == null ? null : _unit[id];
  StItem? item(String? id) => id == null ? null : _item[id];
  StDoc? doc(String? id) => id == null ? null : _doc[id];

  String unitName(String? id) => unit(id)?.name ?? '';
  String warehouseName(String? id) => warehouse(id)?.name ?? '';
  String itemName(String? id) => item(id)?.name ?? '';

  /// سجل الموظف المرتبط بحساب.
  StEmployee? employeeOfProfile(String? profileId) {
    if (profileId == null) return null;
    for (final e in employees) {
      if (e.profileId == profileId) return e;
    }
    return null;
  }

  List<StDocLine> linesOf(String docId) => _lines[docId] ?? const [];

  /// وحدات الصنف: الأساسية أولاً بمعامل 1، ثم الأخرى بمعاملاتها.
  List<(String, String, double)> unitsOf(StItem it) => [
        (it.baseUnitId, unitName(it.baseUnitId), 1.0),
        for (final u in _iu[it.id] ?? const <StItemUnit>[])
          if (u.unitId != it.baseUnitId) (u.unitId, unitName(u.unitId), u.factor),
      ];

  /// معامل وحدة للصنف (1 للأساسية، وnull لوحدة غير معرّفة له).
  double? factorOf(StItem it, String unitId) {
    if (unitId == it.baseUnitId) return 1;
    for (final u in _iu[it.id] ?? const <StItemUnit>[]) {
      if (u.unitId == unitId) return u.factor;
    }
    return null;
  }

  StStock? stockOf(String warehouseId, String itemId) => _stock['$warehouseId|$itemId'];
  List<StStock> stockOfItem(String itemId) => _stockByItem[itemId] ?? const [];

  double onHand(String itemId, {String? warehouseId}) => roundQty(
      [for (final s in stockOfItem(itemId)) if (warehouseId == null || s.warehouseId == warehouseId) s.onHand].fold(0.0, (a, b) => a + b));
  double reserved(String itemId, {String? warehouseId}) => roundQty(
      [for (final s in stockOfItem(itemId)) if (warehouseId == null || s.warehouseId == warehouseId) s.reserved].fold(0.0, (a, b) => a + b));
  double available(String itemId, {String? warehouseId}) =>
      roundQty(onHand(itemId, warehouseId: warehouseId) - reserved(itemId, warehouseId: warehouseId));

  String levelOf(StItem it, {String? warehouseId}) => stockLevel(it,
      onHand: onHand(it.id, warehouseId: warehouseId), available: available(it.id, warehouseId: warehouseId));

  /// الأصناف النشطة التي تحتاج انتباهاً: نفدت أو دون الحد الأدنى أو عند نقطة إعادة الطلب (الأشد أولاً).
  List<StockAlert> lowStock() {
    const rank = {'out': 0, 'min': 1, 'reorder': 2};
    final out = <StockAlert>[
      for (final it in items)
        if (it.active)
          StockAlert(it, levelOf(it), onHand(it.id), available(it.id)),
    ]..removeWhere((a) => !rank.containsKey(a.level));
    out.sort((a, b) => rank[a.level]!.compareTo(rank[b.level]!) != 0
        ? rank[a.level]!.compareTo(rank[b.level]!)
        : a.item.name.compareTo(b.item.name));
    return out;
  }

  /// دفعات بكمية تنتهي صلاحيتها خلال [days] يوماً أو انتهت (الأقرب أولاً).
  List<StBatch> expiring(DateTime today, [int? days]) {
    final limit = days ?? settings.expiryDays;
    final out = [for (final b in batches) if (b.qty > 0 && b.daysLeft(today) <= limit) b];
    out.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return out;
  }

  int get pendingApproval => docs.where((d) => d.isSubmitted).length;
  int get awaitingPost => docs.where((d) => d.isApproved).length;
  int get draftCount => docs.where((d) => d.isDraft).length;

  /// قيمة تقريبية لا تُحسب هنا: القسم لا يحمل أسعاراً (مستقل عن المالية)؛ المؤشرات كميات وأعداد.
  int get activeItems => items.where((i) => i.active).length;

  /// مسار الموقع: المبنى / الطابق / الغرفة.
  String locationPath(String? id) {
    final parts = <String>[];
    var cur = location(id);
    var guard = 0;
    while (cur != null && guard++ < 8) {
      parts.insert(0, cur.name);
      cur = location(cur.parentId);
    }
    return parts.join(' / ');
  }

  /// مسار الإدارة: الإدارة / القسم.
  String departmentPath(String? id) {
    final parts = <String>[];
    var cur = department(id);
    var guard = 0;
    while (cur != null && guard++ < 8) {
      parts.insert(0, cur.name);
      cur = department(cur.parentId);
    }
    return parts.join(' / ');
  }

  /// المستلم أو المُرجِع في مستند صرف أو مرتجع: الموظف ثم إدارته، أو الإدارة وحدها.
  String recipientOf(StDoc d) {
    final e = employee(d.employeeId);
    final dep = department(d.departmentId)?.name ?? '';
    if (e != null) return dep.isEmpty ? e.fullName : '${e.fullName} — $dep';
    return dep;
  }

  /// مستندات الموظف (ما صُرف له أو أرجعه)، الأحدث أولاً.
  List<StDoc> docsOfEmployee(String employeeId) {
    final l = [for (final d in docs) if (d.employeeId == employeeId) d];
    l.sort((a, b) => (b.postedAt ?? b.createdAt ?? DateTime(2000)).compareTo(a.postedAt ?? a.createdAt ?? DateTime(2000)));
    return l;
  }

  /// الكميات الخارجة لمستند لكل مخزن وصنف (بالوحدة الأساسية)، كما يحجزها الاعتماد (st_doc_outgoing):
  /// الصرف والتحويل كل بنودهما، والتسوية بنودها السالبة. والعكسي يُحسب في قاعدة البيانات من حركات أصله.
  Map<(String, String), double> outgoingOf(StDoc d) {
    final out = <(String, String), double>{};
    if (d.isReversal) return out;
    for (final l in linesOf(d.id)) {
      final q = l.baseQty;
      final take = d.kind == 'issue' || d.kind == 'transfer' || (d.kind == 'adjust' && q < 0);
      if (!take) continue;
      final k = (d.warehouseId, l.itemId);
      out[k] = roundQty((out[k] ?? 0) + q.abs());
    }
    return out;
  }

  /// نقص المتاح لاعتماد مستند: لكل صنف لا يكفي متاحه (مع الأخذ بأن المستند المعتمد حجز كميته سلفاً).
  List<(StItem, double, double)> shortages(StDoc d) {
    final res = <(StItem, double, double)>[];
    for (final e in outgoingOf(d).entries) {
      final it = item(e.key.$2);
      if (it == null) continue;
      final avail = available(it.id, warehouseId: e.key.$1);
      if (avail < e.value) res.add((it, avail, e.value));
    }
    return res;
  }

  /// أصناف يمس صرفها الاحتياطي الحرج (المتاح بعد الصرف دون الاحتياطي): تحتاج استثناء عند الاعتماد.
  List<(StItem, double, double)> criticalTouches(StDoc d) {
    if (d.kind != 'issue' && d.kind != 'transfer') return const [];
    final res = <(StItem, double, double)>[];
    for (final e in outgoingOf(d).entries) {
      final it = item(e.key.$2);
      if (it == null || it.criticalQty <= 0) continue;
      final avail = available(it.id, warehouseId: e.key.$1);
      if (avail >= e.value && avail - e.value < it.criticalQty) res.add((it, avail, e.value));
    }
    return res;
  }
}

// ---------------------------------------------------------------------
// الاستيراد من الملفات: مطابقة الأعمدة بأسمائها، وقراءة الأرقام والتواريخ
// ---------------------------------------------------------------------

/// أسماء الأعمدة المقبولة لكل حقل (تُطبَّع الهمزات والتاء المربوطة والمسافات).
const Map<String, List<String>> employeeImportColumns = {
  'emp_no': ['الرقم الوظيفي', 'رقم الموظف', 'الرقم', 'emp_no', 'employee no', 'id'],
  'full_name': ['الاسم', 'اسم الموظف', 'الاسم الكامل', 'الاسم الرباعي', 'full_name', 'name'],
  'department': ['الإدارة', 'الادارة', 'القسم', 'الإدارة أو القسم', 'department'],
  'job_title': ['الوظيفة', 'المسمى الوظيفي', 'المسمى', 'job_title', 'title'],
  'phone': ['الهاتف', 'رقم الهاتف', 'الجوال', 'phone', 'mobile'],
  'email': ['البريد', 'البريد الإلكتروني', 'email', 'e-mail'],
};

const Map<String, List<String>> itemImportColumns = {
  'code': ['الرمز', 'رمز الصنف', 'رقم الصنف', 'كود', 'code'],
  'name': ['الاسم', 'اسم الصنف', 'الصنف', 'البيان', 'name', 'item'],
  'category': ['التصنيف', 'الفئة', 'category'],
  'unit': ['الوحدة', 'وحدة القياس', 'unit'],
  'min_qty': ['الحد الأدنى', 'حد أدنى', 'min'],
  'max_qty': ['الحد الأقصى', 'حد أقصى', 'max'],
  'reorder_qty': ['نقطة إعادة الطلب', 'إعادة الطلب', 'reorder'],
  'critical_qty': ['الاحتياطي الحرج', 'الاحتياطي', 'critical'],
  'barcode': ['الباركود', 'باركود', 'barcode'],
  'description': ['الوصف', 'description'],
};

const Map<String, List<String>> openingImportColumns = {
  'item': ['الرمز', 'رمز الصنف', 'رقم الصنف', 'الصنف', 'اسم الصنف', 'الباركود', 'code', 'item'],
  'qty': ['الكمية', 'الرصيد', 'qty', 'quantity'],
  'unit': ['الوحدة', 'unit'],
  'expiry_date': ['تاريخ الانتهاء', 'تاريخ انتهاء الصلاحية', 'الصلاحية', 'expiry'],
  'batch_no': ['رقم الدفعة', 'الدفعة', 'التشغيلة', 'batch'],
};

String _hdr(String s) => normalizeArabic(s).replaceAll(RegExp(r'[\s_\-:*]+'), ' ').trim();

/// يطابق صف العناوين بالحقول: الحقل ← رقم العمود. يُبحث عن العناوين في أول 10 صفوف غير فارغة.
({int headerRow, Map<String, int> columns}) mapImportColumns(List<List<String>> rows, Map<String, List<String>> spec) {
  var best = (headerRow: -1, columns: <String, int>{});
  for (var r = 0; r < rows.length && r < 10; r++) {
    final cells = [for (final c in rows[r]) _hdr(c)];
    final found = <String, int>{};
    for (final f in spec.entries) {
      final names = [for (final n in f.value) _hdr(n)];
      // المطابقة التامة أولاً، ثم العنوان الذي يبدأ بأحد الأسماء
      var i = cells.indexWhere((c) => c.isNotEmpty && names.contains(c));
      if (i < 0) i = cells.indexWhere((c) => c.isNotEmpty && names.any((n) => c.startsWith(n)));
      if (i >= 0 && !found.containsValue(i)) found[f.key] = i;
    }
    if (found.length > best.columns.length) best = (headerRow: r, columns: found);
  }
  return best;
}

/// رقم من خلية: يقبل الأرقام العربية والفواصل، والفراغ null.
double? parseImportNumber(String raw) {
  final b = StringBuffer();
  for (final r in raw.trim().runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B) {
      b.write('.');
    } else if (r == 0x066C || r == 0x2C || r == 0x20 || r == 0xA0) {
      continue;
    } else {
      b.writeCharCode(r);
    }
  }
  final s = b.toString();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// تاريخ من خلية: 2026-12-31 أو 31/12/2026 أو رقم تاريخ Excel التسلسلي.
DateTime? parseImportDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
  if (iso != null) {
    return _validDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
  }
  final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(s);
  if (dmy != null) {
    return _validDate(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
  }
  final serial = double.tryParse(s);
  if (serial != null && serial > 20000 && serial < 80000) {
    // رقم Excel التسلسلي: الأيام منذ 1899-12-30
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
    return DateTime(d.year, d.month, d.day);
  }
  return null;
}

DateTime? _validDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2200) return null;
  final x = DateTime(y, m, d);
  return x.month == m ? x : null;
}

/// صف مستورد: قيم حقوله، وملاحظة إن كان فيه ما يمنع حفظه.
class ImportRow {
  const ImportRow(this.number, this.values, this.issue);

  /// رقم الصف في الملف (من 1).
  final int number;
  final Map<String, String> values;
  final String? issue;

  bool get ok => issue == null;
}

/// يقرأ صفوف البيانات تحت صف العناوين، ويتجاوز الفارغة، ويتحقق من الحقول المطلوبة والرقمية.
List<ImportRow> readImportRows(List<List<String>> rows, ({int headerRow, Map<String, int> columns}) map,
    {List<String> required = const [], List<String> numeric = const []}) {
  final out = <ImportRow>[];
  for (var r = map.headerRow + 1; r < rows.length; r++) {
    final row = rows[r];
    final v = <String, String>{
      for (final e in map.columns.entries) e.key: e.value < row.length ? row[e.value].trim() : '',
    };
    if (v.values.every((x) => x.isEmpty)) continue;
    String? issue;
    for (final f in required) {
      if ((v[f] ?? '').isEmpty) {
        issue = 'حقل مطلوب فارغ';
        break;
      }
    }
    if (issue == null) {
      for (final f in numeric) {
        final x = v[f] ?? '';
        if (x.isNotEmpty && (parseImportNumber(x) == null || parseImportNumber(x)! < 0)) {
          issue = 'رقم غير صالح';
          break;
        }
      }
    }
    out.add(ImportRow(r + 1, v, issue));
  }
  return out;
}
