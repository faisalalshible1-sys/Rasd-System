// =====================================================================
// لائحة الأسعار الاسترشادية والمقايسات المعدّة منها (الترحيلان 27 و28).
// اللائحة تُقرأ عند الحاجة (بحث برقم البند أو بكلمات، أو تصفّح الفصول والعناوين)،
// والمقايسة تحفظ بنودها بلقطة من اللائحة (الوصف الكامل والوحدة والسعر) مع الكمية والملاحظات.
// =====================================================================

String _str(dynamic v) => v == null ? '' : v.toString();
double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

class PriceChapter {
  const PriceChapter(this.key, this.name);

  final String key;
  final String name;
}

class PriceList {
  const PriceList({
    required this.id,
    required this.title,
    required this.year,
    this.source = '',
    this.chapters = const [],
    this.currency = 'دينار',
    this.active = true,
  });

  final String id;
  final String title;
  final int year;
  final String source;
  final List<PriceChapter> chapters;
  final String currency;
  final bool active;

  factory PriceList.fromMap(Map<String, dynamic> m) => PriceList(
        id: _str(m['id']),
        title: _str(m['title']),
        year: _int(m['year']) ?? 0,
        source: _str(m['source']),
        chapters: [
          if (m['chapters'] is List)
            for (final c in m['chapters'] as List)
              if (c is Map) PriceChapter(_str(c['key']), _str(c['name'])),
        ],
        currency: _str(m['currency']).isEmpty ? 'دينار' : _str(m['currency']),
        active: m['active'] != false,
      );

  String chapterName(String key) {
    for (final c in chapters) {
      if (c.key == key) return c.name;
    }
    return key;
  }
}

/// صف في اللائحة: عنوان، أو بند مسعّر، أو ملاحظة.
class PriceItem {
  const PriceItem({
    required this.listId,
    required this.seq,
    required this.chapter,
    this.code = '',
    this.parentSeq,
    required this.kind,
    required this.description,
    this.unit = '',
    this.unitInferred = false,
    this.price,
    this.section = '',
    this.group = '',
    this.fullDesc = '',
  });

  final String listId;
  final int seq;
  final String chapter;
  final String code;
  final int? parentSeq;

  /// heading · item · note
  final String kind;
  final String description;
  final String unit;

  /// الوحدة فارغة في اللائحة واستُنتجت من البنود الشقيقة.
  final bool unitInferred;
  final double? price;

  /// القسم (البند الأم الأعلى) ومجموعة الأعمال، والوصف الكامل بسياق البنود الأم.
  final String section;
  final String group;
  final String fullDesc;

  bool get isItem => kind == 'item';
  bool get isHeading => kind == 'heading';

  factory PriceItem.fromMap(Map<String, dynamic> m) => PriceItem(
        listId: _str(m['list_id']),
        seq: _int(m['seq']) ?? 0,
        chapter: _str(m['chapter']),
        code: _str(m['code']),
        parentSeq: _int(m['parent_seq']),
        kind: _str(m['kind']),
        description: _str(m['description']),
        unit: _str(m['unit']),
        unitInferred: m['unit_inferred'] == true,
        price: _num(m['price']),
        section: _str(m['section']),
        group: _str(m['grp']),
        fullDesc: _str(m['full_desc']).isEmpty ? _str(m['description']) : _str(m['full_desc']),
      );
}

/// سطر في مقايسة: من اللائحة (seq) أو بند حر.
class BoqLine {
  BoqLine({
    this.seq,
    this.chapter = '',
    this.code = '',
    required this.desc,
    this.unit = '',
    this.price,
    this.qty,
    this.notes = '',
    this.sheetId = '',
    this.projectId,
    this.no = 0,
  });

  final int? seq;
  final String chapter;
  final String code;
  String desc;
  String unit;
  double? price;
  double? qty;
  String notes;

  /// للتصدير: المقايسة التي ينتمي إليها السطر وعقدها ورقمه فيها.
  final String sheetId;
  final String? projectId;
  final int no;

  bool get fromList => seq != null;
  double? get total => price == null ? null : (qty ?? 0) * price!;

  factory BoqLine.fromMap(Map<String, dynamic> m, {String sheetId = '', String? projectId, int no = 0}) => BoqLine(
        seq: _int(m['seq']),
        chapter: _str(m['chapter']),
        code: _str(m['code']),
        desc: _str(m['desc']),
        unit: _str(m['unit']),
        price: _num(m['price']),
        qty: _num(m['qty']),
        notes: _str(m['notes']),
        sheetId: sheetId,
        projectId: projectId,
        no: no,
      );

  factory BoqLine.fromItem(PriceItem p) =>
      BoqLine(seq: p.seq, chapter: p.chapter, code: p.code, desc: p.fullDesc, unit: p.unit, price: p.price);

  BoqLine copy() => BoqLine(
      seq: seq, chapter: chapter, code: code, desc: desc, unit: unit, price: price, qty: qty, notes: notes, sheetId: sheetId, projectId: projectId, no: no);

  /// ما يُرسل للحفظ: بند اللائحة برقمه (والقاعدة تأخذ الوصف والوحدة والسعر من اللائحة)، والبند الحر بكامله.
  Map<String, dynamic> toJson() => seq != null
      ? {'seq': seq, 'qty': qty, 'notes': notes}
      : {'desc': desc, 'unit': unit, 'price': price, 'code': code, 'qty': qty, 'notes': notes};
}

class BoqSheet {
  const BoqSheet({
    required this.id,
    this.projectId,
    required this.listId,
    required this.title,
    this.refNo = '',
    this.notes = '',
    this.showPrices = true,
    this.lines = const [],
    this.total = 0,
    this.createdBy,
    this.updatedAt,
  });

  final String id;
  final String? projectId;
  final String listId;
  final String title;
  final String refNo;
  final String notes;
  final bool showPrices;
  final List<BoqLine> lines;
  final double total;
  final String? createdBy;
  final DateTime? updatedAt;

  factory BoqSheet.fromMap(Map<String, dynamic> m) {
    final id = _str(m['id']);
    final pid = m['project_id'] == null ? null : _str(m['project_id']);
    final raw = m['lines'] is List ? m['lines'] as List : const [];
    return BoqSheet(
      id: id,
      projectId: pid,
      listId: _str(m['list_id']),
      title: _str(m['title']),
      refNo: _str(m['ref_no']),
      notes: _str(m['notes']),
      showPrices: m['show_prices'] != false,
      lines: [
        for (var i = 0; i < raw.length; i++)
          if (raw[i] is Map) BoqLine.fromMap(Map<String, dynamic>.from(raw[i] as Map), sheetId: id, projectId: pid, no: i + 1),
      ],
      total: _num(m['total']) ?? 0,
      createdBy: m['created_by'] == null ? null : _str(m['created_by']),
      updatedAt: DateTime.tryParse(_str(m['updated_at']))?.toLocal(),
    );
  }
}

/// عمود البحث: رقم بند (مثل 7.2 أو ٧.٢) أم كلمات.
bool isPriceCode(String q) => RegExp(r'^\d+(\.\d+)*\.?$').hasMatch(q.trim().replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}'));
