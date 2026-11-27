import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../geo.dart';
import '../maintenance.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

// =====================================================================
// خريطة المواقع (الإصدار 1.13.0، الترحيل 44): مواقع المشاريع وبلاغات الصيانة المفتوحة، والمخاطر عند مشروعها.
// خريطة الأساس OpenStreetMap وتحتاج اتصالاً؛ تُحدَّد المواقع بالنقر على الخريطة أو بكتابة الإحداثيات أو لصق رابط.
// =====================================================================

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'ly.rasd.dc_app';

Widget _osmAttribution() => const RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      attributions: [TextSourceAttribution('© مساهمو OpenStreetMap')],
    );

class SiteMapPage extends StatefulWidget {
  const SiteMapPage({super.key});

  @override
  State<SiteMapPage> createState() => _SiteMapPageState();
}

class _SiteMapPageState extends State<SiteMapPage> {
  bool _projects = true;
  bool _requests = true;
  bool _risks = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);

    final projects = [for (final p in app.projects) if (app.geoOfProject(p.id) != null) p];
    final noProject = [for (final p in app.fullProjects) if (app.geoOfProject(p.id) == null) p];
    final openRequests = app.v24Ready ? app.maint.open : <MtRequest>[];
    final requests = [for (final r in openRequests) if (app.geoOfRequest(r.id) != null) r];
    final noRequest = [for (final r in openRequests) if (app.geoOfRequest(r.id) == null) r];
    final now = DateTime.now();

    List<dynamic> openRisksOf(String projectId) =>
        [for (final r in app.risks) if (!r.isClosed && r.projectId == projectId) r];

    final markers = <Marker>[];
    final points = <LatLng>[];
    if (_projects || _risks) {
      for (final p in projects) {
        final g = app.geoOfProject(p.id)!;
        final risks = _risks ? openRisksOf(p.id) : const [];
        final high = risks.any((r) => app.riskConfig.isHigh(r.score));
        final color = high ? sem.danger : (risks.isNotEmpty ? sem.wip : Theme.of(context).colorScheme.primary);
        if (!_projects && risks.isEmpty) continue;
        points.add(LatLng(g.lat, g.lng));
        markers.add(Marker(
          point: LatLng(g.lat, g.lng),
          width: 44,
          height: 52,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _projectSheet(context, p, g, risks),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              Icon(Icons.location_on_rounded, size: 44, color: color),
              if (risks.isNotEmpty)
                Positioned(
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                    child: Text('${risks.length}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
                  ),
                ),
            ]),
          ),
        ));
      }
    }
    if (_requests) {
      for (final r in requests) {
        final g = app.geoOfRequest(r.id)!;
        final late = r.isOverdue(now);
        points.add(LatLng(g.lat, g.lng));
        markers.add(Marker(
          point: LatLng(g.lat, g.lng),
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () => _requestSheet(context, r, g),
            child: Container(
              decoration: BoxDecoration(
                color: late ? sem.danger : sem.wip,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.build_rounded, size: 17, color: Colors.white),
            ),
          ),
        ));
      }
    }

    final center = points.isEmpty ? const LatLng(geoDefaultLat, geoDefaultLng) : points.first;

    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'خريطة المواقع',
          subtitle: 'مواقع المشاريع وبلاغات الصيانة المفتوحة، وعدد المخاطر النشطة عند كل مشروع. تحتاج الخريطة اتصالاً بالإنترنت.',
          icon: Icons.map_outlined,
        ),
        if (!app.v28Ready)
          const InfoBanner(text: 'يلزم الترحيل 44 لعرض الخريطة.', level: 'warning')
        else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilterChip(label: Text('المشاريع (${projects.length})'), selected: _projects, onSelected: (v) => setState(() => _projects = v)),
            FilterChip(label: Text('بلاغات الصيانة (${requests.length})'), selected: _requests, onSelected: (v) => setState(() => _requests = v)),
            FilterChip(label: const Text('المخاطر'), selected: _risks, onSelected: (v) => setState(() => _risks = v)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 480,
              child: FlutterMap(
                key: ValueKey('${points.length}-$_projects-$_requests-$_risks'),
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: points.length <= 1 ? 14 : 12,
                  initialCameraFit: points.length > 1
                      ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 16)
                      : null,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
                  MarkerLayer(markers: markers),
                  _osmAttribution(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            _legend(Icons.location_on_rounded, Theme.of(context).colorScheme.primary, 'مشروع'),
            _legend(Icons.location_on_rounded, sem.wip, 'مشروع به مخاطر نشطة'),
            _legend(Icons.location_on_rounded, sem.danger, 'مشروع به خطر مرتفع'),
            _legend(Icons.build_circle_rounded, sem.wip, 'بلاغ صيانة'),
            _legend(Icons.build_circle_rounded, sem.danger, 'بلاغ متأخر'),
          ]),
          const SizedBox(height: 14),
          SectionCard(
            title: 'بلا موقع بعد (${noProject.length + noRequest.length})',
            icon: Icons.wrong_location_outlined,
            subtitle: 'حدّد موقع المشروع أو البلاغ لتظهر نقطته على الخريطة.',
            child: (noProject.isEmpty && noRequest.isEmpty)
                ? Text('لكل المشاريع والبلاغات المفتوحة مواقع مسجَّلة.', style: TextStyle(color: sem.muted))
                : Column(children: [
                    for (final p in noProject.take(60))
                      _pendingRow(context, p.label, 'مشروع', app.canSetProjectGeo, () => showGeoPicker(context, kind: 'project', refId: p.id, title: p.label)),
                    for (final r in noRequest.take(60))
                      _pendingRow(context, '${r.reqNo} · ${r.title}', 'بلاغ صيانة', app.canSetRequestGeo,
                          () => showGeoPicker(context, kind: 'request', refId: r.id, title: '${r.reqNo} · ${r.title}')),
                  ]),
          ),
        ],
      ],
    );
  }

  Widget _legend(IconData icon, Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12.5)),
      ]);

  Widget _pendingRow(BuildContext context, String title, String kind, bool canSet, VoidCallback onSet) {
    final sem = Sem.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(kind, style: TextStyle(color: sem.muted, fontSize: 12.5)),
        if (canSet) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: onSet, icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('تحديد')),
        ],
      ]),
    );
  }

  void _projectSheet(BuildContext context, Project p, GeoPoint g, List<dynamic> risks) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.label, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(geoText(g.lat, g.lng) + (g.note.isEmpty ? '' : ' · ${g.note}'), style: TextStyle(color: sem.muted)),
            if (risks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('المخاطر النشطة (${risks.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final r in risks.take(6)) Text('• ${r.code} — ${r.description} (الدرجة ${r.score})', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(geoOsmUrl(g.lat, g.lng)), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('فتح في OpenStreetMap'),
              ),
              if (app.canSetProjectGeo)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    showGeoPicker(context, kind: 'project', refId: p.id, title: p.label, current: g);
                  },
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: const Text('تعديل الموقع'),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _requestSheet(BuildContext context, MtRequest r, GeoPoint g) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.reqNo} · ${r.title}', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('الأولوية: ${mtPriorityLabels[r.priority] ?? r.priority}${r.isOverdue(DateTime.now()) ? ' · متأخر' : ''}',
                style: TextStyle(color: r.isOverdue(DateTime.now()) ? sem.danger : sem.muted)),
            Text(geoText(g.lat, g.lng) + (g.note.isEmpty ? '' : ' · ${g.note}'), style: TextStyle(color: sem.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(geoOsmUrl(g.lat, g.lng)), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('فتح في OpenStreetMap'),
              ),
              if (app.canSetRequestGeo)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    showGeoPicker(context, kind: 'request', refId: r.id, title: '${r.reqNo} · ${r.title}', current: g);
                  },
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: const Text('تعديل الموقع'),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// منتقي الموقع: انقر الخريطة، أو اكتب «العرض, الطول»، أو الصق رابط خرائط. kind: project | request.
Future<bool> showGeoPicker(BuildContext context, {required String kind, required String refId, required String title, GeoPoint? current}) async {
  final app = AppScope.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => _GeoPickerDialog(app: app, kind: kind, refId: refId, title: title, current: current),
  );
  return saved ?? false;
}

class _GeoPickerDialog extends StatefulWidget {
  const _GeoPickerDialog({required this.app, required this.kind, required this.refId, required this.title, this.current});

  final AppState app;
  final String kind;
  final String refId;
  final String title;
  final GeoPoint? current;

  @override
  State<_GeoPickerDialog> createState() => _GeoPickerDialogState();
}

class _GeoPickerDialogState extends State<_GeoPickerDialog> {
  final _map = MapController();
  late final TextEditingController _coords;
  late final TextEditingController _note;
  LatLng? _pick;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _pick = c == null ? null : LatLng(c.lat, c.lng);
    _coords = TextEditingController(text: c == null ? '' : geoText(c.lat, c.lng));
    _note = TextEditingController(text: c?.note ?? '');
  }

  @override
  void dispose() {
    _coords.dispose();
    _note.dispose();
    _map.dispose();
    super.dispose();
  }

  void _fromText(String v) {
    final c = parseCoordinates(v);
    setState(() {
      _error = v.trim().isEmpty || c != null ? null : 'إحداثيات غير مفهومة. اكتب «العرض, الطول» مثل 32.1167, 20.0667';
      if (c != null) {
        _pick = LatLng(c.lat, c.lng);
        _map.move(_pick!, 16);
      }
    });
  }

  Future<void> _save() async {
    final p = _pick;
    if (p == null) {
      setState(() => _error = 'انقر الخريطة أو اكتب الإحداثيات أولاً');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.app.setGeo(widget.kind, widget.refId, p.latitude, p.longitude, note: _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
      if (mounted) showToast(context, 'حُفظ الموقع');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await widget.app.clearGeo(widget.kind, widget.refId);
      if (mounted) Navigator.of(context).pop(true);
      if (mounted) showToast(context, 'أُزيل الموقع');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final start = _pick ?? const LatLng(geoDefaultLat, geoDefaultLng);
    return AlertDialog(
      title: Text('موقع: ${widget.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 300,
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: start,
                    initialZoom: _pick == null ? 12 : 16,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onTap: (_, p) => setState(() {
                      _pick = p;
                      _coords.text = geoText(p.latitude, p.longitude);
                      _error = null;
                    }),
                  ),
                  children: [
                    TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
                    if (_pick != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _pick!,
                          width: 44,
                          height: 52,
                          alignment: Alignment.topCenter,
                          child: Icon(Icons.location_on_rounded, size: 44, color: sem.danger),
                        ),
                      ]),
                    _osmAttribution(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _coords,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'الإحداثيات (العرض, الطول) أو رابط خرائط',
                errorText: _error,
                isDense: true,
              ),
              onChanged: _fromText,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'ملاحظة عن الموقع (اختياري)', isDense: true),
            ),
          ]),
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(onPressed: _busy ? null : _clear, child: Text('إزالة الموقع', style: TextStyle(color: sem.danger))),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}
