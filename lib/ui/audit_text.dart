import '../app_state.dart';
import '../models.dart';

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
    default:
      return auditActionLabels[e.action] ?? e.action;
  }
}

/// أسماء الإعدادات كما تُعرض في السجل.
const Map<String, String> settingLabels = {
  'brand.app_title': 'اسم المنظومة',
  'brand.org_name': 'اسم الجهة',
  'brand.org_parent': 'الجهة الأم',
  'brand.primary_color': 'لون الهوية',
  'ui.announcement': 'الإعلان العام',
  'ui.status_labels': 'مسميات الحالات',
  'ui.features': 'الميزات',
  'finance.guarantee_initial_rate': 'نسبة الضمان الابتدائي',
  'finance.guarantee_final_rate': 'نسبة الضمان النهائي',
  'finance.currency': 'رمز العملة',
  'security.require_mfa_director': 'فرض التحقق على المدير',
  'security.require_mfa_all': 'فرض التحقق على الجميع',
  'security.idle_minutes': 'القفل التلقائي',
  'security.freeze': 'تجميد المنظومة',
  'security.signups_open': 'التسجيل الجديد',
};
