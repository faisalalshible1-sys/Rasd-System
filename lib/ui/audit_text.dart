import '../app_state.dart';
import '../models.dart';
import '../registers.dart';

/// وصف سطر من سجل التدقيق بلغة مفهومة.
String auditDescription(AppState app, AuditEntry e) {
  final d = e.detail;
  final form = e.formKey == null ? '' : (app.formDef(e.formKey!)?.name ?? e.formKey!);
  String st(Object? v) => parseStatus(v).label;
  String text(Object? v) => v == null ? '' : v.toString();

  switch (e.action) {
    case 'form.set':
      final by = text(d['approved_by_name']);
      return '«$form»: ${st(d['from'])} ← ${st(d['to'])}${by.isNotEmpty ? ' (باعتماد $by)' : ''}';
    case 'request.create':
      final note = text(d['note']);
      return 'طلب اعتماد تغيير «$form» إلى «${st(d['to'])}»${note.isNotEmpty ? ' — $note' : ''}';
    case 'request.approve':
      return 'اعتمد تغيير «$form» إلى «${st(d['to'])}» بطلب من ${text(d['requested_by_name'])}';
    case 'request.reject':
      final note = text(d['note']);
      return 'رفض تغيير «$form» إلى «${st(d['to'])}»${note.isNotEmpty ? ' — السبب: $note' : ''}';
    case 'request.withdraw':
      return 'سحب طلب اعتماد «$form»';
    case 'project.create':
      return 'أنشأ المشروع ${e.projectLabel}';
    case 'project.delete':
      return 'حذف المشروع ${e.projectLabel}';
    case 'project.update':
      final fields = d.keys.map((k) => projectFieldLabels[k] ?? k).join('، ');
      return 'عدّل: $fields';
    case 'note.add':
      return 'أضاف ملاحظة تقييم: ${text(d['body'])}';
    case 'user.activate':
    case 'user.update':
    case 'user.deactivate':
      final roleTo = d['role'] is Map ? parseRole((d['role'] as Map)['to'])?.label : null;
      final verb = e.action == 'user.activate'
          ? 'فعّل حساب'
          : e.action == 'user.deactivate'
              ? 'أوقف حساب'
              : 'عدّل صلاحيات';
      return '$verb ${e.projectLabel}${roleTo != null && e.action != 'user.deactivate' ? ' — $roleTo' : ''}';
    case 'user.email':
      return 'غيّر بريد الدخول لـ ${e.projectLabel}: ${text(d['from'])} ← ${text(d['to'])}';
    case 'user.delete':
      final email = text(d['email']);
      final n = (d['withdrawn_requests'] as num?)?.toInt() ?? 0;
      return 'حذف حساب ${e.projectLabel}${email.isNotEmpty && email != e.projectLabel ? ' ($email)' : ''} نهائياً'
          '${n > 0 ? ' وسُحب $n طلب معلّق له' : ''}';
    case 'user.claim_director':
      return 'تولّى إدارة المنظومة (${e.projectLabel})';
    case 'form_def.update':
      return 'عدّل صلاحيات نموذج «${e.projectLabel}»';
    case 'system.import':
      return 'استيراد المشاريع من ملف Excel';
    case 'project.field':
      return 'عدّل «${text(d['label'])}»: ${d['from'] == null ? '—' : text(d['from'])} ← ${d['to'] == null ? '—' : text(d['to'])}';
    case 'setting.update':
    case 'security.setting':
      return 'عدّل إعداد «${settingLabels[text(d['key'])] ?? text(d['key'])}»';
    case 'security.session_revoke':
      return 'أنهى جلسة لـ ${e.projectLabel}';
    case 'security.user_signout':
      return 'أخرج ${e.projectLabel} من كل أجهزته';
    case 'security.mfa_reset':
      return 'ألغى التحقق بخطوتين لـ ${e.projectLabel}';
    case 'config.stage':
      return d['from'] == null ? 'أضاف مرحلة «${text(d['to'])}»' : 'غيّر اسم مرحلة «${text(d['from'])}» إلى «${text(d['to'])}»';
    case 'config.stage_delete':
      return 'حذف مرحلة «${e.projectLabel}»';
    case 'config.form':
      return d['created'] == true ? 'أضاف نموذج «${e.projectLabel}»' : 'عدّل نموذج «${e.projectLabel}»';
    case 'config.form_delete':
      return 'حذف نموذج «${e.projectLabel}»';
    case 'config.form_order':
      return 'غيّر ترتيب النماذج';
    case 'config.department':
      return d['from'] == null ? 'أضاف قسم «${text(d['to'])}»' : 'غيّر اسم قسم «${text(d['from'])}» إلى «${text(d['to'])}»';
    case 'config.field':
      return 'عرّف حقلاً إضافياً «${e.projectLabel}»';
    case 'idea.create':
      return 'أرسل فكرة: ${e.projectLabel}';
    case 'idea.update':
      return 'حدّث فكرة: ${e.projectLabel}';
    case 'idea.delete':
      return 'حذف فكرة: ${e.projectLabel}';
    case 'contract.work_add':
      return 'أضاف عملاً: ${[text(d['title']), text(d['company'])].where((x) => x.isNotEmpty).join(' · ')}';
    case 'contract.work_update':
      final title = d['title'] is Map ? text((d['title'] as Map)['to']) : '';
      return 'عدّل عملاً في العقد${title.isNotEmpty ? ': $title' : ''}';
    case 'contract.work_delete':
      return 'حذف عملاً: ${[text(d['title']), text(d['company'])].where((x) => x.isNotEmpty).join(' · ')}';
    case 'contract.merge':
      final n = (d['count'] as num?)?.toInt() ?? 0;
      return 'دمج $n ${n == 1 ? 'عملاً' : 'أعمال'} في العقد';
    case 'contract.merged_into':
      return 'دُمج في ${text(d['target_label'])}';
    case 'contract.unmerge':
      return 'فكّ دمج ${text(d['source_label'])}';
    case 'engineer.add':
      return 'كلّف ${engineerKindLabel(text(d['kind']))}: ${text(d['name'])}${text(d['assign_no']).isNotEmpty ? ' (رقم ${text(d['assign_no'])})' : ''}';
    case 'engineer.update':
      final name = d['name'] is Map ? text((d['name'] as Map)['to']) : '';
      final no = d['assign_no'] is Map ? text((d['assign_no'] as Map)['to']) : '';
      return 'عدّل تكليف ${engineerKindLabel(text(d['kind']))}: $name${no.isNotEmpty ? ' (رقم $no)' : ''}';
    case 'engineer.delete':
      return 'ألغى تكليف ${engineerKindLabel(text(d['kind']))}: ${text(d['name'])}';
    case 'engineer.set':
      return 'حدّث ${engineerKindPlural(text(d['kind']))}: ${text(d['to']).isEmpty ? '—' : text(d['to'])}';
    case 'ai.ask':
      final tokens = ((d['input_tokens'] as num?)?.toInt() ?? 0) + ((d['output_tokens'] as num?)?.toInt() ?? 0);
      return 'سأل مساعد Claude (${text(d['model'])}${tokens > 0 ? ' · $tokens رمزاً' : ''})';
    case 'finance.work_values':
      String fromTo(Object? v) {
        if (v is! Map) return '';
        String m(Object? x) => x is num ? fmtMoney(x.toDouble()) : '—';
        return '${m(v['from'])} ← ${m(v['to'])}';
      }
      return 'عدّل قيم البند «${text(d['title'])}»: القيمة ${fromTo(d['contract_value'])}، المنفذ ${fromTo(d['executed_value'])}';
    case 'finance.variation_add':
      return 'سجّل أمر تغيير (${text(d['kind']) == 'deduct' ? 'نقص' : 'زيادة'}) «${text(d['title'])}» بقيمة ${_m(d['amount'])}';
    case 'finance.variation_update':
      final amt = d['amount'] is Map ? '${_m((d['amount'] as Map)['from'])} ← ${_m((d['amount'] as Map)['to'])}' : '';
      return 'عدّل أمر التغيير «${text(d['title'])}»${amt.isNotEmpty ? ': $amt' : ''}';
    case 'finance.variation_delete':
      return 'حذف أمر التغيير «${text(d['title'])}» (${_m(d['amount'])})';
    case 'finance.extract_add':
      return 'سجّل المستخلص رقم ${text(d['seq'])} (${extractStatusLabels[text(d['status'])] ?? text(d['status'])}) بقيمة ${_m(d['gross'])}، صافيه ${_m(d['net'])}';
    case 'finance.extract_update':
      final stFrom = d['status'] is Map ? extractStatusLabels[text((d['status'] as Map)['from'])] : null;
      final stTo = d['status'] is Map ? extractStatusLabels[text((d['status'] as Map)['to'])] : null;
      final paid = d['paid'] is Map ? _m((d['paid'] as Map)['to']) : '';
      return 'عدّل المستخلص رقم ${text(d['seq'])}${stFrom != null && stFrom != stTo ? ': $stFrom ← $stTo' : ''}${paid.isNotEmpty ? ' · المدفوع $paid' : ''}';
    case 'finance.extract_delete':
      return 'حذف المستخلص رقم ${text(d['seq'])} (${_m(d['gross'])})';
    case 'finance.payment_add':
      final ref = text(d['ref_no']);
      return 'سجّل دفعة ${_m(d['amount'])} على المستخلص رقم ${text(d['seq'])} (${paymentMethodLabels[text(d['method'])] ?? text(d['method'])}${ref.isNotEmpty ? ' $ref' : ''}) بتاريخ ${text(d['paid_on']).replaceAll('-', '/')}';
    case 'finance.payment_delete':
      return 'حذف دفعة ${_m(d['amount'])} من المستخلص رقم ${text(d['seq'])}';
    case 'finance.advance':
      final to = d['amount'] is Map ? (d['amount'] as Map)['to'] : null;
      final from = d['amount'] is Map ? (d['amount'] as Map)['from'] : null;
      final on = d['paid_on'] is Map ? text((d['paid_on'] as Map)['to']) : '';
      if (to == null) return 'أزال الدفعة المقدمة للعقد (${_m(from)})';
      return 'الدفعة المقدمة للعقد: ${from == null ? '' : '${_m(from)} ← '}${_m(to)}${on.isNotEmpty ? ' · صُرفت ${on.replaceAll('-', '/')}' : ' · لم تُصرف'}';
    case 'security.user_lock':
      final until = text(d['until']);
      return 'قفل دخول ${e.projectLabel}${until.startsWith('infinity') ? ' حتى يُفك' : ''} — ${text(d['reason'])}';
    case 'security.user_unlock':
      return 'فكّ قفل دخول ${e.projectLabel}';
    case 'security.device_new':
      return 'دخل ${e.projectLabel} من جهاز جديد (${platformLabels[text(d['platform'])] ?? text(d['platform'])}${text(d['ip']).isNotEmpty ? ' · ${text(d['ip'])}' : ''})';
    case 'security.device_trust':
      return 'وثّق ${e.projectLabel} جهازه (${text(d['label'])})';
    case 'security.device_untrust':
      return 'أُلغي توثيق جهاز ${e.projectLabel} (${text(d['label'])})';
    case 'security.device_block':
      return 'حظر جهاز ${e.projectLabel} (${text(d['label'])})';
    case 'security.device_unblock':
      return 'رفع حظر جهاز ${e.projectLabel} (${text(d['label'])})';
    case 'security.device_blocked_attempt':
      return 'محاولة دخول من جهاز محظور لـ ${e.projectLabel}${text(d['ip']).isNotEmpty ? ' (${text(d['ip'])})' : ''}';
    case 'risk.create':
      return 'سجّل الخطر ${text(d['code'])}: ${text(d['description'])} (الدرجة ${text(d['score'])})';
    case 'risk.update':
      return 'عدّل الخطر ${text(d['code'])}${_changed(d['changes'])}';
    case 'risk.delete':
      return 'حذف الخطر ${text(d['code'])}: ${text(d['description'])}';
    case 'swot.factor':
      return text(d['op']) == 'create'
          ? 'أضاف عامل SWOT ${text(d['code'])}: ${text(d['factor'])}'
          : 'عدّل عامل SWOT ${text(d['code'])}${_changed(d['changes'])}';
    case 'swot.strategy':
      return text(d['op']) == 'create'
          ? 'أضاف الاستراتيجية ${text(d['code'])}: ${text(d['strategy'])}'
          : 'عدّل الاستراتيجية ${text(d['code'])}${_changed(d['changes'])}';
    case 'swot.action':
      return text(d['op']) == 'create'
          ? 'أضاف الإجراء ${text(d['code'])}: ${text(d['action'])}'
          : 'عدّل الإجراء ${text(d['code'])}${_changed(d['changes'])}';
    case 'swot.progress':
      final ch = d['changes'] is Map ? d['changes'] as Map : const {};
      final pr = ch['progress'] is Map ? (ch['progress'] as Map)['to'] : null;
      final stt = ch['status'] is Map ? actionStatusLabels[text((ch['status'] as Map)['to'])] : null;
      return 'حدّث إنجاز الإجراء ${text(d['code'])}${pr is num ? ': ${(pr * 100).round()}%' : ''}${stt != null ? ' · $stt' : ''}';
    case 'swot.delete':
      final item = switch (text(d['item'])) { 'factor' => 'العامل', 'strategy' => 'الاستراتيجية', _ => 'الإجراء' };
      return 'حذف $item ${text(d['code'])}: ${text(d['text'])}';
    case 'ai.action':
      return 'نفّذ اقتراح مساعد Claude: ${text(d['summary'])}';
    default:
      return auditActionLabels[e.action] ?? e.action;
  }
}

/// أسماء الحقول المعدلة في سجل المخاطر وتحليل SWOT.
const Map<String, String> _registerFields = {
  'code': 'الرمز',
  'description': 'الوصف',
  'cause': 'السبب',
  'effect': 'الأثر',
  'probability': 'الاحتمالية',
  'impact': 'التأثير',
  'residual_probability': 'الاحتمالية بعد المعالجة',
  'residual_impact': 'التأثير بعد المعالجة',
  'mitigation': 'الإجراء الوقائي',
  'response': 'الاستجابة',
  'owner': 'المسؤول',
  'status': 'الحالة',
  'next_review': 'موعد المراجعة',
  'target_date': 'الموعد المستهدف',
  'closed_on': 'تاريخ الإغلاق',
  'phase': 'المرحلة',
  'category': 'التصنيف',
  'project_group': 'المشروع',
  'project_id': 'العقد المرتبط',
  'early_warning': 'مؤشر الإنذار',
  'notes': 'الملاحظات',
  'kind': 'التصنيف',
  'factor': 'العامل',
  'importance': 'الأهمية',
  'urgency': 'الاستعجال',
  'rating': 'التقييم',
  'department': 'القسم',
  'evidence': 'مصدر التحقق',
  'strategy': 'الاستراتيجية',
  'internal_factors': 'العوامل الداخلية',
  'external_factors': 'العوامل الخارجية',
  'priority': 'الأولوية',
  'lead_department': 'القسم القائد',
  'action': 'الإجراء',
  'strategy_code': 'الاستراتيجية',
  'factors': 'العوامل',
  'output': 'المخرج',
  'kpi': 'المؤشر',
  'start_date': 'تاريخ البدء',
  'duration_months': 'المدة',
  'progress': 'الإنجاز',
  'verification': 'مصدر التحقق',
  'review_cycle': 'دورية المراجعة',
  'source': 'المصدر',
};

String _changed(Object? changes) {
  if (changes is! Map || changes.isEmpty) return '';
  final names = [for (final k in changes.keys) _registerFields[k.toString()] ?? k.toString()];
  return ': ${names.toSet().join('، ')}';
}

String _m(Object? v) => v is num ? '${fmtMoney(v.toDouble())} $currencyLabel' : '—';

/// أسماء الإعدادات كما تُعرض في السجل.
const Map<String, String> settingLabels = {
  'brand.app_title': 'اسم المنظومة',
  'brand.org_name': 'اسم الجهة',
  'brand.org_parent': 'الجهة الأم',
  'brand.primary_color': 'لون الهوية',
  'ui.announcement': 'الإعلان العام',
  'ui.status_labels': 'مسميات الحالات',
  'ui.features': 'الميزات',
  'ui.motion': 'الحركة والانتقالات',
  'ui.nav': 'القائمة الرئيسية',
  'ui.dashboard': 'أقسام الرئيسية',
  'ui.labels': 'المصطلحات',
  'ui.appearance': 'المظهر والرسوم البيانية',
  'ai.enabled': 'تشغيل مساعد Claude',
  'ai.model': 'نموذج مساعد Claude',
  'ai.instructions': 'تعليمات مساعد Claude',
  'finance.guarantee_initial_rate': 'نسبة الضمان الابتدائي',
  'finance.guarantee_final_rate': 'نسبة الضمان النهائي',
  'finance.currency': 'رمز العملة',
  'finance.retention_rate': 'نسبة التأمين الافتراضية',
  'finance.tax_rate': 'نسبة الضرائب الافتراضية',
  'finance.advance_recovery_rate': 'نسبة استرداد الدفعة المقدمة',
  'finance.deduction_types': 'أنواع الاستقطاعات المخصصة',
  'security.require_mfa_director': 'فرض التحقق على المدير',
  'security.require_mfa_all': 'فرض التحقق على الجميع',
  'security.idle_minutes': 'القفل التلقائي',
  'security.freeze': 'تجميد المنظومة',
  'security.signups_open': 'التسجيل الجديد',
  'risk.config': 'معايير سجل المخاطر وقوائمه',
  'swot.meta': 'بيانات وثيقة تحليل SWOT',
};
