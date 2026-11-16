// =====================================================================
// «المستندات الفنية» (المقايسات، المراسلات، التصاميم) و«الإشراف» (التقارير اليومية):
// النماذج والتسميات وأدوات التجميع. الحساب والعرض فقط؛ الصلاحيات الفعلية في قاعدة البيانات.
// =====================================================================

DateTime? _day(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime? _ts(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
String _s(Object? v) => v == null ? '' : v.toString();
int? _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v));
double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse(_s(v));

String _iso(DateTime? d) =>
    d == null ? '' : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------
// التسميات
// ---------------------------------------------------------------------
const List<String> docKinds = ['boq', 'letter', 'design'];
const Map<String, String> docKindLabels = {'boq': 'المقايسات', 'letter': 'المراسلات', 'design': 'التصاميم'};
const Map<String, String> docKindSingle = {'boq': 'مقايسة', 'letter': 'مراسلة', 'design': 'تصميم'};

const List<String> boqCategories = ['estimate', 'contract', 'variation', 'final'];
const Map<String, String> boqCategoryLabels = {
  'estimate': 'تقديرية',
  'contract': 'تعاقدية',
  'variation': 'تعديلية (أمر تغيير)',
  'final': 'ختامية',
};

const List<String> letterCategories = ['contract', 'finance', 'technical', 'admin', 'other'];
const Map<String, String> letterCategoryLabels = {
  '': 'دون تصنيف',
  'contract': 'تعاقدية',
  'finance': 'مالية',
  'technical': 'فنية',
  'admin': 'إدارية',
  'other': 'أخرى',
};

const List<String> designCategories = [
  'architectural', 'structural', 'electrical', 'mechanical', 'plumbing', 'landscape', 'urban', 'heritage', 'other',
];
const Map<String, String> designCategoryLabels = {
  'architectural': 'معماري',
  'structural': 'إنشائي',
  'electrical': 'كهربائي',
  'mechanical': 'ميكانيكي',
  'plumbing': 'صحي',
  'landscape': 'تنسيق مواقع',
  'urban': 'تخطيط عمراني',
  'heritage': 'تراثي وترميم',
  'other': 'أخرى',
};

const List<String> docStatuses = ['draft', 'review', 'approved'];
const Map<String, String> docStatusLabels = {'draft': 'مسودة', 'review': 'قيد المراجعة', 'approved': 'معتمد'};
const List<String> letterStatuses = ['open', 'closed', 'info'];
const Map<String, String> letterStatusLabels = {'open': 'بانتظار رد', 'closed': 'أُغلقت', 'info': 'للعلم'};
const List<String> letterDirections = ['in', 'out', 'internal'];
const Map<String, String> letterDirectionLabels = {'in': 'وارد', 'out': 'صادر', 'internal': 'داخلي'};

const List<String> weatherKinds = ['clear', 'cloudy', 'rain', 'wind', 'dust', 'hot', 'cold'];
const Map<String, String> weatherLabels = {
  'clear': 'صحو',
  'cloudy': 'غائم',
  'rain': 'ممطر',
  'wind': 'رياح',
  'dust': 'غبار',
  'hot': 'حار',
  'cold': 'بارد',
};

/// الطقس الذي قد يعطّل العمل في الموقع (يظهر بلون التنبيه).
const Set<String> weatherAdverse = {'rain', 'wind', 'dust'};

String docCategoryLabel(String kind, String c) => switch (kind) {
      'boq' => boqCategoryLabels[c] ?? c,
      'letter' => letterCategoryLabels[c] ?? c,
      _ => designCategoryLabels[c] ?? c,
    };

String docStatusLabel(String kind, String s) => kind == 'letter' ? (letterStatusLabels[s] ?? s) : (docStatusLabels[s] ?? s);

/// حجم ملف مقروء: 850 ك.ب، 2.4 م.ب.
String fmtBytes(num? b) {
  if (b == null) return '—';
  if (b < 1024) return '$b بايت';
  if (b < 1024 * 1024) return '${(b / 1024).round()} ك.ب';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} ج.ب';
}

// ---------------------------------------------------------------------
// النماذج
// ---------------------------------------------------------------------
class DocItem {
  const DocItem({
    required this.id,
    required this.kind,
    this.projectId,
    this.originProject,
    required this.title,
    this.refNo = '',
    this.docDate,
    this.category = '',
    this.direction,
    this.party = '',
    this.amount,
    this.status = 'draft',
    this.replyTo,
    this.dueDate,
    this.notes = '',
    this.createdAt,
    this.createdBy,
    this.updatedAt,
  });

  final String id;
  final String kind;
  final String? projectId;
  final String? originProject;
  final String title;
  final String refNo;
  final DateTime? docDate;
  final String category;
  final String? direction;
  final String party;
  final double? amount;
  final String status;
  final String? replyTo;
  final DateTime? dueDate;
  final String notes;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;

  factory DocItem.fromMap(Map<String, dynamic> m) => DocItem(
        id: _s(m['id']),
        kind: _s(m['kind']),
        projectId: m['project_id'] as String?,
        originProject: m['origin_project'] as String?,
        title: _s(m['title']),
        refNo: _s(m['ref_no']),
        docDate: _day(m['doc_date']),
        category: _s(m['category']),
        direction: m['direction'] as String?,
        party: _s(m['party']),
        amount: _d(m['amount']),
        status: _s(m['status']).isEmpty ? 'draft' : _s(m['status']),
        replyTo: m['reply_to'] as String?,
        dueDate: _day(m['due_date']),
        notes: _s(m['notes']),
        createdAt: _ts(m['created_at']),
        createdBy: m['created_by'] as String?,
        updatedAt: _ts(m['updated_at']),
      );

  /// القيم كما تُرسل إلى save_doc_item (لنموذج التعديل).
  Map<String, dynamic> toJson() => {
        'project_id': projectId ?? '',
        'title': title,
        'ref_no': refNo,
        'doc_date': _iso(docDate),
        'category': category,
        'direction': direction ?? '',
        'party': party,
        'amount': amount,
        'status': status,
        'reply_to': replyTo ?? '',
        'due_date': _iso(dueDate),
        'notes': notes,
      };

  bool get isLetter => kind == 'letter';

  /// مراسلة واردة بانتظار رد تجاوزت موعد الرد.
  bool overdue(DateTime today) => isLetter && status == 'open' && dueDate != null && dueDate!.isBefore(today);

  String get categoryLabel => docCategoryLabel(kind, category);
  String get statusLabel => docStatusLabel(kind, status);
}

class DocRevision {
  const DocRevision({required this.id, required this.itemId, required this.revNo, this.revDate, this.note = '', this.createdAt, this.createdBy});

  final String id;
  final String itemId;
  final int revNo;
  final DateTime? revDate;
  final String note;
  final DateTime? createdAt;
  final String? createdBy;

  factory DocRevision.fromMap(Map<String, dynamic> m) => DocRevision(
        id: _s(m['id']),
        itemId: _s(m['item_id']),
        revNo: _i(m['rev_no']) ?? 1,
        revDate: _day(m['rev_date']),
        note: _s(m['note']),
        createdAt: _ts(m['created_at']),
        createdBy: m['created_by'] as String?,
      );

  String get label => 'الإصدار $revNo';
}

class DocFile {
  const DocFile({
    required this.id,
    this.revisionId,
    this.reportId,
    this.recordId,
    required this.path,
    required this.name,
    required this.mime,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.sort = 0,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String? revisionId;
  final String? reportId;

  /// سجل من سجلات الوحدات (الترحيل 21).
  final String? recordId;
  final String path;
  final String name;
  final String mime;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int sort;
  final DateTime? createdAt;
  final String? createdBy;

  factory DocFile.fromMap(Map<String, dynamic> m) => DocFile(
        id: _s(m['id']),
        revisionId: m['revision_id'] as String?,
        reportId: m['report_id'] as String?,
        recordId: m['record_id'] as String?,
        path: _s(m['path']),
        name: _s(m['name']),
        mime: _s(m['mime']),
        sizeBytes: _i(m['size_bytes']) ?? 0,
        width: _i(m['width']),
        height: _i(m['height']),
        sort: _i(m['sort']) ?? 0,
        createdAt: _ts(m['created_at']),
        createdBy: m['created_by'] as String?,
      );

  bool get isImage => mime.startsWith('image/');
  bool get isVideo => mime.startsWith('video/');
  bool get isPdf => mime == 'application/pdf';
}

class SiteReport {
  const SiteReport({
    required this.id,
    required this.projectId,
    this.originProject,
    this.workId,
    required this.reportDate,
    this.weather = 'clear',
    this.tempC,
    this.workers,
    this.equipment = '',
    this.worksDone = '',
    this.materials = '',
    this.issues = '',
    this.safety = '',
    this.nextPlan = '',
    this.progressPct,
    this.notes = '',
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote = '',
    this.createdAt,
    this.createdBy,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String? originProject;
  final String? workId;
  final DateTime reportDate;
  final String weather;
  final int? tempC;
  final int? workers;
  final String equipment;
  final String worksDone;
  final String materials;
  final String issues;
  final String safety;
  final String nextPlan;

  /// نسبة الإنجاز التقديرية من 0 إلى 100 كما يقدّرها المشرف.
  final double? progressPct;
  final String notes;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String reviewNote;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;

  factory SiteReport.fromMap(Map<String, dynamic> m) => SiteReport(
        id: _s(m['id']),
        projectId: _s(m['project_id']),
        originProject: m['origin_project'] as String?,
        workId: m['work_id'] as String?,
        reportDate: _day(m['report_date']) ?? DateTime(2000),
        weather: _s(m['weather']).isEmpty ? 'clear' : _s(m['weather']),
        tempC: _i(m['temp_c']),
        workers: _i(m['workers']),
        equipment: _s(m['equipment']),
        worksDone: _s(m['works_done']),
        materials: _s(m['materials']),
        issues: _s(m['issues']),
        safety: _s(m['safety']),
        nextPlan: _s(m['next_plan']),
        progressPct: _d(m['progress_pct']),
        notes: _s(m['notes']),
        reviewedBy: m['reviewed_by'] as String?,
        reviewedAt: _ts(m['reviewed_at']),
        reviewNote: _s(m['review_note']),
        createdAt: _ts(m['created_at']),
        createdBy: m['created_by'] as String?,
        updatedAt: _ts(m['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'work_id': workId ?? '',
        'report_date': _iso(reportDate),
        'weather': weather,
        'temp_c': tempC,
        'workers': workers,
        'equipment': equipment,
        'works_done': worksDone,
        'materials': materials,
        'issues': issues,
        'safety': safety,
        'next_plan': nextPlan,
        'progress_pct': progressPct,
        'notes': notes,
      };

  bool get reviewed => reviewedAt != null;
  bool get hasIssues => issues.trim().isNotEmpty;
  bool get adverseWeather => weatherAdverse.contains(weather);
}

/// فهرس المستندات والتقارير وملفاتها (يُبنى مرة عند كل تحميل).
class DocIndex {
  DocIndex({required this.items, required this.revisions, required this.files, required this.reports}) {
    for (final r in revisions) {
      (_revBy[r.itemId] ??= []).add(r);
    }
    for (final l in _revBy.values) {
      l.sort((a, b) => a.revNo.compareTo(b.revNo));
    }
    for (final f in files) {
      if (f.revisionId != null) (_filesByRev[f.revisionId!] ??= []).add(f);
      if (f.reportId != null) (_filesByRep[f.reportId!] ??= []).add(f);
      if (f.recordId != null) (_filesByRec[f.recordId!] ??= []).add(f);
    }
    for (final l in [..._filesByRev.values, ..._filesByRep.values, ..._filesByRec.values]) {
      l.sort((a, b) => a.sort.compareTo(b.sort));
    }
  }

  DocIndex.empty() : this(items: const [], revisions: const [], files: const [], reports: const []);

  final List<DocItem> items;
  final List<DocRevision> revisions;
  final List<DocFile> files;
  final List<SiteReport> reports;
  final Map<String, List<DocRevision>> _revBy = {};
  final Map<String, List<DocFile>> _filesByRev = {};
  final Map<String, List<DocFile>> _filesByRep = {};
  final Map<String, List<DocFile>> _filesByRec = {};

  List<DocItem> ofKind(String kind) => items.where((i) => i.kind == kind).toList();

  /// الإصدارات من الأقدم إلى الأحدث (مسار التطوير).
  List<DocRevision> revisionsOf(String itemId) => _revBy[itemId] ?? const [];
  DocRevision? latest(String itemId) {
    final l = revisionsOf(itemId);
    return l.isEmpty ? null : l.last;
  }

  List<DocFile> filesOfRevision(String revisionId) => _filesByRev[revisionId] ?? const [];
  List<DocFile> filesOfReport(String reportId) => _filesByRep[reportId] ?? const [];
  List<DocFile> filesOfRecord(String recordId) => _filesByRec[recordId] ?? const [];

  /// ملفات أحدث إصدار، وإن خلا من الملفات فأحدث إصدار فيه ملفات.
  List<DocFile> currentFiles(String itemId) {
    for (final r in revisionsOf(itemId).reversed) {
      final f = filesOfRevision(r.id);
      if (f.isNotEmpty) return f;
    }
    return const [];
  }

  /// صور كل الإصدارات بالترتيب (للعرض المتحرك لمسار التطوير).
  List<(DocRevision, DocFile)> imagesAcrossRevisions(String itemId) => [
        for (final r in revisionsOf(itemId))
          for (final f in filesOfRevision(r.id))
            if (f.isImage) (r, f),
      ];

  List<DocItem> itemsOfProject(String projectId) => items.where((i) => i.projectId == projectId).toList();
  List<SiteReport> reportsOfProject(String projectId) =>
      reports.where((r) => r.projectId == projectId).toList()..sort((a, b) => b.reportDate.compareTo(a.reportDate));

  /// الردود المرتبطة بمراسلة.
  List<DocItem> repliesTo(String itemId) => items.where((i) => i.replyTo == itemId).toList();

  int get totalBytes => files.fold(0, (s, f) => s + f.sizeBytes);
}

/// تغطية التقارير اليومية: لكل يوم من [days] الأخيرة حتى [today]، هل يوجد تقرير للعقد؟
List<bool> reportCoverage(List<SiteReport> reports, DateTime today, int days) {
  final have = {for (final r in reports) _iso(r.reportDate)};
  return [
    for (var i = days - 1; i >= 0; i--) have.contains(_iso(DateTime(today.year, today.month, today.day - i))),
  ];
}
