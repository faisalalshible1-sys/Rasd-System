// تشغيل الاستخراج: بناء الملف بالصيغة المطلوبة، ثم حفظه أو فتحه للطباعة، وتسجيله في التدقيق.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
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

/// اسم الملف: العنوان وتاريخ اليوم.
String exportFileName(ExportTable t, PrintConfig c, PrintContext ctx) => '${titleOf(t, c)} ${fmtDateBy(ctx.at, 'ymd').replaceAll('/', '-')}';

/// يبني الملف ثم يحفظه ([print] = false) أو يفتحه للطباعة ([print] = true)، مع نافذة انتظار ورسالة بالنتيجة.
Future<void> runExport(BuildContext context, ExportTable table, PrintConfig config, ExportFormat format, {bool print = false}) async {
  final app = AppScope.read(context);
  final ctx = printContextOf(app);
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
