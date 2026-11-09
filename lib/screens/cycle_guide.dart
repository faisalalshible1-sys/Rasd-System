import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

// =====================================================================
// الدليل المرجعي للدورة المستندية: المخطط المجمّع من عرض «الدورة المستندية للعقود»
// (25 بنداً في 5 مراحل، وجهات التنفيذ والمتابعة، والتعديلات المقترحة على ترتيب ملف الوورد).
// =====================================================================

const String guideStatus = 'مقترح بانتظار الاعتماد · 2026-11-09';

class GuideLane {
  const GuideLane(this.name, this.light, this.dark);

  final String name;
  final Color light;
  final Color dark;

  Color color(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// صفوف المخطط: جهات التنفيذ والمتابعة.
const List<GuideLane> guideLanes = [
  GuideLane('رئيس اللجنة', Color(0xFF6B4FBB), Color(0xFFB7A4F2)),
  GuideLane('مكتب العقود والتوريدات والمستخلصات', Color(0xFF9A6A12), Color(0xFFE2B866)),
  GuideLane('مدير مكتب الشؤون الهندسية', Color(0xFF2F4F9A), Color(0xFF93AEEE)),
  GuideLane('قسم الشؤون الفنية', Color(0xFF137A7A), Color(0xFF6CCFCB)),
  GuideLane('قسم الإشراف والتنسيق', Color(0xFF2E7D32), Color(0xFF86CF8A)),
  GuideLane('قسم المطابقة والاستلام', Color(0xFFB0244A), Color(0xFFF08DA8)),
  GuideLane('قسم المتابعة وتقييم الأداء', Color(0xFF1F6FB2), Color(0xFF86BDF0)),
  GuideLane('لجان الاستلام', Color(0xFF8A5A3C), Color(0xFFD9A98A)),
  GuideLane('الجهة المنفذة', Color(0xFF5E6B1F), Color(0xFFC2CF7A)),
];

class GuideStage {
  const GuideStage(this.name, this.cols, this.note);

  final String name;
  final int cols;
  final String note;
}

const List<GuideStage> guideStages = [
  GuideStage('التعاقد والإعداد الفني', 3,
      'نقطة البدء: أمر بالتعاقد من المدير العام للصندوق · بعد توقيع العقد تنتقل الدورة إلى المرحلة 2'),
  GuideStage('أمر العمل وتسليم الموقع', 3,
      'تبدأ بعد توقيع العقد · التكليفات الثلاثة بالتوازي · بعد تصريح العمل يبدأ التنفيذ (المرحلة 3)'),
  GuideStage('التنفيذ والمستخلصات الجارية', 5, 'دورة تتكرر مع كل مستخلص جاري · عند اكتمال الأعمال تنتقل إلى المرحلة 4'),
  GuideStage('الاستلام الابتدائي والمستخلص الختامي', 1,
      'تبدأ عند اكتمال الأعمال · المستخلص الختامي يمر بشهادة الدفع والمراجعة والاعتماد · ثم فترة الضمان'),
  GuideStage('الاستلام النهائي وإقفال العقد', 2, 'تبدأ بعد انتهاء فترة الضمان · إقفال العقد نهاية الدورة'),
];

class GuideStep {
  const GuideStep(this.n, this.name, this.stage, this.lane, this.col, this.issuer, this.wordNo,
      {this.suggested = false, this.delta, this.parallel = false});

  final int n; // موضع الخطوة في الترتيب المقترح
  final String name;
  final int stage; // 0..4
  final int lane; // صف جهة التنفيذ والمتابعة
  final int col; // العمود داخل المرحلة (0 = الأول من اليمين)
  final String issuer; // الجهة المصدرة للنموذج
  final int wordNo; // رقمه في ملف الوورد
  final bool suggested; // جهة تنفيذ مقترحة لخانة فارغة في الملف
  final int? delta; // رقم التعديل على الترتيب (نُقل عن موضعه)
  final bool parallel;

  bool get moved => delta != null;
}

const List<GuideStep> guideSteps = [
  GuideStep(1, 'أمر بالتعاقد', 0, 1, 0, 'المدير العام للصندوق', 1, suggested: true),
  GuideStep(2, 'نطاق وطريقة عمل', 0, 3, 0, 'الشؤون الهندسية', 3),
  GuideStep(3, 'مقايسة تقديرية', 0, 3, 1, 'الشؤون الهندسية', 4),
  GuideStep(4, 'ملحق فني', 0, 1, 1, 'مكتب العقود', 5),
  GuideStep(5, 'نموذج عقد أشغال عامة', 0, 1, 2, 'مكتب العقود', 2, suggested: true, delta: 1),
  GuideStep(6, 'أمر عمل', 1, 0, 0, 'رئيس اللجنة', 6),
  GuideStep(7, 'تكليف مهندس إشراف', 1, 4, 0, 'الشؤون الهندسية', 9, delta: 2, parallel: true),
  GuideStep(8, 'تكليف مهندس حصر', 1, 5, 0, 'الشؤون الهندسية', 10, delta: 2, parallel: true),
  GuideStep(9, 'تكليف مهندس متابعة', 1, 6, 0, 'مكتب التخطيط', 11, delta: 2, parallel: true),
  GuideStep(10, 'محضر تسليم موقع عمل', 1, 4, 1, 'الشؤون الهندسية', 7),
  GuideStep(11, 'تصريح عمل', 1, 4, 2, 'الشؤون الهندسية', 8),
  GuideStep(12, 'ورقة قياس نموذج أ', 2, 5, 0, 'مكتب العقود', 12),
  GuideStep(13, 'ورقة قياس نموذج ب', 2, 5, 1, 'مكتب العقود', 13),
  GuideStep(14, 'محضر حصر كميات', 2, 5, 2, 'الشؤون الهندسية', 14),
  GuideStep(15, 'كشف حصر مستخلص', 2, 5, 3, 'الشؤون الهندسية', 16),
  GuideStep(16, 'مستخلص جاري', 2, 8, 3, 'الشؤون الهندسية', 17),
  GuideStep(17, 'شهادة دفع مستخلص', 2, 5, 4, 'الشؤون الهندسية', 15, delta: 3),
  GuideStep(18, 'مراجعة مستخلص', 2, 1, 4, 'مكتب العقود', 23, suggested: true, delta: 4),
  GuideStep(19, 'اعتماد مستخلص', 2, 0, 4, 'رئيس اللجنة', 24, suggested: true, delta: 4),
  GuideStep(20, 'تكليف لجنة استلام ابتدائي', 3, 2, 0, 'الشؤون الهندسية', 19),
  GuideStep(21, 'محضر استلام ابتدائي', 3, 7, 0, 'الشؤون الهندسية', 20),
  GuideStep(22, 'مستخلص ختامي', 3, 8, 0, 'الشؤون الهندسية', 18, delta: 5),
  GuideStep(23, 'تكليف لجنة استلام نهائي', 4, 2, 0, 'الشؤون الهندسية', 21),
  GuideStep(24, 'محضر استلام نهائي', 4, 7, 0, 'الشؤون الهندسية', 22),
  GuideStep(25, 'إقفال عقد', 4, 1, 1, 'مكتب العقود', 25, suggested: true),
];

/// تسلسل الخطوات (من، إلى). الخط المتقطع: يتكرر مع كل مستخلص جاري.
const List<(int, int)> guideEdges = [
  (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (6, 8), (6, 9), (7, 10), (8, 10), (9, 10), (10, 11), (11, 12),
  (12, 13), (13, 14), (14, 15), (15, 16), (16, 17), (17, 18), (18, 19), (19, 20), (20, 21), (21, 22), (22, 23),
  (23, 24), (24, 25),
];
const (int, int) guideRepeatEdge = (19, 12);

class GuideDelta {
  const GuideDelta(this.n, this.items, this.from, this.to, this.reason);

  final int n;
  final String items;
  final String from;
  final String to;
  final String reason;
}

const List<GuideDelta> guideDeltas = [
  GuideDelta(1, 'نموذج عقد أشغال عامة', '2', '5',
      'قيمة العقد ونطاقه ومدته تُستمد من المقايسة والملحق الفني، فيُستكمل نموذج العقد ويُوقَّع بعد جاهزيتهما.'),
  GuideDelta(2, 'تكليف مهندس إشراف، تكليف مهندس حصر، تكليف مهندس متابعة', '9، 10، 11', '7، 8، 9',
      'تُصدر التكليفات الثلاثة بالتوازي فور أمر العمل، ليحضر المهندسون تسليم الموقع ويوثّقوا الوضع القائم.'),
  GuideDelta(3, 'شهادة دفع مستخلص', '15', '17', 'شهادة الدفع تصدر بعد كشف الحصر والمستخلص الجاري، لأنها تشهد بالمبلغ المستحق فيه.'),
  GuideDelta(4, 'مراجعة مستخلص، اعتماد مستخلص', '23، 24', '18، 19',
      'المراجعة والاعتماد يتمّان مع كل مستخلص جاري أثناء التنفيذ، لا بعد الاستلام النهائي.'),
  GuideDelta(5, 'مستخلص ختامي', '18', '22', 'المستخلص الختامي يُبنى على الكميات النهائية بعد الاستلام الابتدائي. يُراجَع مع شروط العقد.'),
];

/// جهات مقترحة لخانات «الجهة المسؤولة عن التنفيذ والمتابعة» الفارغة: (رقم البند في الملف، النموذج، الجهة، السبب)
const List<(int, String, String, String)> guideSuggested = [
  (1, 'أمر بالتعاقد', 'مكتب العقود والتوريدات والمستخلصات', 'يتسلم الأمر ويبدأ إجراءات التعاقد'),
  (2, 'نموذج عقد أشغال عامة', 'مكتب العقود والتوريدات والمستخلصات', 'الجهة المصدرة للنموذج وتتابع توقيعه'),
  (23, 'مراجعة مستخلص', 'مكتب العقود والتوريدات والمستخلصات', 'الجهة المصدرة لنموذج المراجعة'),
  (24, 'اعتماد مستخلص', 'رئيس اللجنة', 'صاحب صلاحية الاعتماد'),
  (25, 'إقفال عقد', 'مكتب العقود والتوريدات والمستخلصات', 'الجهة المصدرة لنموذج الإقفال'),
];

const List<String> guideFileNotes = [
  'عنوان العمود الرابع «الجهة المسؤولة عن التنقيد والمتابعة»، والمقصود «التنفيذ».',
  'جهة البند 15 مكتوبة «المطابقة والاستلام» دون كلمة «قسم».',
  'البنود 1 و2 و23 و24 و25 بلا جهة تنفيذ ومتابعة في الملف.',
  'قسم الترميم لا يُسند إليه أي بند في هذه الدورة.',
];

const List<(String, String)> guideApprovals = [
  ('اعتماد الترتيب المقترح', 'التعديلات الخمسة على ترتيب الملف، من Δ1 إلى Δ5'),
  ('اعتماد الجهات المقترحة', 'جهات التنفيذ والمتابعة للبنود 1 و2 و23 و24 و25'),
  ('تأكيد موضع المستخلص الختامي', 'مطابقة التعديل الخامس مع شروط العقد'),
];

// =====================================================================
// الصفحة
// =====================================================================
class CycleGuidePage extends StatefulWidget {
  const CycleGuidePage({super.key});

  @override
  State<CycleGuidePage> createState() => _CycleGuidePageState();
}

class _CycleGuidePageState extends State<CycleGuidePage> {
  String _view = 'diagram';

  static const _views = [
    ('diagram', 'المخطط الكامل', Icons.schema_outlined),
    ('stages', 'المراحل', Icons.view_week_outlined),
    ('lanes', 'مسؤوليات الجهات', Icons.groups_2_outlined),
    ('changes', 'التعديلات والاعتماد', Icons.change_circle_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final moved = guideSteps.where((s) => s.moved).length;
    final suggested = guideSteps.where((s) => s.suggested).length;
    return PageBody(
      maxWidth: 1500,
      children: [
        PageHeader(
          title: 'الدليل المرجعي للدورة المستندية',
          subtitle: 'المخطط المجمّع لترتيب النماذج والوثائق والجهات المسؤولة عن التنفيذ والمتابعة، من أمر التعاقد إلى إقفال العقد.',
          icon: Icons.schema_outlined,
          actions: [ToneBadge(guideStatus, color: sem.wip)],
        ),
        ResponsiveGrid(minItemWidth: 150, spacing: 10, children: [
          StatCard(label: 'بنداً في الدورة', value: '${guideSteps.length}', icon: Icons.format_list_numbered_rounded),
          StatCard(label: 'مراحل', value: '${guideStages.length}', icon: Icons.view_week_rounded),
          StatCard(label: 'جهات تنفيذ ومتابعة', value: '${guideLanes.length}', icon: Icons.groups_2_rounded),
          StatCard(label: 'تعديلات مقترحة على الترتيب', value: '${guideDeltas.length}', sub: '$moved بنود نُقلت', icon: Icons.swap_vert_rounded),
          StatCard(label: 'جهات مقترحة لخانات فارغة', value: '$suggested', icon: Icons.person_add_alt_rounded),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in _views)
            ChoiceChip(
              avatar: Icon(v.$3, size: 18),
              label: Text(v.$2),
              selected: _view == v.$1,
              onSelected: (_) => setState(() => _view = v.$1),
            ),
        ]),
        const SizedBox(height: 14),
        MotionSwitcher(
          expand: false,
          child: KeyedSubtree(
            key: ValueKey(_view),
            child: switch (_view) {
              'stages' => const _StagesView(),
              'lanes' => const _LanesView(),
              'changes' => const _ChangesView(),
              _ => const _DiagramCard(),
            },
          ),
        ),
      ],
    );
  }
}

void showGuideStep(BuildContext context, GuideStep s) {
  final sem = Sem.of(context);
  final lane = guideLanes[s.lane];
  final color = lane.color(context);
  final delta = s.delta == null ? null : guideDeltas.firstWhere((d) => d.n == s.delta);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
                child: Text('${s.n}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text('المرحلة ${s.stage + 1}: ${guideStages[s.stage].name}', style: TextStyle(color: sem.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            _kv(ctx, 'جهة التنفيذ والمتابعة', lane.name + (s.suggested ? ' (جهة مقترحة)' : '')),
            _kv(ctx, 'الجهة المصدرة للنموذج', s.issuer),
            _kv(ctx, 'رقمه في ملف الوورد', 'بند ${s.wordNo}'),
            if (s.parallel) _kv(ctx, 'التوقيت', 'يصدر بالتوازي مع التكليفين الآخرين فور أمر العمل'),
            if (s.stage == 2) _kv(ctx, 'التكرار', 'يتكرر مع كل مستخلص جاري'),
            if (delta != null) ...[
              const SizedBox(height: 8),
              InfoBanner(text: 'Δ${delta.n}: نُقل من الموضع ${delta.from} إلى ${delta.to}. ${delta.reason}', level: 'warning'),
            ],
            if (s.suggested) ...[
              const SizedBox(height: 8),
              InfoBanner(
                text: 'خانة الجهة فارغة في الملف، والمقترح: ${lane.name} — '
                    '${guideSuggested.firstWhere((x) => x.$1 == s.wordNo, orElse: () => (0, '', '', '')).$4}.',
                level: 'info',
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _kv(BuildContext context, String k, String v) {
  final sem = Sem.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 170, child: Text(k, style: TextStyle(color: sem.muted))),
      Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );
}

// ---------------------------------------------------------------------
// المخطط الكامل (صفوف الجهات × أعمدة المراحل)
// ---------------------------------------------------------------------
class _DiagramCard extends StatefulWidget {
  const _DiagramCard();

  @override
  State<_DiagramCard> createState() => _DiagramCardState();
}

class _DiagramCardState extends State<_DiagramCard> {
  bool? _choice; // اختيار المستخدم؛ الافتراضي: ملاءمة على الشاشات العريضة والحجم الكامل على الهاتف

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final fitMode = _choice ?? MediaQuery.sizeOf(context).width >= 900;
    return SectionCard(
      title: 'المخطط الكامل للدورة المستندية',
      icon: Icons.schema_outlined,
      subtitle: 'الرقم: موضع الخطوة · الصفوف: جهة التنفيذ والمتابعة · الإطار المتقطع: جهة مقترحة · '
          'المثلث الأحمر: بند نُقل عن موضعه في الملف · الخط المتقطع: يتكرر مع كل مستخلص جاري. اضغط أي بند لتفاصيله.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.fit_screen_outlined, size: 18), label: Text('ملاءمة')),
              ButtonSegment(value: false, icon: Icon(Icons.zoom_in_rounded, size: 18), label: Text('الحجم الكامل')),
            ],
            selected: {fitMode},
            onSelectionChanged: (s) => setState(() => _choice = s.first),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
        const d = CycleDiagram();
        final w = CycleDiagram.width, h = CycleDiagram.height;
        if (fitMode) {
          final scale = math.min(1.0, c.maxWidth / w);
          return SizedBox(
            width: c.maxWidth,
            height: h * scale,
            child: FittedBox(fit: BoxFit.contain, alignment: Alignment.topCenter, child: d),
          );
        }
        return Container(
          height: math.min(h + 16, 720),
          decoration: BoxDecoration(border: Border.all(color: sem.rule), borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.4,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(40),
            child: d,
          ),
        );
      }),
      ]),
    );
  }
}

/// رسم المخطط: صفوف الجهات وأعمدة المراحل وصناديق البنود والأسهم.
class CycleDiagram extends StatelessWidget {
  const CycleDiagram({super.key});

  static const double headW = 150, headH = 50, laneH = 92, colW = 112, stagePad = 10, boxW = 94, boxH = 72;
  static int get totalCols => guideStages.fold(0, (a, s) => a + s.cols);
  static double get width => headW + totalCols * colW + guideStages.length * stagePad * 2;
  static double get height => headH + guideLanes.length * laneH + 8;

  /// حدود عمود مرحلة (من اليمين): يمين ويسار.
  static (double, double) stageSpan(int stage) {
    var right = width - headW;
    for (var i = 0; i < stage; i++) {
      right -= guideStages[i].cols * colW + stagePad * 2;
    }
    final left = right - guideStages[stage].cols * colW - stagePad * 2;
    return (left, right);
  }

  static Rect boxOf(GuideStep s) {
    final (_, right) = stageSpan(s.stage);
    final colRight = right - stagePad - s.col * colW;
    final cx = colRight - colW / 2;
    final cy = headH + s.lane * laneH + laneH / 2;
    return Rect.fromCenter(center: Offset(cx, cy), width: boxW, height: boxH);
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final tone = toneOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final headBg = dark ? const Color(0xFF0E1620) : const Color(0xFF1C2733);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(children: [
          // خلفيات المراحل والصفوف
          for (var i = 0; i < guideStages.length; i++)
            Positioned(
              left: stageSpan(i).$1 + 3,
              top: headH,
              width: stageSpan(i).$2 - stageSpan(i).$1 - 6,
              height: guideLanes.length * laneH,
              child: Container(color: i.isEven ? sem.surface2.withValues(alpha: 0.85) : tone.surface),
            ),
          for (var l = 1; l < guideLanes.length; l++)
            Positioned(left: 0, right: 0, top: headH + l * laneH, height: 1, child: Container(color: sem.rule)),
          // رؤوس المراحل
          for (var i = 0; i < guideStages.length; i++)
            Positioned(
              left: stageSpan(i).$1 + 3,
              top: 0,
              width: stageSpan(i).$2 - stageSpan(i).$1 - 6,
              height: headH - 6,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: headBg, borderRadius: BorderRadius.circular(6)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text('${i + 1} · ${guideStages[i].name}${i == 2 ? ' ↺' : ''}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, height: 1.2)),
                ),
              ),
            ),
          // رأس عمود الجهات
          Positioned(
            right: 0,
            top: 0,
            width: headW - 6,
            height: headH - 6,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: headBg, borderRadius: BorderRadius.circular(6)),
              child: const Directionality(
                textDirection: TextDirection.rtl,
                child: Text('جهة التنفيذ\nوالمتابعة',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.2)),
              ),
            ),
          ),
          // أسماء الجهات
          for (var l = 0; l < guideLanes.length; l++)
            Positioned(
              right: 0,
              top: headH + l * laneH + 3,
              width: headW - 6,
              height: laneH - 6,
              child: Container(
                alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: guideLanes[l].color(context).withValues(alpha: dark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(guideLanes[l].name,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.25, color: tone.text)),
                ),
              ),
            ),
          // الأسهم
          Positioned.fill(
            child: CustomPaint(painter: _EdgesPainter(line: sem.muted, repeat: dark ? const Color(0xFF8E9AAA) : const Color(0xFF7A8594))),
          ),
          // عبارة التكرار
          Positioned(
            left: stageSpan(2).$1,
            width: stageSpan(2).$2 - stageSpan(2).$1,
            top: headH + 4,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('↺ يتكرر مع كل مستخلص جاري',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11.5, color: guideLanes[6].color(context))),
            ),
          ),
          // البنود
          for (final s in guideSteps) Positioned.fromRect(rect: boxOf(s), child: _StepBox(step: s)),
        ]),
      ),
    );
  }
}

class _StepBox extends StatelessWidget {
  const _StepBox({required this.step});

  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final tone = toneOf(context);
    final color = guideLanes[step.lane].color(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(color.withValues(alpha: dark ? 0.16 : 0.09), tone.surface3);
    final box = CustomPaint(
      foregroundPainter: _BorderPainter(color: color, dashed: step.suggested),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => showGuideStep(context, step),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Center(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${step.n} ', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
                    TextSpan(text: step.name, style: TextStyle(color: tone.text, fontSize: 12, height: 1.25)),
                  ]),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: '${step.name} · ${guideLanes[step.lane].name}${step.moved ? ' · Δ${step.delta}' : ''}',
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: box),
        if (step.moved)
          Positioned(
            right: -6,
            bottom: -7,
            child: IgnorePointer(child: CustomPaint(size: const Size(16, 14), painter: _TrianglePainter(Sem.of(context).danger))),
          ),
      ]),
    );
  }
}

class _BorderPainter extends CustomPainter {
  _BorderPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.8 : 1.4;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9));
    if (!dashed) {
      canvas.drawRRect(rr, p);
      return;
    }
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), p);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) => old.color != color || old.dashed != dashed;
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({required this.line, required this.repeat});

  final Color line;
  final Color repeat;

  static GuideStep _s(int n) => guideSteps.firstWhere((x) => x.n == n);

  bool _blocked(Offset a, Offset b, Set<int> skip) {
    final seg = Rect.fromPoints(a, b).inflate(1);
    for (final s in guideSteps) {
      if (skip.contains(s.n)) continue;
      if (CycleDiagram.boxOf(s).deflate(2).overlaps(seg)) return true;
    }
    return false;
  }

  List<Offset> _route(GuideStep from, GuideStep to) {
    final a = CycleDiagram.boxOf(from), b = CycleDiagram.boxOf(to);
    final skip = {from.n, to.n};
    // نفس العمود: خط رأسي، أو التفاف من اليمين إن اعترضه بند
    if ((a.center.dx - b.center.dx).abs() < 2) {
      final down = b.center.dy > a.center.dy;
      final p1 = Offset(a.center.dx, down ? a.bottom : a.top);
      final p2 = Offset(b.center.dx, down ? b.top : b.bottom);
      if (!_blocked(p1, p2, skip)) return [p1, p2];
      final x = a.right + 9;
      return [Offset(a.right, a.center.dy), Offset(x, a.center.dy), Offset(x, b.center.dy), Offset(b.right, b.center.dy)];
    }
    // نفس الصف: خط أفقي
    if ((a.center.dy - b.center.dy).abs() < 2) {
      return b.center.dx < a.center.dx
          ? [Offset(a.left, a.center.dy), Offset(b.right, b.center.dy)]
          : [Offset(a.right, a.center.dy), Offset(b.left, b.center.dy)];
    }
    // صف آخر: أفقي حتى عمود الهدف ثم رأسي إلى حافته، وإلا التفاف إلى جانبه الأيمن
    final down = b.center.dy > a.center.dy;
    final start = Offset(a.left, a.center.dy);
    final corner = Offset(b.center.dx, a.center.dy);
    final end = Offset(b.center.dx, down ? b.top : b.bottom);
    if (!_blocked(start, corner, skip) && !_blocked(corner, end, skip)) return [start, corner, end];
    final mid = (a.left + b.right) / 2;
    return [start, Offset(mid, a.center.dy), Offset(mid, b.center.dy), Offset(b.right, b.center.dy)];
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Paint p) {
    final dir = (to - from);
    final len = dir.distance;
    if (len == 0) return;
    final u = dir / len;
    final n = Offset(-u.dy, u.dx);
    const s = 7.0;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - u.dx * s + n.dx * s * 0.55, to.dy - u.dy * s + n.dy * s * 0.55)
      ..lineTo(to.dx - u.dx * s - n.dx * s * 0.55, to.dy - u.dy * s - n.dy * s * 0.55)
      ..close();
    canvas.drawPath(path, Paint()..color = p.color);
  }

  void _poly(Canvas canvas, List<Offset> pts, Paint p, {bool dashed = false}) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    if (!dashed) {
      canvas.drawPath(path, p);
    } else {
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), p);
          d += 12;
        }
      }
    }
    _arrow(canvas, pts[pts.length - 2], pts.last, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final e in guideEdges) {
      _poly(canvas, _route(_s(e.$1), _s(e.$2)), p);
    }
    // التكرار: من اعتماد المستخلص عائداً إلى ورقة القياس الأولى
    final a = CycleDiagram.boxOf(_s(guideRepeatEdge.$1)), b = CycleDiagram.boxOf(_s(guideRepeatEdge.$2));
    final rp = Paint()
      ..color = repeat
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    _poly(canvas, [Offset(a.right, a.center.dy), Offset(b.center.dx, a.center.dy), Offset(b.center.dx, b.top)], rp, dashed: true);
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter old) => old.line != line || old.repeat != repeat;
}

// ---------------------------------------------------------------------
// المراحل
// ---------------------------------------------------------------------
class _StagesView extends StatelessWidget {
  const _StagesView();

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < guideStages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SectionCard(
              title: 'المرحلة ${i + 1}: ${guideStages[i].name}',
              icon: Icons.flag_outlined,
              subtitle: guideStages[i].note,
              trailing: ToneBadge('${guideSteps.where((s) => s.stage == i).length} بنود', color: sem.muted),
              child: Column(children: [
                for (final s in guideSteps.where((s) => s.stage == i))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => showGuideStep(context, s),
                    leading: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: guideLanes[s.lane].color(context).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${s.n}', style: TextStyle(color: guideLanes[s.lane].color(context), fontWeight: FontWeight.w900)),
                    ),
                    title: Row(children: [
                      Flexible(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (s.moved) ...[const SizedBox(width: 6), ToneBadge('Δ${s.delta}', color: sem.danger)],
                      if (s.parallel) ...[const SizedBox(width: 6), ToneBadge('بالتوازي', color: sem.wip)],
                    ]),
                    subtitle: Text(
                      '${guideLanes[s.lane].name}${s.suggested ? ' (مقترحة)' : ''} · تصدره: ${s.issuer} · بند ${s.wordNo} في الملف',
                      style: TextStyle(color: sem.muted, fontSize: 12.5),
                    ),
                  ),
              ]),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// مسؤوليات الجهات
// ---------------------------------------------------------------------
class _LanesView extends StatelessWidget {
  const _LanesView();

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final order = [for (var i = 0; i < guideLanes.length; i++) i]
      ..sort((a, b) => guideSteps.where((s) => s.lane == b).length.compareTo(guideSteps.where((s) => s.lane == a).length));
    final issuers = <String, int>{};
    for (final s in guideSteps) {
      issuers[s.issuer] = (issuers[s.issuer] ?? 0) + 1;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ResponsiveGrid(minItemWidth: 320, spacing: 12, children: [
        for (final l in order)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDecoration(context),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: guideLanes[l].color(context).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
                  child: Text('${guideSteps.where((s) => s.lane == l).length}',
                      style: TextStyle(color: guideLanes[l].color(context), fontWeight: FontWeight.w900, fontSize: 17)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(guideLanes[l].name, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in guideSteps.where((s) => s.lane == l))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${s.n}. ${s.name}${s.suggested ? ' *' : ''}'),
                    onPressed: () => showGuideStep(context, s),
                  ),
              ]),
            ]),
          ),
      ]),
      const SizedBox(height: 10),
      Text('الرقم: عدد البنود التي تنفذها الجهة وتتابعها · * جهة مقترحة لخانة فارغة في الملف · قسم الترميم لا يُسند إليه أي بند في هذه الدورة.',
          style: TextStyle(color: sem.muted, fontSize: 12.5)),
      const SizedBox(height: 14),
      SectionCard(
        title: 'الجهات المصدرة للنماذج',
        icon: Icons.outbox_outlined,
        child: Wrap(spacing: 18, runSpacing: 8, children: [
          for (final e in (issuers.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
            Text.rich(TextSpan(children: [
              TextSpan(text: '${e.value} ', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              TextSpan(text: e.key, style: TextStyle(color: sem.muted)),
            ])),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------
// التعديلات المقترحة والجهات المقترحة والمطلوب للاعتماد
// ---------------------------------------------------------------------
class _ChangesView extends StatelessWidget {
  const _ChangesView();

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'خمسة تعديلات على ترتيب الملف',
        icon: Icons.swap_vert_rounded,
        child: Column(children: [
          for (final d in guideDeltas)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ToneBadge('Δ${d.n}', color: sem.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.items, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('رقمه في الملف: ${d.from} ← موضعه المقترح: ${d.to}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      Text(d.reason),
                    ]),
                  ),
                ]),
              ),
            ),
          InfoBanner(text: 'التعديل الخامس (موضع المستخلص الختامي) يحتاج تأكيداً مع شروط العقد قبل الاعتماد.', level: 'warning'),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'جهات مقترحة للخانات الفارغة',
        icon: Icons.person_add_alt_rounded,
        subtitle: 'خانة «الجهة المسؤولة عن التنفيذ والمتابعة» فارغة في الملف لهذه البنود.',
        child: Column(children: [
          for (final x in guideSuggested)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 17, child: Text('${x.$1}', style: const TextStyle(fontWeight: FontWeight.w800))),
              title: Text('${x.$2} ← ${x.$3}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(x.$4, style: TextStyle(color: sem.muted)),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'ملاحظات على ملف الوورد',
        icon: Icons.sticky_note_2_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in guideFileNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.circle, size: 7, color: sem.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(n)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'المطلوب للاعتماد',
        icon: Icons.verified_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < guideApprovals.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 16, child: Text('${i + 1}')),
              title: Text(guideApprovals[i].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(guideApprovals[i].$2, style: TextStyle(color: sem.muted)),
            ),
          const SizedBox(height: 6),
          Text('بعد الاعتماد: يُعمَّم الجدول على الأقسام، ويُحدَّث ملف الوورد والمخطط التفاعلي بالترتيب المعتمد.',
              style: TextStyle(color: sem.muted)),
        ]),
      ),
    ]);
  }
}
