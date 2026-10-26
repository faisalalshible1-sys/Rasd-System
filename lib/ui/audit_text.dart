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
    case 'user.claim_director':
      return 'تولّى إدارة المنظومة (${e.projectLabel})';
    case 'form_def.update':
      return 'عدّل صلاحيات نموذج «${e.projectLabel}»';
    case 'system.import':
      return 'استيراد المشاريع من ملف Excel';
    default:
      return auditActionLabels[e.action] ?? e.action;
  }
}
