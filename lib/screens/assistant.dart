import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/audit_text.dart' show settingLabels;
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// مساعد Claude داخل المنظومة — لمدير المكتب وحده.
/// يقرأ ملخص المنظومة بصلاحية المدير (عبر خدمة claude-assistant في Supabase)، ويقترح تعديلات تظهر بطاقاتٍ
/// ينفّذها المدير بضغطة عبر العمليات المعتادة (قاعدة البيانات تتحقق من الصلاحيات وتسجّل كل تعديل).
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _busy = false;

  static const _suggestions = <(IconData, String)>[
    (Icons.summarize_outlined, 'لخّص حالة العقود اليوم في نقاط'),
    (Icons.hourglass_top_rounded, 'ما العقود المتأخرة في دورتها المستندية، وما المستند الذي يوقفها؟'),
    (Icons.payments_outlined, 'حلّل القيم التعاقدية والمنفذة والضمانات، وأين الفجوات؟'),
    (Icons.engineering_outlined, 'من المهندسون الأكثر تكليفاً، وهل هناك عقود بلا مهندس مشرف؟'),
    (Icons.fact_check_outlined, 'ما طلبات الاعتماد المعلقة التي تحتاج قراري؟'),
    (Icons.receipt_long_outlined, 'حلّل المستخلصات والمدفوع والمستحق غير المدفوع، وما العقود الأعلى متبقياً للدفع؟'),
    (Icons.price_change_outlined, 'راجع قيم البنود والمنفذ، واقترح تصحيح ما يبدو غير متسق'),
    (Icons.lightbulb_outline_rounded, 'اقترح تطويرات عملية للمنظومة بناءً على البيانات والاستخدام'),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.of(context, 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    _input.clear();
    setState(() => _busy = true);
    _scrollToEnd();
    final app = AppScope.read(context);
    await app.askClaude(q);
    if (!mounted) return;
    setState(() => _busy = false);
    _scrollToEnd();
    _focus.requestFocus();
  }

  Future<void> _saveAsIdea(AssistantMessage m) async {
    final lines = m.text.split('\n').map((l) => l.replaceAll(RegExp(r'^[\s•\-\*#\d\.\)]+'), '').trim()).where((l) => l.isNotEmpty).toList();
    var title = lines.isEmpty ? '' : lines.first;
    if (title.length > 120) title = '${title.substring(0, 117)}…';
    if (title.length < 3) title = 'اقتراح من مساعد Claude';
    final body = m.text.length > 7800 ? '${m.text.substring(0, 7800)}…' : m.text;
    final edited = await textInputDialog(
      context,
      title: 'حفظ كفكرة تطوير',
      message: 'تُضاف إلى «الأفكار والتطوير» ويمكنك متابعتها ومزامنتها مع GitHub من هناك.',
      label: 'عنوان الفكرة',
      confirmLabel: 'حفظ الفكرة',
      initial: title,
      multiline: false,
      required: true,
    );
    if (edited == null || !mounted) return;
    try {
      await AppScope.read(context).submitIdea(
        title: edited.length < 3 ? title : edited,
        body: '$body\n\n— من مساعد Claude',
        category: 'feature',
        priority: 'normal',
      );
      if (mounted) showToast(context, 'حُفظت الفكرة في «الأفكار والتطوير»');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.isDirector) {
      return const Center(child: EmptyState(icon: Icons.lock_outline, title: 'مساعد Claude لمدير المكتب وحده'));
    }
    if (!app.canUseAssistant) {
      return Center(
        child: EmptyState(
          icon: Icons.power_settings_new_rounded,
          title: app.v3Ready ? 'مساعد Claude متوقف' : 'المساعد يحتاج تحديث قاعدة البيانات',
          message: app.v3Ready
              ? 'شغّله من لوحة التحكم ← «التخصيص والتطوير».'
              : 'طبّق ملف قاعدة البيانات 20261102000010_contracts.sql أولاً.',
        ),
      );
    }
    final msgs = app.assistantMessages;
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 980 ? (width - 900) / 2 : 14.0;

    return Column(
      children: [
        // شريط المساعد
        Padding(
          padding: EdgeInsets.fromLTRB(side, 10, side, 6),
          child: Row(
            children: [
              const _Spark(size: 30),
              const SizedBox(width: 10),
              const Expanded(child: Text('مساعد Claude', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              ToneBadge(app.settings.aiModel, color: Theme.of(context).colorScheme.primary, icon: Icons.memory_rounded),
              if (msgs.isNotEmpty)
                IconButton(
                  tooltip: 'محادثة جديدة',
                  onPressed: _busy ? null : app.clearAssistant,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: sem.rule),
        Expanded(
          child: msgs.isEmpty
              ? _Welcome(side: side, onPick: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(side, 16, side, 16),
                  itemCount: msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= msgs.length) {
                      return const FadeSlideIn(child: _Typing());
                    }
                    final m = msgs[i];
                    return FadeSlideIn(
                      key: ValueKey(m),
                      offset: Offset(0, m.isUser ? 0.15 : 0.08),
                      child: _Bubble(message: m, onSaveIdea: m.isUser || m.error ? null : () => _saveAsIdea(m)),
                    );
                  },
                ),
        ),
        Divider(height: 1, color: sem.rule),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, 10, side, 8),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        enabled: !_busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'اسأل عن العقود والأعمال والمهندسين والمالية…',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedScale(
                      scale: _input.text.trim().isEmpty ? 0.9 : 1,
                      duration: Motion.of(context, 200),
                      child: IconButton.filled(
                        tooltip: 'إرسال',
                        onPressed: _busy || _input.text.trim().isEmpty ? null : _send,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'يقرأ Claude ملخص المنظومة بصلاحيتك، ويقترح التعديلات ولا ينفّذ شيئاً إلا بضغطتك. كل سؤال وتنفيذ يُسجَّل. راجع الأرقام قبل اعتمادها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sem.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// شارة المساعد المتدرجة.
class _Spark extends StatelessWidget {
  const _Spark({this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [cs.primary, Brand.flagGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.55),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.side, required this.onPick});

  final double side;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sem = Sem.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 28, side, 20),
      children: [
        const Center(child: FadeSlideIn(scale: 0.6, child: _Spark(size: 64))),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          child: Text('كيف أساعدك اليوم؟', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 6),
        FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: Text(
            'اسأل عن العقود وأعمالها، والمهندسين وأرقام تكليفهم، والقيم التعاقدية والمنفذة والضمانات، والطلبات المعلقة — أو اطلب اقتراحات لتطوير المنظومة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: sem.muted),
          ),
        ),
        const SizedBox(height: 22),
        ResponsiveGrid(
          minItemWidth: 260,
          spacing: 10,
          children: staggered(startMs: 260, stepMs: 60, [
            for (final s in _AssistantPageState._suggestions)
              HoverLift(
                radius: 14,
                child: Material(
                  color: sem.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sem.rule)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onPick(s.$2),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(s.$1, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.45))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TypingDots(),
            const SizedBox(width: 10),
            Text('Claude يحلّل بيانات المنظومة…', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onSaveIdea});

  final AssistantMessage message;
  final VoidCallback? onSaveIdea;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final user = message.isUser;
    final bg = user ? cs.primary : (message.error ? sem.dangerSoft : sem.surface);
    final fg = user ? cs.onPrimary : (message.error ? sem.danger : null);
    const r = Radius.circular(18);
    const tight = Radius.circular(5);
    return Align(
      alignment: user ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: bg,
            border: user ? null : Border.all(color: message.error ? sem.danger.withAlpha(80) : sem.rule),
            borderRadius: BorderRadiusDirectional.only(
              topStart: r,
              topEnd: r,
              bottomStart: user ? tight : r,
              bottomEnd: user ? r : tight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, size: 16, color: sem.danger),
                    const SizedBox(width: 6),
                    Text('تعذّر الحصول على إجابة', style: TextStyle(color: sem.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ]),
                ),
              SelectableText(message.text, style: TextStyle(color: fg, height: 1.65)),
              if (message.actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final a in message.actions) _ActionCard(action: a),
                if (message.actions.where((a) => a.state == 'pending').length > 1)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () async {
                        final app = AppScope.read(context);
                        for (final a in message.actions.where((a) => a.state == 'pending').toList()) {
                          await app.executeAssistantAction(a);
                        }
                      },
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('تنفيذ كل الاقتراحات'),
                    ),
                  ),
              ],
              if (!user && !message.error) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (message.model.isNotEmpty)
                      Expanded(
                        child: Text(
                          '${message.model} · ${message.inputTokens + message.outputTokens} رمزاً',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: sem.muted, fontSize: 11),
                        ),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      tooltip: 'نسخ',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: message.text));
                        if (context.mounted) showToast(context, 'نُسخ النص');
                      },
                    ),
                    if (onSaveIdea != null)
                      IconButton(
                        tooltip: 'حفظ كفكرة تطوير',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                        onPressed: onSaveIdea,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة اقتراح تعديل من المساعد: ما سيتغير، وزر التنفيذ أو التجاهل.
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final AssistantAction action;

  static const Map<String, String> _labels = {
    'project_id': 'العقد',
    'work_id': 'البند',
    'extract_id': 'المستخلص',
    'form_key': 'النموذج',
    'contract_value': 'القيمة التعاقدية',
    'executed_value': 'المنفذ',
    'kind': 'النوع',
    'amount': 'القيمة',
    'title': 'العنوان',
    'ref_no': 'الرقم',
    'approved_on': 'تاريخ الاعتماد',
    'period_from': 'بداية الفترة',
    'period_to': 'نهاية الفترة',
    'submitted_on': 'تاريخ التقديم',
    'gross': 'قيمة الأعمال',
    'retention': 'التأمين المحتجز',
    'advance': 'استرداد الدفعة المقدمة',
    'penalties': 'الغرامات',
    'taxes': 'الضرائب والرسوم',
    'other': 'استقطاعات أخرى',
    'status': 'الحالة',
    'paid_amount': 'المدفوع',
    'paid_on': 'تاريخ الدفع',
    'contract_no': 'رقم العقد',
    'key': 'الإعداد',
    'value': 'القيمة الجديدة',
    'body': 'التفاصيل',
    'category': 'التصنيف',
    'priority': 'الأولوية',
  };

  String _value(AppState app, String k, Object? v) {
    final s = v?.toString() ?? '';
    switch (k) {
      case 'project_id':
        return app.project(s)?.contractTitle ?? 'عقد غير موجود';
      case 'work_id':
        final w = app.work(s);
        return w == null ? 'بند غير موجود' : (w.title.isEmpty ? w.company : w.title);
      case 'extract_id':
        for (final x in app.extracts) {
          if (x.id == s) return '${app.project(x.projectId)?.contractTitle ?? ''} · ${x.title}';
        }
        return 'مستخلص غير موجود';
      case 'form_key':
        return app.formDef(s)?.name ?? s;
      case 'kind':
        return switch (s) { 'add' => 'زيادة', 'deduct' => 'نقص', 'final' => 'ختامي', 'interim' => 'جاري', _ => s };
      case 'status':
        return extractStatusLabels[s] ?? parseStatus(s).label;
      case 'key':
        return settingLabels[s] ?? s;
    }
    if (v is num) return '${fmtMoney(v.toDouble())}${k == 'value' ? '' : ' $currencyLabel'}';
    if (v is Map || v is List) return v.toString();
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final a = action;
    final entries = a.input.entries.where((e) => e.key != 'summary' && e.value != null && e.value.toString().isNotEmpty).toList();
    final (color, badge) = switch (a.state) {
      'done' => (sem.ok, 'نُفّذ'),
      'failed' => (sem.danger, 'تعذّر التنفيذ'),
      'dismissed' => (sem.muted, 'تُجوهل'),
      'running' => (sem.wip, 'جارٍ التنفيذ'),
      _ => (cs.primary, 'بانتظار قرارك'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: sem.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.edit_note_rounded, size: 18, color: color),
          const SizedBox(width: 6),
          Text('اقتراح: ${a.title}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const Spacer(),
          ToneBadge(badge, color: color),
        ]),
        if (a.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(a.summary, style: const TextStyle(height: 1.5)),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 2, children: [
          for (final e in entries)
            Text('${_labels[e.key] ?? e.key}: ${_value(app, e.key, e.value)}',
                style: TextStyle(color: sem.muted, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        if (a.result != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(a.result!, style: TextStyle(color: a.state == 'failed' ? sem.danger : sem.ok, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        if (a.state == 'pending' || a.state == 'failed' || a.state == 'running')
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (a.state != 'running')
              TextButton(onPressed: () => app.dismissAssistantAction(a), child: const Text('تجاهل')),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: a.state == 'running' ? null : () => app.executeAssistantAction(a),
              icon: a.state == 'running'
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(a.state == 'failed' ? 'إعادة المحاولة' : 'تنفيذ'),
            ),
          ]),
      ]),
    );
  }
}
