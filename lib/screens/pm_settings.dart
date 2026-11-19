import 'package:flutter/material.dart';

import '../app_state.dart';
import '../pm.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

// =====================================================================
// القوائم والإعدادات (pm.config)، والدليل وإطار الحوكمة
// =====================================================================
class PmSettingsPage extends StatelessWidget {
  const PmSettingsPage({super.key});

  Future<void> _save(BuildContext context, AppState app, Map<String, dynamic> patch, String done) async {
    final next = Map<String, dynamic>.from(app.pmConfig.raw)..addAll(patch);
    try {
      await app.setSetting('pm.config', next);
      if (context.mounted) showToast(context, done);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editThresholds(BuildContext context, AppState app) async {
    final c = app.pmConfig;
    await showPmForm(
      context,
      title: 'الحدود والتنبيهات',
      note: 'SPI = الإنجاز الفعلي ÷ المخطط. الحدود الثلاثة تحدد «متقدم» و«ضمن المخطط» و«تأخر بسيط»، وما دون الأخير «متأخر حرج».',
      sections: const [
        PmSection('مؤشر أداء الجدول', [
          PmField('spi_ahead', 'حد «متقدم» لـ SPI', PmKind.decimal, required: true, helper: 'مثل 1.05'),
          PmField('spi_ok', 'حد «ضمن المخطط»', PmKind.decimal, required: true, helper: 'مثل 0.95'),
          PmField('spi_warn', 'حد «تأخر بسيط» (أقل منه = متأخر حرج)', PmKind.decimal, required: true, helper: 'مثل 0.85'),
        ]),
        PmSection('التنبيهات', [
          PmField('alert_days', 'أيام التنبيه قبل موعد المراجعة / الحل', PmKind.integer, required: true),
          PmField('stale_days', 'أيام دون تحديث للتقدم قبل التنبيه', PmKind.integer, required: true),
          PmField('forecast_delay_alert', 'تأخير متوقع يستوجب التنبيه (يوم)', PmKind.integer, required: true),
          PmField('change_limit', 'حد التنبيه لنسبة التغييرات المعتمدة من قيمة العقد', PmKind.percent, required: true,
              helper: 'افتراض قابل للتعديل وفق اللوائح المعتمدة'),
          PmField('change_decide_days', 'المدة المستهدفة للبت في طلب التغيير (يوم)', PmKind.integer, required: true),
          PmField('issue_days', 'المدة المستهدفة لحل المشكلة (يوم)', PmKind.integer, required: true),
          PmField('ref_date', 'تاريخ الإسناد اليدوي', PmKind.date,
              helper: 'فارغ = تاريخ اليوم. لإعداد تقرير بتاريخ سابق أو لتجميد الحسابات عند تاريخ محدد'),
        ]),
      ],
      values: {
        'spi_ahead': c.spiAhead,
        'spi_ok': c.spiOk,
        'spi_warn': c.spiWarn,
        'alert_days': c.alertDays,
        'stale_days': c.staleDays,
        'forecast_delay_alert': c.forecastDelayAlert,
        'change_limit': c.changeLimit,
        'change_decide_days': c.changeDecideDays,
        'issue_days': c.issueDays,
        'ref_date': c.refDate,
      },
      onSave: (d) async {
        final patch = Map<String, dynamic>.from(d);
        patch['ref_date'] = (d['ref_date'] as String).isEmpty ? null : d['ref_date'];
        await app.setSetting('pm.config', Map<String, dynamic>.from(app.pmConfig.raw)..addAll(patch));
      },
    );
  }

  Future<void> _editWeights(BuildContext context, AppState app) async {
    final c = app.pmConfig;
    await showPmForm(
      context,
      title: 'أوزان مؤشر الأداء المركّب للشركات',
      note: 'مجموع الأوزان الأربعة يجب أن يساوي 100%. عند غياب بيانات أحد المكونات يُعاد توزيع وزنه على الباقي.',
      sections: const [
        PmSection('الأوزان', [
          PmField('w_schedule', 'الالتزام بالبرنامج الزمني (متوسط SPI)', PmKind.percent, required: true),
          PmField('w_delay', 'التأخير المنسوب للشركة', PmKind.percent, required: true),
          PmField('w_field', 'التقييم الميداني الدوري', PmKind.percent, required: true),
          PmField('w_response', 'سرعة حل المشاكل المسندة للشركة', PmKind.percent, required: true),
        ]),
        PmSection('نقاط الصفر', [
          PmField('spi_zero', 'قيمة SPI التي تكون عندها درجة الالتزام صفراً', PmKind.decimal, required: true, helper: 'SPI ≥ 1 = 100 درجة'),
          PmField('delay_zero', 'نسبة التأخير المنسوب التي تكون عندها الدرجة صفراً', PmKind.percent, required: true,
              helper: 'لا تأخير منسوب = 100 درجة'),
        ]),
        PmSection('شرط إصدار الدرجة', [
          PmField('kpi_min_components', 'الحد الأدنى لعدد مكونات التقييم (من 4)', PmKind.integer, required: true,
              helper: 'ويُشترط معه توفر التقييم الميداني أو قياسات التقدم؛ وإلا «بيانات غير كافية»'),
        ]),
      ],
      values: {
        'w_schedule': c.weight('schedule'),
        'w_delay': c.weight('delay'),
        'w_field': c.weight('field'),
        'w_response': c.weight('response'),
        'spi_zero': c.spiZero,
        'delay_zero': c.delayZero,
        'kpi_min_components': c.kpiMinComponents,
      },
      onSave: (d) async {
        final w = {
          'schedule': d['w_schedule'] as double,
          'delay': d['w_delay'] as double,
          'field': d['w_field'] as double,
          'response': d['w_response'] as double,
        };
        final sum = w.values.fold<double>(0, (a, b) => a + b);
        if ((sum - 1).abs() > 0.001) throw 'مجموع الأوزان ${(sum * 100).toStringAsFixed(1)}% ويجب أن يساوي 100%';
        final minC = d['kpi_min_components'] as int;
        if (minC < 1 || minC > 4) throw 'الحد الأدنى لمكونات التقييم من 1 إلى 4';
        await app.setSetting('pm.config', Map<String, dynamic>.from(app.pmConfig.raw)
          ..addAll({'weights': w, 'spi_zero': d['spi_zero'], 'delay_zero': d['delay_zero'], 'kpi_min_components': minC}));
      },
    );
  }

  Future<void> _editGrades(BuildContext context, AppState app) async {
    final g = app.pmConfig.grades;
    await showPmForm(
      context,
      title: 'جدول تقدير الشركات',
      note: 'حسب الدرجة المركّبة (0–100). يبدأ الجدول من الصفر، و«من درجة» تصاعدية.',
      sections: [
        for (var i = 0; i < g.length; i++)
          PmSection('التقدير ${i + 1}', [
            PmField('min_$i', 'من درجة', PmKind.integer, required: true, enabled: i > 0),
            PmField('name_$i', 'التقدير', PmKind.text, required: true, max: 30),
            PmField('rec_$i', 'التوصية للإسناد المستقبلي', PmKind.text, max: 120, full: true),
          ]),
      ],
      values: {
        for (var i = 0; i < g.length; i++) ...{'min_$i': g[i].min.round(), 'name_$i': g[i].name, 'rec_$i': g[i].rec},
      },
      onSave: (d) async {
        final out = [
          for (var i = 0; i < g.length; i++) {'min': i == 0 ? 0 : d['min_$i'], 'name': d['name_$i'], 'rec': d['rec_$i']},
        ];
        await app.setSetting('pm.config', Map<String, dynamic>.from(app.pmConfig.raw)..addAll({'grades': out}));
      },
    );
  }

  Future<void> _editList(BuildContext context, AppState app, String key, String title, List<String> current) async {
    final res = await textInputDialog(
      context,
      title: title,
      message: 'قيمة في كل سطر. الإضافة والتعديل يسريان على القوائم المنسدلة فوراً، ولا يتغير ما سُجّل سابقاً.',
      label: title,
      confirmLabel: 'حفظ',
      initial: current.join('\n'),
    );
    if (res == null || !context.mounted) return;
    final list = [for (final l in res.split('\n')) if (l.trim().isNotEmpty) l.trim()];
    await _save(context, app, {key: list}, 'حُفظت القائمة');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'القوائم والإعدادات');
    final sem = Sem.of(context);
    final c = app.pmConfig;
    final can = app.isDirector;
    Widget editBtn(VoidCallback onTap) =>
        can ? IconButton.filledTonal(tooltip: 'تعديل', onPressed: onTap, icon: const Icon(Icons.edit_outlined)) : const SizedBox.shrink();
    Widget listCard(String key, String title, List<String> values, IconData icon) => SectionCard(
          title: title,
          icon: icon,
          trailing: editBtn(() => _editList(context, app, key, title, values)),
          child: Wrap(spacing: 6, runSpacing: 6, children: [for (final v in values) ToneBadge(v, color: sem.muted)]),
        );
    return PageBody(
      maxWidth: 1200,
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'القوائم والإعدادات',
          subtitle: 'القوائم المنسدلة والحدود والأوزان وجدول التقدير. يعدّلها مدير المكتب، وتسري فوراً على كل المستخدمين وتُسجَّل في سجل التدقيق.',
          icon: Icons.tune_rounded,
        ),
        if (!can)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: InfoBanner(text: 'للاطلاع فقط؛ التعديل من صلاحية مدير المكتب.', level: 'info'),
          ),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'الحدود والتنبيهات',
            icon: Icons.notifications_outlined,
            trailing: editBtn(() => _editThresholds(context, app)),
            child: Column(children: [
              PmKv('حد «متقدم» لـ SPI', spiText(c.spiAhead)),
              PmKv('حد «ضمن المخطط»', spiText(c.spiOk)),
              PmKv('حد «تأخر بسيط» (أقل منه = متأخر حرج)', spiText(c.spiWarn)),
              PmKv('أيام التنبيه قبل موعد المراجعة / الحل', '${c.alertDays}'),
              PmKv('أيام دون تحديث للتقدم قبل التنبيه', '${c.staleDays}'),
              PmKv('تأخير متوقع يستوجب التنبيه', '${c.forecastDelayAlert} يوم'),
              PmKv('حد التنبيه لنسبة التغييرات', pctText(c.changeLimit)),
              PmKv('المدة المستهدفة للبت في طلب التغيير', '${c.changeDecideDays} يوم'),
              PmKv('المدة المستهدفة لحل المشكلة', '${c.issueDays} يوم'),
              PmKv('تاريخ الإسناد المعتمد في الحسابات', c.refDate == null ? 'تاريخ اليوم' : pmDay(c.refDate)),
            ]),
          ),
          SectionCard(
            title: 'مؤشر الأداء المركّب للشركات',
            icon: Icons.balance_rounded,
            trailing: editBtn(() => _editWeights(context, app)),
            child: Column(children: [
              PmKv('الالتزام بالبرنامج الزمني', pctText(c.weight('schedule'))),
              PmKv('التأخير المنسوب للشركة', pctText(c.weight('delay'))),
              PmKv('التقييم الميداني الدوري', pctText(c.weight('field'))),
              PmKv('سرعة حل المشاكل', pctText(c.weight('response'))),
              PmKv('SPI عند درجة الصفر', spiText(c.spiZero)),
              PmKv('نسبة التأخير عند درجة الصفر', pctText(c.delayZero)),
              PmKv('الحد الأدنى لمكونات التقييم لإصدار الدرجة', '${c.kpiMinComponents} من 4'),
            ]),
          ),
          SectionCard(
            title: 'جدول تقدير الشركات',
            icon: Icons.military_tech_outlined,
            trailing: editBtn(() => _editGrades(context, app)),
            child: Column(children: [
              for (final g in c.grades) PmKv('من ${g.min.toStringAsFixed(0)}: ${g.name}', g.rec),
            ]),
          ),
          listCard('project_types', 'أنواع المشاريع', c.projectTypes, Icons.category_outlined),
          listCard('departments', 'أقسام المكتب (للقوائم)', c.departments, Icons.apartment_outlined),
          listCard('delay_causes', 'أسباب التأخير الرئيسية', c.delayCauses, Icons.hourglass_bottom_rounded),
          listCard('change_types', 'أنواع التغيير', c.changeTypes, Icons.change_circle_outlined),
          listCard('change_reasons', 'أسباب التغيير', c.changeReasons, Icons.help_outline_rounded),
          listCard('lesson_apply', 'آلية تعميم الدرس', c.lessonApply, Icons.campaign_outlined),
          SectionCard(
            title: 'قوائم ثابتة مستخدمة في الحسابات',
            icon: Icons.lock_outline_rounded,
            subtitle: 'لا تُعدَّل لأن الحسابات تعتمد عليها.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (t, l) in [
                ('الوضع التشغيلي', opStatusLabels.values),
                ('الجهة المسؤولة', pmPartyLabels.values),
                ('التصنيف التعاقدي للتأخير', delayClassLabels.values),
                ('مصدر التغيير', changeSourceLabels.values),
                ('حالات التغيير', changeStatusLabels.values),
                ('حالات المشاكل', issueStatusLabels.values),
                ('نوع الدرس', lessonTypeLabels.values),
                ('حالة تطبيق الدرس', lessonStatusLabels.values),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('$t: ${l.join('، ')}', style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.5)),
                ),
              Text('قوائم المخاطر (المراحل، التصنيفات، الأقسام المالكة، منفذو الإجراءات) ومعايير المستويات في «مصفوفة المخاطر».',
                  style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ]),
          ),
        ]),
      ],
    );
  }
}

// =====================================================================
// دليل الاستخدام وإطار حوكمة إدارة المخاطر ومتابعة المشاريع
// =====================================================================
class PmGuidePage extends StatelessWidget {
  const PmGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final rc = app.riskConfig;
    final fw = app.pmConfig.raw['framework'];
    final status = fw is Map ? '${fw['version'] ?? '2.0'} · ${fw['status'] ?? ''}' : '2.0';
    Widget p(String s) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s, style: const TextStyle(height: 1.6)));
    Widget bullet(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 8), child: Icon(Icons.circle, size: 6, color: sem.muted)),
            const SizedBox(width: 8),
            Expanded(child: Text(s, style: const TextStyle(height: 1.6))),
          ]),
        );
    return PageBody(
      maxWidth: 1100,
      children: [
        PageHeader(
          title: 'دليل الاستخدام وإطار الحوكمة',
          subtitle: 'إدارة المخاطر ومتابعة المشاريع · الإصدار $status',
          icon: Icons.menu_book_rounded,
        ),
        SectionCard(
          title: '١. الغرض والنطاق',
          icon: Icons.flag_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            p('يوحّد هذا القسم متابعة مشاريع إعادة الإعمار في سجل واحد مترابط مع العقود والدورة المستندية: البرنامج الزمني والإنجاز (المخطط مقابل الفعلي)، '
                'والمخاطر ومراجعاتها، والمشاكل، وأحداث التأخير وأسبابها، والتغييرات وأثرها، والدروس المستفادة، وأداء الشركات المنفذة.'),
            p('ينطبق على جميع المشاريع التي يشرف عليها المكتب بأقسامه الأربعة، من مرحلة التخطيط حتى انتهاء فترة الضمان.'),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '٢. خريطة القسم',
          icon: Icons.map_outlined,
          child: PmTable(
            columns: const ['الصفحة', 'الغرض', 'المسؤول عن التحديث', 'الدورية'],
            rows: const [
              ['لوحة القيادة', 'نظرة موحدة: مؤشرات، تنبيهات، ملخص المشاريع، رسوم', '—', 'تلقائي'],
              ['لوحة العرض', 'ملخص المحفظة في صفحة واحدة للعرض التقديمي والطباعة (تُحفظ صورةً)', '—', 'تلقائي'],
              ['سجل المشاريع', 'البرنامج الزمني ومؤشرات الإنجاز لكل عقد', 'مكتب المدير + القسم المشرف', 'عند التعاقد وأي تعديل'],
              ['التقدم الدوري', 'قياسات الإنجاز التراكمي المخطط والفعلي', 'الإشراف والتنسيق / القسم المشرف', 'أسبوعياً كل خميس'],
              ['سجل المخاطر', 'تعريف المخاطر وتقييمها وخطط معالجتها ومراجعاتها', 'مالك الخطر (رئيس القسم)', 'عند ظهور خطر وحسب مستواه'],
              ['مصفوفة المخاطر', 'معايير التصنيف ومسار التصعيد ودورية المراجعة', 'مدير المكتب', 'عند تعديل المعايير'],
              ['سجل المشاكل', 'المشاكل الواقعة وحلولها ومواعيدها', 'القسم المتابع', 'فور الرصد + مراجعة أسبوعية'],
              ['التأخيرات وأسبابها', 'أحداث التأخير والجهة المسؤولة والتمديدات، وباريتو الأسباب', 'الإشراف والتنسيق + الشؤون الفنية', 'عند بدء الحدث وانتهائه'],
              ['سجل التغييرات', 'طلبات التغيير وأثرها المالي والزمني والبت فيها', 'الشؤون الفنية (والبت لمكتب العقود والمدير)', 'عند التقديم وعند البت'],
              ['الدروس المستفادة', 'توثيق الدروس وتعميمها', 'جميع الأقسام', 'عند كل حدث مهم وإغلاق كل مرحلة'],
              ['تقييم الشركات', 'التقييم الميداني (6 معايير) ومؤشرات الأداء والدرجة المركّبة', 'القسم المشرف', 'ربع سنوي (شهري للمتعثرة)'],
              ['التقرير الدوري', 'التقرير الأسبوعي أو الشهري', 'مكتب المدير', 'أسبوعياً / شهرياً'],
              ['القوائم والإعدادات', 'القوائم والحدود والأوزان وجدول التقدير', 'مدير المكتب', 'عند الحاجة'],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '٣. الأدوار والمسؤوليات',
          icon: Icons.groups_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bullet('مدير المكتب: اعتماد هذا الإطار والمعايير؛ البت في المخاطر المصعّدة؛ رفع المخاطر المرتفعة جداً إلى اللجنة؛ اعتماد التقارير الدورية وإغلاق المخاطر التي كانت مرتفعة؛ رئاسة اجتماع المراجعة الشهري.'),
            bullet('قسم الإشراف والتنسيق: إدخال قياسات التقدم أسبوعياً بعد التحقق الميداني؛ رصد المشاكل وأحداث التأخير الميدانية؛ ملكية مخاطر التنفيذ والسلامة والموقع؛ التقييم الميداني للشركات.'),
            bullet('قسم الشؤون الفنية: ملكية مخاطر التصميم والدراسات والتعاقد؛ دراسة طلبات التغيير وتقدير أثرها؛ مراجعة التصنيف التعاقدي لأحداث التأخير وطلبات التمديد.'),
            bullet('قسم الترميم: ملكية مخاطر المباني التراثية وأعمال الترميم؛ تسجيل مشاكلها وتأخيراتها؛ التقييم الميداني لشركات الترميم.'),
            bullet('قسم المطابقة والاستلام: ملكية مخاطر الجودة والاستلام؛ تسجيل ملاحظات الجودة؛ توثيق الدروس المستفادة عند الاستلام الابتدائي والنهائي.'),
            bullet('مكتب المدير: إدارة القوائم والإعدادات؛ تدقيق جودة البيانات أسبوعياً («تحقق البيانات» وتنبيهات لوحة القيادة)؛ استخراج التقريرين الأسبوعي والشهري؛ أمانة اجتماعات المراجعة؛ اعتماد الدروس المستفادة.'),
            bullet('مكتب العقود والتوريدات والمستخلصات: البت في طلبات التغيير؛ والمعتمد منها بأثر مالي يصبح أمر تغيير في مالية العقد تلقائياً.'),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '٤. مسار التصعيد ودورية المراجعة',
          icon: Icons.escalator_warning_outlined,
          subtitle: 'مرتبط آلياً بمصفوفة المخاطر: موعد المراجعة القادمة = تاريخ آخر مراجعة + دورية المراجعة حسب المستوى الحالي.',
          child: PmTable(
            columns: const ['المستوى', 'نطاق الدرجة', 'الاستجابة ومسار التصعيد', 'دورية المراجعة', 'النشطة حالياً'],
            rows: [
              for (var i = rc.levels.length - 1; i >= 0; i--)
                [
                  rc.levels[i].name,
                  '${rc.levels[i].min} – ${rc.maxOf(i)}',
                  rc.levels[i].action,
                  '${rc.reviewDaysFor(rc.levels[i].min)} يوم',
                  '${app.v7Ready ? app.pm.riskList.where((s) => s.isActive && rc.levelIndex(s.currentScore) == i).length : 0}',
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '٥. معايير إغلاق الخطر',
          icon: Icons.task_alt_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            bullet('تنفيذ الإجراء الوقائي بنسبة 100% وتوثيقه في آخر مراجعة.'),
            bullet('أن تكون الدرجة الحالية (من آخر مراجعة) مساوية للدرجة المستهدفة أو أقل منها.'),
            bullet('إدخال تاريخ الإغلاق وتغيير الحالة إلى «مغلق».'),
            bullet('اعتماد الإغلاق من مالك الخطر، ومن مدير المكتب للمخاطر التي كان تقييمها الأولي مرتفعاً أو مرتفعاً جداً.'),
            bullet('توثيق الدرس المستفاد في «الدروس المستفادة» إن وُجد.'),
            p('تتحقق المنظومة آلياً من المعايير ١–٣ وتُظهر «إغلاق غير مستوفٍ للمعايير» في «تحقق البيانات» عند مخالفتها.'),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '٦. قواعد الترميز والإدخال',
          icon: Icons.tag_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PmTable(
              columns: const ['السجل', 'صيغة الرمز', 'مثال', 'ملاحظة'],
              rows: const [
                ['المشاريع', 'رقم التكليف / رقم العقد', '—', 'المشروع هو العقد نفسه في الدورة المستندية'],
                ['المخاطر', 'R + رقمين', 'R01', 'لا يُعاد استخدام رمز خطر مغلق؛ «عام» للمخاطر على مستوى المحفظة'],
                ['المشاكل', 'I + رقمين', 'I01', 'اربط المشكلة بالخطر الذي تحقق إن وُجد'],
                ['التأخيرات', 'D + رقمين', 'D01', ''],
                ['التغييرات', 'C + رقمين', 'C01', 'المعتمد بأثر مالي = أمر تغيير في مالية العقد'],
                ['الدروس', 'L + رقمين', 'L01', ''],
              ],
            ),
            const SizedBox(height: 10),
            bullet('الرموز تُولَّد تلقائياً بالتسلسل عند الحفظ.'),
            bullet('السجلات التاريخية (التقدم الدوري، مراجعات المخاطر، التقييم الدوري) يُضاف إليها سجل جديد في كل مرة ولا يُكتب فوق السابق؛ التعديل للتصحيح فقط ويُسجَّل في سجل التدقيق.'),
            bullet('نسب الإنجاز تراكمية من بداية المشروع، والمخطط يُؤخذ من البرنامج الزمني المعتمد (خط الأساس) في تاريخ القياس.'),
            bullet('التمديد الناتج عن أمر تغيير يُسجَّل في «سجل التغييرات» فقط، وبقية التمديدات في «سجل التأخيرات»، لتجنب احتسابه مرتين.'),
            bullet('جميع الحسابات تعتمد «تاريخ الإسناد» (تاريخ اليوم افتراضياً)، ويمكن تثبيته بتاريخ محدد من «القوائم والإعدادات».'),
            bullet('اسم العقد وشركته وقيمته وقسمه المشرف تُقرأ من بيانات العقد في الدورة المستندية؛ تعديلها هناك يكفي.'),
            bullet('الإضافة والتعديل لكل الأعضاء عدا CISO (للاطلاع)، والبت في التغييرات لمكتب العقود والمدير، واعتماد الدروس لمكتب المدير، والحذف لمدير المكتب وحده. كل عملية في سجل التدقيق.'),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '٧. دورة العمل الأسبوعية والشهرية',
          icon: Icons.event_repeat_rounded,
          child: PmTable(
            columns: const ['التوقيت', 'الإجراء', 'المسؤول'],
            rows: const [
              ['كل خميس', 'إدخال قياسات التقدم؛ تحديث المشاكل والتأخيرات؛ تسجيل المراجعات المستحقة', 'الأقسام'],
              ['كل خميس', 'مراجعة «أبرز التنبيهات» في لوحة القيادة و«تحقق البيانات»', 'مكتب المدير'],
              ['كل خميس', 'استخراج التقرير الأسبوعي وكتابة الملاحظات والتوصيات', 'مكتب المدير'],
              ['أول 5 أيام عمل من الشهر', 'التقرير الشهري (تاريخ من الشهر السابق) واجتماع المراجعة', 'مدير المكتب'],
              ['كل ربع سنة', 'التقييم الميداني للشركات ومراجعة «مؤشرات أداء الشركات» والدروس المقترحة', 'الأقسام + المدير'],
            ],
          ),
        ),
      ],
    );
  }
}
