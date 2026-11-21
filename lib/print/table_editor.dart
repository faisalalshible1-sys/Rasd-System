// تحرير البيانات قبل التصدير: تعديل أي نص أو رقم، وتسمية الأعمدة، وترتيب الصفوف بالسحب وحذفها وإضافتها.
// الأعمدة المحسوبة والمجاميع تُعاد حسابها فوراً بالمعادلات نفسها التي تُكتب في Excel، فتبقى النتائج مرتبطة بالقيم.
// التعديل هنا على الملف المستخرج وحده؛ سجلات المنظومة لا تتغير.

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'model.dart';

Future<ExportTable?> editExportTable(BuildContext context, ExportTable table) => showDialog<ExportTable>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 900), child: _TableEditor(table: table)),
      ),
    );

const _eastern = '٠١٢٣٤٥٦٧٨٩';

/// يقرأ رقماً كتبه المستخدم (بالأرقام العربية أو الهندية، وبفواصل الآلاف)، وإلا يبقى نصاً.
Object? parseCell(String text, ColType type) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (type == ColType.number || type == ColType.money || type == ColType.percent) {
    var s = t;
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(_eastern[i], '$i');
    }
    s = s.replaceAll('٬', '').replaceAll(',', '').replaceAll('٫', '.').replaceAll('%', '').replaceAll('٪', '');
    final n = num.tryParse(s);
    if (n != null) return n;
  }
  return t;
}

String _editText(Object? v) => switch (v) {
      null => '',
      DateTime d => fmtDateBy(d, 'ymd'),
      double d when d == d.roundToDouble() => d.toStringAsFixed(0),
      num n => '$n',
      bool b => b ? 'نعم' : 'لا',
      _ => v.toString(),
    };

class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.table});

  final ExportTable table;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late ExportTable _t = widget.table.recompute();
  late final _title = TextEditingController(text: widget.table.title);
  late final List<TextEditingController> _heads = [for (final c in widget.table.columns) TextEditingController(text: c.label)];
  late List<int> _ids = List.generate(_t.rows.length, (i) => i);
  int _nextId = 0;
  int _edits = 0;

  @override
  void initState() {
    super.initState();
    _nextId = _ids.length;
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in _heads) {
      c.dispose();
    }
    super.dispose();
  }

  double _w(ExportColumn c) => switch (c.type) {
        ColType.long => 260,
        ColType.date => 120,
        ColType.money => 130,
        ColType.number || ColType.percent => 100,
        _ => (c.flex * 140).clamp(120, 240).toDouble(),
      };

  void _set(int row, int col, String text) {
    final rows = [for (final r in _t.rows) [...r]];
    while (rows[row].length < _t.columns.length) {
      rows[row].add(null);
    }
    rows[row][col] = parseCell(text, _t.columns[col].type);
    _edits++;
    setState(() => _t = _t.copyWith(rows: rows).recompute());
  }

  void _addRow() {
    setState(() {
      _t = _t.copyWith(rows: [..._t.rows, List<Object?>.filled(_t.columns.length, null)]);
      _ids = [..._ids, _nextId++];
      _edits++;
    });
  }

  void _removeRow(int i) {
    setState(() {
      final rows = [..._t.rows]..removeAt(i);
      _ids = [..._ids]..removeAt(i);
      _t = _t.copyWith(rows: rows);
      _edits++;
    });
  }

  void _reorder(int a, int b) {
    if (b > a) b--;
    setState(() {
      final rows = [..._t.rows];
      rows.insert(b, rows.removeAt(a));
      _ids = [..._ids]..insert(b, _ids.removeAt(a));
      _t = _t.copyWith(rows: rows);
      _edits++;
    });
  }

  ExportTable _result() => _t.copyWith(
        title: _title.text.trim().isEmpty ? widget.table.title : _title.text.trim(),
        columns: [
          for (var j = 0; j < _t.columns.length; j++) _t.columns[j].copyWith(label: _heads[j].text.trim().isEmpty ? _t.columns[j].label : _heads[j].text.trim()),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final cols = _t.columns;
    final totalW = cols.fold<double>(0, (s, c) => s + _w(c)) + 90;
    final hasTotals = _t.hasTotals;

    Widget cellBox(double w, Widget child, {Color? color}) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(color: color, border: BorderDirectional(end: BorderSide(color: sem.rule))),
          child: child,
        );

    final header = Row(children: [
      const SizedBox(width: 90),
      for (var j = 0; j < cols.length; j++)
        cellBox(
          _w(cols[j]),
          TextField(
            controller: _heads[j],
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              prefixIcon: cols[j].computed ? Tooltip(message: 'عمود محسوب: ${cols[j].formula}', child: const Icon(Icons.functions_rounded, size: 16)) : null,
              prefixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            ),
          ),
          color: cs.primaryContainer,
        ),
    ]);

    final body = ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _t.rows.length,
      onReorder: _reorder,
      itemBuilder: (_, i) {
        final r = _t.rows[i];
        return Container(
          key: ValueKey('row-${_ids[i]}'),
          decoration: BoxDecoration(color: i.isOdd ? sem.surface2 : null, border: Border(bottom: BorderSide(color: sem.rule))),
          child: Row(children: [
            SizedBox(
              width: 90,
              child: Row(children: [
                ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.drag_indicator_rounded, size: 18))),
                Text('${i + 1}', style: TextStyle(color: sem.muted, fontSize: 12)),
                const Spacer(),
                IconButton(
                  tooltip: 'حذف الصف من الملف',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeRow(i),
                  icon: Icon(Icons.close_rounded, size: 16, color: sem.muted),
                ),
              ]),
            ),
            for (var j = 0; j < cols.length; j++)
              cellBox(
                _w(cols[j]),
                cols[j].computed
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Text(
                          j < r.length ? cellText(r[j], cols[j].type) : '',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                        ),
                      )
                    : TextFormField(
                        key: ValueKey('c-${_ids[i]}-$j'),
                        initialValue: _editText(j < r.length ? r[j] : null),
                        maxLines: cols[j].type == ColType.long ? 3 : 1,
                        minLines: 1,
                        textAlign: cols[j].numeric ? TextAlign.center : TextAlign.start,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                        onChanged: (v) => _set(i, j, v),
                      ),
              ),
          ]),
        );
      },
    );

    final totals = !hasTotals
        ? const SizedBox.shrink()
        : Container(
            decoration: BoxDecoration(color: cs.secondaryContainer, border: Border(top: BorderSide(color: cs.primary, width: 2))),
            child: Row(children: [
              const SizedBox(width: 90, child: Padding(padding: EdgeInsets.all(8), child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w800)))),
              for (var j = 0; j < cols.length; j++)
                cellBox(
                  _w(cols[j]),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_t.total(j) == null ? '' : cellText(_t.total(j), cols[j].type),
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          Icon(Icons.edit_note_rounded, color: cs.primary),
          const SizedBox(width: 8),
          const Text('تحرير البيانات قبل التصدير', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _title, decoration: fieldDeco('عنوان الملف')),
          const SizedBox(height: 6),
          Text(
            'عدّل أي خلية أو اسم عمود، واسحب ⠿ لترتيب الصفوف. الأعمدة المعلّمة ƒ محسوبة وتتغير وحدها، والمجاميع كذلك، '
            'وفي Excel تُكتب معادلات حية. التعديل على هذا الملف فقط ولا يغيّر سجلات المنظومة.',
            style: TextStyle(color: sem.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border.all(color: sem.rule), borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalW,
              child: Column(children: [header, Expanded(child: body), totals]),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(children: [
          TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add_rounded), label: const Text('صف جديد')),
          const Spacer(),
          Text('${_t.rows.length} صفاً · $_edits تعديلاً', style: TextStyle(color: sem.muted)),
          const SizedBox(width: 12),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
          const SizedBox(width: 6),
          FilledButton.icon(onPressed: () => Navigator.of(context).pop(_result()), icon: const Icon(Icons.check_rounded), label: const Text('اعتماد للتصدير')),
        ]),
      ),
    ]);
  }
}
