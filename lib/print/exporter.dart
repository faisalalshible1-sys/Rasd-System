// تشغيل الاستخراج: بناء الملف بالصيغة المطلوبة، ثم حفظه أو فتحه للطباعة، وتسجيله في التدقيق.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../units.dart';
import '../ui/widgets.dart';
import 'docx_writer.dart';
import 'model.dart';
import 'output.dart';
import 'pdf_writer.dart';
import 'text_writers.dart';
import 'xlsx_writer.dart';

Future<Uint8List> renderExport(ExportFormat f, ExportTable t, PrintConfig c, PrintContext ctx) async {
  final Uint8List bytes = switch (f) {
    ExportFormat.pdf => await buildPdf(t, c, ctx),
    ExportFormat.docx => await buildDocx(t, c, ctx),
    ExportFormat.xlsx => buildXlsx(t, c, ctx),
    ExportFormat.csv => buildCsv(t, c),
    ExportFormat.html => await buildHtml(t, c, ctx),
    ExportFormat.json => buildJson(t, c, ctx),
  };
  return bytes;
}

PrintContext printContextOf(AppState app) => PrintContext(printedBy: app.me?.displayName ?? 'مستخدم', orgName: app.orgName);

/// قسم المصدر لرمز {SECTION} في الرقم الإشاري: cycle:finance ← cycle، وunit:ncr ← قسم وحدته.
String refSectionOf(String sourceId) {
  final i = sourceId.indexOf(':');
  final head = i < 0 ? sourceId : sourceId.substring(0, i);
  if (head == 'unit') {
    final k = unitKinds[sourceId.substring(i + 1)];
    return k == null ? 'print' : (unitSectionOf[k.unit] ?? 'print');
  }
  return switch (head) { 'media' => 'print', '' => 'print', _ => head };
}

/// سياق المعاينة: شكل الرقم الإشاري قبل صدوره (التسلسل #) إن كانت صيغة المطبوعات مفعّلة.
PrintContext previewPrintContext(AppState app, String sourceId) {
  final ctx = printContextOf(app);
  final s = app.v11Ready ? app.refScheme('print') : null;
  if (s == null || !s.active) return ctx;
  return ctx.withRef(s.masked(ctx: {'section': refSectionOf(sourceId)}));
}

/// سياق الطباعة برقم إشاري تصدره قاعدة البيانات (لا يتكرر)، وإلا الرقم التلقائي من الوقت.
Future<PrintContext> issuedPrintContext(AppState app, ExportTable table, PrintConfig config) async {
  final ctx = printContextOf(app);
  if (!config.showRef) return ctx;
  final kind = table.sourceId.startsWith('unit:') ? table.sourceId.substring(5) : '';
  final ref = await app.issueRef('print', {
    'section': refSectionOf(table.sourceId),
    'source': table.sourceId,
    'title': titleOf(table, config),
    if (kind.isNotEmpty) 'kind': kind,
  });
  return ref == null ? ctx : ctx.withRef(ref);
}

/// اسم الملف: العنوان وتاريخ اليوم.
String exportFileName(ExportTable t, PrintConfig c, PrintContext ctx) => '${titleOf(t, c)} ${fmtDateBy(ctx.at, 'ymd').replaceAll('/', '-')}';

/// يبني الملف ثم يحفظه ([print] = false) أو يفتحه للطباعة ([print] = true)، مع نافذة انتظار ورسالة بالنتيجة.
Future<void> runExport(BuildContext context, ExportTable table, PrintConfig config, ExportFormat format, {bool print = false}) async {
  final app = AppScope.read(context);
  var ctx = printContextOf(app);
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 16),
          Expanded(child: Text(print ? 'تجهيز الطباعة…' : 'تجهيز ملف ${format.label}…')),
        ]),
      ),
    ),
  );
  String? message;
  var error = false;
  try {
    ctx = await issuedPrintContext(app, table, config);
    final bytes = await renderExport(format, table, config, ctx);
    final name = exportFileName(table, config, ctx);
    if (print) {
      final r = await openBytes(bytes, name, format.ext);
      message = switch (r) {
        'opened' => 'فُتح الملف؛ اطبعه من العارض',
        'saved' => 'حُفظ الملف؛ افتحه من التنزيلات واطبعه',
        'blocked' => 'منع المتصفح فتح نافذة جديدة؛ اسمح بالنوافذ المنبثقة لهذا الموقع أو استعمل «تصدير»',
        'cancelled' => null,
        _ => 'الطباعة غير متاحة هنا؛ استعمل «تصدير»',
      };
      error = r == 'blocked' || r == 'unsupported';
    } else {
      final path = await saveBytes(bytes, name, format.ext);
      message = path == null ? null : 'حُفظ ملف ${format.label}';
    }
    await app.logExport(
      kind: print ? 'print' : 'file',
      source: table.sourceId,
      title: titleOf(table, config),
      format: format.ext,
      rows: table.rows.length,
      bytes: bytes.length,
    );
  } catch (e) {
    message = friendlyError(e);
    error = true;
  }
  if (nav.canPop()) nav.pop();
  if (message != null && context.mounted) showToast(context, message, error: error);
}
