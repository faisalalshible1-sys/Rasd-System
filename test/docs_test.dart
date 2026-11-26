import 'package:dc_app/docs.dart';
import 'package:dc_app/services/doc_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('المستند: القراءة والمراسلة المتأخرة', () {
    final l = DocItem.fromMap({
      'id': 'a',
      'kind': 'letter',
      'title': 'طلب تمديد',
      'direction': 'in',
      'status': 'open',
      'due_date': '2026-11-10',
      'category': 'contract',
    });
    expect(l.overdue(DateTime(2026, 11, 11)), isTrue);
    expect(l.overdue(DateTime(2026, 11, 10)), isFalse);
    expect(l.statusLabel, 'بانتظار رد');
    expect(l.categoryLabel, 'تعاقدية');
    expect(l.toJson()['due_date'], '2026-11-10');
    final b = DocItem.fromMap({'id': 'b', 'kind': 'boq', 'title': 'مقايسة', 'status': 'approved', 'amount': '125000.5', 'category': 'estimate'});
    expect(b.amount, 125000.5);
    expect(b.overdue(DateTime(2030)), isFalse);
    expect(b.statusLabel, 'معتمد');
  });

  test('مسار التطوير: الترتيب والملفات الحالية وصور كل الإصدارات', () {
    final idx = DocIndex(
      items: [DocItem.fromMap({'id': 'd', 'kind': 'design', 'title': 'واجهة', 'category': 'heritage'})],
      revisions: [
        DocRevision.fromMap({'id': 'r3', 'item_id': 'd', 'rev_no': 3}),
        DocRevision.fromMap({'id': 'r1', 'item_id': 'd', 'rev_no': 1}),
        DocRevision.fromMap({'id': 'r2', 'item_id': 'd', 'rev_no': 2}),
      ],
      files: [
        DocFile.fromMap({'id': 'f2', 'revision_id': 'r2', 'path': 'doc/r2/b.png', 'name': 'b.png', 'mime': 'image/png', 'sort': 1, 'size_bytes': 10}),
        DocFile.fromMap({'id': 'f1', 'revision_id': 'r1', 'path': 'doc/r1/a.jpg', 'name': 'a.jpg', 'mime': 'image/jpeg', 'sort': 2, 'size_bytes': 5}),
        DocFile.fromMap({'id': 'f0', 'revision_id': 'r1', 'path': 'doc/r1/0.pdf', 'name': '0.pdf', 'mime': 'application/pdf', 'sort': 1}),
      ],
      reports: const [],
    );
    expect(idx.revisionsOf('d').map((r) => r.revNo), [1, 2, 3]);
    expect(idx.latest('d')!.revNo, 3);
    // الإصدار 3 بلا ملفات: الملفات الحالية من الإصدار 2
    expect(idx.currentFiles('d').map((f) => f.id), ['f2']);
    expect(idx.imagesAcrossRevisions('d').map((x) => '${x.$1.revNo}:${x.$2.id}'), ['1:f1', '2:f2']);
    expect(idx.filesOfRevision('r1').map((f) => f.id), ['f0', 'f1']);
    expect(idx.totalBytes, 15);
  });

  test('التقرير اليومي وتغطيته', () {
    final r = SiteReport.fromMap({
      'id': 'x',
      'project_id': 'p',
      'report_date': '2026-11-13',
      'weather': 'dust',
      'workers': 24,
      'works_done': 'حفر',
      'issues': 'تأخر توريد',
      'progress_pct': 35,
    });
    expect(r.adverseWeather, isTrue);
    expect(r.hasIssues, isTrue);
    expect(r.reviewed, isFalse);
    expect(r.toJson()['report_date'], '2026-11-13');
    final r2 = SiteReport.fromMap({'id': 'y', 'project_id': 'p', 'report_date': '2026-11-11', 'works_done': 'x'});
    expect(reportCoverage([r, r2], DateTime(2026, 11, 14), 4), [true, false, true, false]);
  });

  test('مسارات الحاوية تطابق شرط قاعدة البيانات', () {
    final re = RegExp(r'^(doc|report)/[0-9a-f-]{36}/[A-Za-z0-9_-]{8,64}\.(pdf|jpg|jpeg|png|webp|gif)$');
    const owner = '3f2a9c1e-0b7d-4c55-9a1e-2b3c4d5e6f70';
    for (final ext in ['pdf', 'jpg', 'png', 'webp', 'gif']) {
      expect(re.hasMatch(newDocPath('doc', owner, ext)), isTrue);
      expect(re.hasMatch(newDocPath('report', owner, ext)), isTrue);
    }
    expect(newDocPath('doc', owner, 'pdf'), isNot(newDocPath('doc', owner, 'pdf')));
    expect(mimeOfExt('pdf'), 'application/pdf');
    expect(extOf('مخطط.نهائي.PNG'), 'png');
  });

  test('الأحجام المقروءة', () {
    expect(fmtBytes(512), '512 بايت');
    expect(fmtBytes(250000), '244 ك.ب');
    expect(fmtBytes(5 * 1024 * 1024), '5.0 م.ب');
    expect(fmtBytes(null), '—');
  });

  test('ملف العقد: التصنيفات والترتيب وقرار التكليف بالمهندس (الترحيل 35)', () {
    final idx = DocIndex(
      items: [
        DocItem.fromMap({'id': 'o', 'kind': 'attachment', 'project_id': 'p', 'title': 'صور', 'category': 'other', 'doc_date': '2026-11-01'}),
        DocItem.fromMap({'id': 'c1', 'kind': 'attachment', 'project_id': 'p', 'title': 'العقد', 'category': 'contract', 'doc_date': '2026-10-01'}),
        DocItem.fromMap({'id': 'c2', 'kind': 'attachment', 'project_id': 'p', 'title': 'ملحق', 'category': 'contract', 'doc_date': '2026-11-20'}),
        DocItem.fromMap({
          'id': 'a', 'kind': 'attachment', 'project_id': 'p', 'title': 'قرار', 'category': 'assignment', 'engineer_id': 'e1', //
          'doc_date': '2026-11-05', 'status': 'active',
        }),
        DocItem.fromMap({'id': 'x', 'kind': 'attachment', 'project_id': 'q', 'title': 'عقد آخر', 'category': 'contract'}),
        DocItem.fromMap({'id': 'l', 'kind': 'letter', 'project_id': 'p', 'title': 'مراسلة', 'direction': 'in'}),
      ],
      revisions: const [],
      files: const [],
      reports: const [],
    );
    expect(idx.attachmentsOf('p').map((i) => i.id), ['c2', 'c1', 'a', 'o'], reason: 'بترتيب التصنيفات ثم الأحدث، دون مستندات الشؤون الفنية');
    expect(idx.ofKind('letter').length, 1);
    final a = idx.assignmentOf('e1')!;
    expect(a.id, 'a');
    expect(a.isAttachment, isTrue);
    expect(a.categoryLabel, 'قرارات التكليف');
    expect(a.statusLabel, 'نافذ');
    expect(a.toJson()['engineer_id'], 'e1');
    expect(idx.assignmentOf('e2'), isNull);
    expect(DocItem.fromMap({'id': 'b', 'kind': 'boq', 'title': 'م'}).toJson().containsKey('engineer_id'), isFalse);
    for (final c in attachmentCategories) {
      expect(attachmentCategoryLabels[c], isNotNull);
    }
    expect(attachmentCategories.length, 9);
  });

  test('أنواع مرفقات العقد: الامتداد يحدد النوع كما في attachment_mime()', () {
    const expected = {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'png': 'image/png',
      'heic': 'image/heic',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'dwg': 'image/vnd.dwg',
      'dxf': 'image/vnd.dxf',
      'rvt': 'application/vnd.autodesk.revit',
      'zip': 'application/zip',
      'kmz': 'application/vnd.google-earth.kmz',
    };
    expected.forEach((ext, mime) => expect(mimeOfExt(ext), mime, reason: ext));
    expect(attachmentExts, containsAll(expected.keys));
    expect(attachmentExts, isNot(contains('exe')));
    expect(attachmentExts, isNot(contains('mp4')));
    expect(maxAttachmentBytes, 50 * 1024 * 1024);
    // ملفات الرسم لا تُعرض صوراً، والصور العادية تُعرض
    final dwg = DocFile.fromMap({'id': '1', 'path': 'doc/x/a.dwg', 'name': 'a.dwg', 'mime': 'image/vnd.dwg'});
    expect(dwg.isImage, isFalse);
    expect(dwg.isCad, isTrue);
    expect(dwg.typeLabel, 'DWG');
    expect(DocFile.fromMap({'id': '2', 'path': 'p', 'name': 'a.png', 'mime': 'image/png'}).isImage, isTrue);
    expect(DocFile.fromMap({'id': '3', 'path': 'p', 'name': 'a.heic', 'mime': 'image/heic'}).isImage, isFalse);
    expect(fileTypeLabel('application/vnd.ms-excel'), 'Excel');
    expect(fileTypeLabel('application/msword'), 'Word');
    expect(isolate('DWG-12'), '\u2068DWG-12\u2069');
    expect(isolate(''), '');
  });
}
