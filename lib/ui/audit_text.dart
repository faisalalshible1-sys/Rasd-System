import '../app_state.dart';
import '../docs.dart' show docCategoryLabel, fmtBytes;
import '../models.dart';
import '../rasd.dart' show grantLabel, sectionDefaultNames;
import '../registers.dart';
import '../units.dart';

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
    case 'user.rename':
      return 'غيّر اسمه في المنظومة: ${text(d['from'])} ← ${text(d['to'])}';
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
      final where = [_sectionName(d['section']), text(d['page'])].where((x) => x.isNotEmpty).join(' · ');
      return 'أرسل فكرة: ${e.projectLabel}${where.isEmpty ? '' : ' ($where)'}';
    case 'idea.move':
      String place(Object? v) {
        if (v is! Map) return 'عامة';
        final w = [_sectionName(v['section']), text(v['page'])].where((x) => x.isNotEmpty).join(' · ');
        return w.isEmpty ? 'عامة' : w;
      }
      return 'نقل الفكرة «${e.projectLabel}» من ${place(d['from'])} إلى ${place(d['to'])}';
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
      if (d['status'] == 'draft') {
        final both = d['added'] is num && d['deducted'] is num && (d['added'] as num) > 0 && (d['deducted'] as num) > 0;
        return 'سجّل أمر تغيير مسودة «${text(d['title'])}»: '
            '${both ? 'زيادة ${_m(d['added'])} ونقص ${_m(d['deducted'])}' : '${text(d['kind']) == 'deduct' ? 'نقص' : 'زيادة'} ${_m(d['amount'])}'}'
            '${d['items'] is num && (d['items'] as num) > 0 ? ' في ${d['items']} بنداً' : ''}';
      }
      return 'سجّل أمر تغيير (${text(d['kind']) == 'deduct' ? 'نقص' : 'زيادة'}) «${text(d['title'])}» بقيمة ${_m(d['amount'])}';
    case 'finance.variation_approve':
      final on = text(d['approved_on']).replaceAll('-', '/');
      return 'اعتمد أمر التغيير «${text(d['title'])}» (${_varNet(d)})${on.isNotEmpty ? ' بتاريخ $on' : ''}${text(d['note']).isNotEmpty ? ' — ${text(d['note'])}' : ''}';
    case 'finance.variation_reject':
      return 'رفض أمر التغيير «${text(d['title'])}» (${_varNet(d)}) — ${text(d['note'])}';
    case 'finance.variation_reopen':
      return 'أعاد أمر التغيير «${text(d['title'])}» إلى مسودة وأخرج أثره من قيمة العقد — ${text(d['note'])}';
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
    case 'finance.guarantees':
      return _guarantees(d);
    case 'committee.save':
      return _committee(d, deleted: false);
    case 'committee.delete':
      return _committee(d, deleted: true);
    case 'stores.setup':
    case 'stores.employee':
    case 'stores.item':
      return _storesEntity(e.action, d);
    case 'stores.settings':
      return _storesSettings(d);
    case 'stores.employees_import':
      return 'استورد ${text(d['rows'])} صفاً من الموظفين: أُضيف ${text(d['inserted'])} وحُدّث ${text(d['updated'])}'
          '${(d['departments'] as num? ?? 0) > 0 ? ' وأُنشئت ${text(d['departments'])} إدارة' : ''}';
    case 'stores.items_import':
      return 'استورد ${text(d['rows'])} صفاً من الأصناف: أُضيف ${text(d['inserted'])} وحُدّث ${text(d['updated'])}'
          '${(d['units'] as num? ?? 0) > 0 ? ' وأُنشئت ${text(d['units'])} وحدة' : ''}';
    case 'stores.doc_save':
      final doc = d['doc'] is Map ? d['doc'] as Map : const {};
      final n = doc['lines'] is List ? (doc['lines'] as List).length : 0;
      return '${d['op'] == 'create' ? 'أنشأ' : 'عدّل'} ${_stKind(doc['kind'], doc['reverses_id'])} ${e.projectLabel} ($n بند)';
    case 'stores.doc_submit':
    case 'stores.doc_return':
    case 'stores.doc_reject':
    case 'stores.doc_approve':
    case 'stores.doc_post':
    case 'stores.doc_cancel':
      return _storesDocAction(e.action, d, e.projectLabel);
    case 'stores.doc_delete':
      final doc = d['doc'] is Map ? d['doc'] as Map : const {};
      return 'حذف مسودة ${_stKind(doc['kind'], null)} ${e.projectLabel} قبل تقديمها';
    case 'stores.doc_reverse':
      return 'أنشأ المستند العكسي ${e.projectLabel} للمستند ${text(d['reverses_no'])} — ${text(d['note'])}';
    case 'stores.receipt_confirm':
      return 'أكّد استلام ما صُرف له بالمستند ${e.projectLabel}';
    case 'finance.guarantee_initial':
      return d['na'] == true
          ? 'سجّل أن الضمان الابتدائي لا ينطبق على العقد'
          : 'سجّل أن الضمان الابتدائي ينطبق على العقد (${_m(d['amount'])})';
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
    case 'risk.review':
      return 'سجّل مراجعة للخطر ${text(d['code'])} بتاريخ ${text(d['reviewed_on']).replaceAll('-', '/')} (الدرجة الحالية ${text(d['score'])}'
          '${d['progress'] is num ? ' · التنفيذ ${((d['progress'] as num) * 100).round()}%' : ''})';
    case 'risk.review_update':
      return 'صحّح مراجعة الخطر ${text(d['code'])} بتاريخ ${text(d['reviewed_on']).replaceAll('-', '/')}${_changed(d['changes'])}';
    case 'risk.review_delete':
      return 'حذف مراجعة الخطر ${text(d['code'])} بتاريخ ${text(d['reviewed_on']).replaceAll('-', '/')}';
    case 'pm.schedule':
      return 'حدّث البرنامج الزمني للعقد${_changed(d['changes'])}';
    case 'pm.progress_add':
      return 'سجّل قياس تقدم بتاريخ ${text(d['measured_on']).replaceAll('-', '/')}: المخطط ${_p(d['planned'])} والفعلي ${_p(d['actual'])}';
    case 'pm.progress_update':
      return 'صحّح قياس التقدم بتاريخ ${text(d['measured_on']).replaceAll('-', '/')}${_changed(d['changes'])}';
    case 'pm.progress_delete':
      return 'حذف قياس التقدم بتاريخ ${text(d['measured_on']).replaceAll('-', '/')}';
    case 'pm.item_add':
      return 'أضاف البند «${text(d['title'])}» للجدول الزمني: ${text(d['planned_start']).replaceAll('-', '/')} إلى ${text(d['planned_end']).replaceAll('-', '/')}';
    case 'pm.item_update':
      return 'حدّث بند الجدول الزمني «${text(d['title'])}»${_changed(d['changes'])}';
    case 'pm.item_delete':
      return 'حذف بند الجدول الزمني «${text(d['title'])}» (الإنجاز ${text(d['progress'])}%)';
    case 'pm.items_from_works':
      return 'أنشأ ${text(d['items'])} من بنود الجدول الزمني من أعمال العقد';
    case 'pm.items_reorder':
      return 'رتّب بنود الجدول الزمني (${text(d['items'])})';
    case 'boq.create':
      if (d['source'] == 'import') {
        return 'استورد المقايسة «${text(d['title'])}» من الملف «${text(d['file'])}» بعد مراجعتها: ${text(d['lines'])} بنداً، الإجمالي ${_m(d['total'])}';
      }
      return 'أعدّ المقايسة «${text(d['title'])}» من لائحة الأسعار: ${text(d['lines'])} بنداً، الإجمالي ${_m(d['total'])}';
    case 'boq.update':
      return 'عدّل المقايسة «${text(d['title'])}»: ${text(d['lines'])} بنداً، الإجمالي ${_m(d['total'])}';
    case 'boq.delete':
      final items = d['plan_items'] is num ? (d['plan_items'] as num).toInt() : 0;
      final tracked = d['tracked_items'] is num ? (d['tracked_items'] as num).toInt() : 0;
      return 'حذف المقايسة «${text(d['title'])}» (${text(d['lines'])} بنداً)'
          '${items > 0 ? '، وحذف معها $items من بنود البرنامج الزمني ومتابعة الإشراف${tracked > 0 ? ' (منها $tracked عليها إنجاز مسجّل)' : ''}' : ''}'
          '${d['plan_removed'] == true ? '، وحذف البرنامج المسودة الذي فرغ' : ''}';
    case 'pm.boq_orphans':
      return 'حذف ${text(d['items'])} من بنود البرنامج الزمني بقيت من مقايسات محذوفة${(d['plans'] is num && d['plans'] != 0) ? '، والبرنامج المسودة الذي فرغ' : ''}';
    case 'boq.approve':
      return 'اعتمد المقايسة «${text(d['title'])}»: ${text(d['lines'])} بنداً، الإجمالي ${_m(d['total'])}، فصارت بنودها بنود العقد';
    case 'boq.reopen':
      return 'أعاد فتح المقايسة «${text(d['title'])}» للتعديل';
    case 'pm.item_progress':
      return 'حدّث تنفيذ البند «${text(d['title'])}»${_changed(d['changes'])}';
    case 'pm.plan_save':
      return 'حدّد بداية البرنامج الزمني ${text(d['start_date']).replaceAll('-', '/')}';
    case 'pm.phase_save':
      return '${d['new'] == true ? 'أضاف' : 'عدّل'} مرحلة التنفيذ «${text(d['name'])}»${(d['lag_days'] is num && d['lag_days'] != 0) ? ' (الفاصل ${text(d['lag_days'])} يوماً)' : ''}';
    case 'pm.phase_delete':
      return 'حذف مرحلة التنفيذ «${text(d['name'])}»';
    case 'pm.link_add':
      return 'ربط «${text(d['succ'])}» بـ«${text(d['pred'])}»: ${_linkText(d['kind'], d['lag'])}';
    case 'pm.link_update':
      return 'عدّل علاقة «${text(d['succ'])}» بـ«${text(d['pred'])}» من ${_linkText(d['from_kind'], d['from_lag'])} إلى ${_linkText(d['kind'], d['lag'])}';
    case 'pm.link_delete':
      return 'حذف علاقة «${text(d['succ'])}» بـ«${text(d['pred'])}» (${_linkText(d['kind'], d['lag'])})';
    case 'pm.rate_save':
      final kw = text(d['keyword']).isEmpty ? 'عام للوحدة' : '«${text(d['keyword'])}»';
      final prev = d['previous'] == null ? '' : ' (كان ${_n(d['previous'])})';
      return 'معدل الإنتاجية ${text(d['unit'])} $kw: ${_n(d['rate'])} في اليوم$prev، يسري من ${text(d['valid_from']).replaceAll('-', '/')}'
          '${d['active'] == false ? '، غير مفعّل' : ''}${text(d['note']).isEmpty ? '' : '. السبب: ${text(d['note'])}'}';
    case 'pm.rate_delete':
      return 'حذف قيد معدل الإنتاجية ${text(d['unit'])}${text(d['keyword']).isEmpty ? '' : ' «${text(d['keyword'])}»'}: ${_n(d['rate'])} في اليوم'
          ' من ${text(d['valid_from']).replaceAll('-', '/')}';
    case 'pm.plan_generate':
      return 'ولّد البرنامج الزمني من المقايسة المعتمدة: ${text(d['phases'])} مراحل و${text(d['items'])} بنداً في ${text(d['total_days'])} يوماً';
    case 'pm.plan_approve':
      return 'اعتمد البرنامج الزمني (الإصدار ${text(d['version'])}): ${text(d['items'])} بنداً من ${text(d['start_date']).replaceAll('-', '/')} إلى ${text(d['end_date']).replaceAll('-', '/')}، وأحاله إلى الإشراف';
    case 'pm.plan_reopen':
      return 'أعاد فتح البرنامج الزمني (الإصدار ${text(d['version'])}) للتعديل';
    case 'risk.auto':
      return 'ترجم تنفيذ البرنامج الزمني إلى سجل المخاطر بتاريخ ${text(d['ref_date']).replaceAll('-', '/')}: فُتح ${text(d['opened'])} وأُغلق ${text(d['closed'])}';
    case 'swot.auto':
      return 'ترجم تنفيذ البرنامج الزمني إلى تحليل SWOT بتاريخ ${text(d['ref_date']).replaceAll('-', '/')}: أُضيف ${text(d['added'])} وأُزيل ${text(d['removed'])}';
    case 'export.store':
      return 'حفظ النسخة الأصلية من «${text(d['title'])}»${text(d['ref_no']).isEmpty ? '' : ' (${text(d['ref_no'])})'} لرمز التحقق، ${_access(d['access'])}';
    case 'export.open':
      return 'فتح النسخة الأصلية من «${text(d['title'])}»${text(d['ref_no']).isEmpty ? '' : ' (${text(d['ref_no'])})'} برمز التحقق';
    case 'export.denied':
      return 'رُفض فتح النسخة الأصلية من «${text(d['title'])}» لأنها ${_access(d['access'])}';
    case 'export.unknown':
      return 'محاولة فتح مستند برمز تحقق غير معروف';
    case 'pm.issue_create':
      return 'سجّل المشكلة ${text(d['code'])}: ${text(d['description'])}';
    case 'pm.delay_create':
      return 'سجّل حدث التأخير ${text(d['code'])}: ${text(d['description'])}';
    case 'pm.change_create':
      return 'سجّل طلب التغيير ${text(d['code'])}: ${text(d['description'])}';
    case 'pm.lesson_create':
      return 'وثّق الدرس ${text(d['code'])}: ${text(d['lesson'])}';
    case 'pm.issue_update':
    case 'pm.delay_update':
    case 'pm.change_update':
    case 'pm.lesson_update':
      final what = switch (e.action) {
        'pm.issue_update' => 'المشكلة',
        'pm.delay_update' => 'حدث التأخير',
        'pm.change_update' => 'طلب التغيير',
        _ => 'الدرس',
      };
      return 'عدّل $what ${text(d['code'])}${_changed(d['changes'])}';
    case 'pm.evaluation_add':
      return 'سجّل تقييماً ميدانياً لـ ${text(d['company'])} بتاريخ ${text(d['evaluated_on']).replaceAll('-', '/')}';
    case 'pm.evaluation_update':
      return 'عدّل التقييم الميداني لـ ${text(d['company'])}${_changed(d['changes'])}';
    case 'pm.issue_delete':
    case 'pm.delay_delete':
    case 'pm.change_delete':
    case 'pm.lesson_delete':
    case 'pm.evaluation_delete':
      final what = switch (e.action) {
        'pm.issue_delete' => 'المشكلة',
        'pm.delay_delete' => 'حدث التأخير',
        'pm.change_delete' => 'طلب التغيير',
        'pm.lesson_delete' => 'الدرس',
        _ => 'التقييم الميداني',
      };
      return 'حذف $what ${text(d['code'] ?? d['company'])}${text(d['description']).isNotEmpty ? ': ${text(d['description'])}' : ''}';
    case 'doc.create':
      final cat = d['kind'] == 'attachment' && text(d['category']).isNotEmpty ? ' — ${docCategoryLabel('attachment', text(d['category']))}' : '';
      return 'أضاف ${_docKind(d['kind'])}$cat: ${text(d['title'])}${text(d['ref_no']).isNotEmpty ? ' (رقم ${text(d['ref_no'])})' : ''}';
    case 'doc.update':
      return 'عدّل ${_docKind(d['kind'])} «${text(d['title'])}»${_changed(d['changes'])}';
    case 'doc.delete':
      return 'حذف ${_docKind(d['kind'])} «${text(d['title'])}» بكل إصداراته (${text(d['files'])} ملف)';
    case 'doc.revision_add':
      return 'أضاف الإصدار ${text(d['rev_no'])} إلى ${_docKind(d['kind'])} «${text(d['title'])}»${text(d['note']).isNotEmpty ? ': ${text(d['note'])}' : ''}';
    case 'doc.revision_update':
      return 'عدّل بيانات الإصدار ${text(d['rev_no'])} من ${_docKind(d['kind'])} «${text(d['title'])}»';
    case 'doc.revision_delete':
      return 'حذف الإصدار ${text(d['rev_no'])} من ${_docKind(d['kind'])} «${text(d['title'])}» (${text(d['files'])} ملف)';
    case 'doc.file_add':
      return 'أرفق «${text(d['file'])}» بالإصدار ${text(d['rev_no'])} من ${_docKind(d['kind'])} «${text(d['title'])}»';
    case 'doc.file_delete':
    case 'report.file_delete':
      return 'أزال الملف «${text(d['file'])}»';
    case 'report.create':
      return 'رفع التقرير اليومي ليوم ${text(d['date']).replaceAll('-', '/')}';
    case 'report.update':
      return 'عدّل التقرير اليومي ليوم ${text(d['date']).replaceAll('-', '/')}${_changed(d['changes'])}';
    case 'report.delete':
      return 'حذف التقرير اليومي ليوم ${text(d['date']).replaceAll('-', '/')}';
    case 'report.review':
      final note = text(d['note']);
      return d['reviewed'] == true
          ? 'اطّلع على التقرير اليومي ليوم ${text(d['date']).replaceAll('-', '/')}${note.isNotEmpty ? ' — $note' : ''}'
          : 'ألغى الاطلاع على التقرير اليومي ليوم ${text(d['date']).replaceAll('-', '/')}';
    case 'report.file_add':
      return 'أرفق «${text(d['file'])}» بالتقرير اليومي ليوم ${text(d['date']).replaceAll('-', '/')}';
    case 'unit.create':
      return 'أضاف ${_unitKind(d['kind'])} في ${_unitName(d['unit'])}: ${text(d['title'])}';
    case 'unit.update':
      return 'عدّل ${_unitKind(d['kind'])} «${text(d['title'])}»${_changed(d['changes'])}';
    case 'unit.delete':
      final n = (d['children'] as num?)?.toInt() ?? 0;
      final files = (d['files'] as num?)?.toInt() ?? 0;
      return 'حذف ${_unitKind(d['kind'])} «${text(d['title'])}» من ${_unitName(d['unit'])}'
          '${n > 0 ? ' مع $n سجل تابع' : ''}${files > 0 ? ' ($files ملف)' : ''}';
    case 'unit.file_add':
      return 'أرفق «${text(d['file'])}» بـ${_unitKind(d['kind'])} «${text(d['title'])}»';
    case 'unit.file_delete':
      return 'أزال الملف «${text(d['file'])}» من سجل وحدة';
    case 'user.unit':
      final to = text(d['to_name']);
      final from = text(d['from_name']);
      final head = d['head'] is Map && (d['head'] as Map)['to'] == true;
      return to.isEmpty
          ? 'أزال ${e.projectLabel} من ${from.isEmpty ? 'وحدته' : from}'
          : 'أسند ${e.projectLabel} إلى $to${head ? ' رئيساً لها' : ''}';
    case 'print.template_save':
      final kind = d['shared'] == true ? (d['default'] == true ? 'القالب العام الافتراضي' : 'القالب العام') : 'القالب الخاص';
      return '${d['created'] == true ? 'أنشأ' : 'عدّل'} $kind «${text(d['name'])}»';
    case 'print.template_delete':
      return 'حذف ${d['shared'] == true ? 'القالب العام' : 'القالب الخاص'} «${text(d['name'])}»';
    case 'export.file':
    case 'export.print':
      final rows = (d['rows'] as num?)?.toInt() ?? 0;
      return '${e.action == 'export.print' ? 'طبع' : 'استخرج'} «${text(d['title'])}» بصيغة ${text(d['format']).toUpperCase()} ($rows سجل)';
    case 'export.media':
      final n = (d['rows'] as num?)?.toInt() ?? 0;
      return 'نزّل حزمة ZIP من $n ملفاً (${fmtBytes(d['bytes'] as num?)})';
    case 'user.grants':
      String names(Object? v) => (v is List ? v : const []).map((x) => grantLabel('$x', app.allFormDefs, warehouses: [for (final w in app.stores.warehouses) (w.id, w.name)])).join('، ');
      final add = names(d['added']);
      final rem = names(d['removed']);
      return 'الصلاحيات الدقيقة لـ ${text(d['name'])}: ${[if (add.isNotEmpty) 'منح $add', if (rem.isNotEmpty) 'سحب $rem'].join(' · ')}';
    case 'ref.scheme_save':
      return d['created'] == true
          ? 'أنشأ صيغة الرقم الإشاري «${text(d['name'])}»: ${text(d['pattern'])}'
          : 'عدّل صيغة «${text(d['name'])}»: ${text(d['from'])} ← ${text(d['pattern'])}';
    case 'ref.scheme_delete':
      return 'حذف صيغة الرقم الإشاري «${text(d['name'])}»';
    case 'ref.counter_set':
      return 'ضبط تسلسل «${text(d['key'])}» للفترة ${text(d['period'])}: من ${text(d['from'])} إلى ${text(d['to'])}';
    case 'chat.room_create':
      return 'أنشأ ${d['kind'] == 'channel' ? 'القناة' : 'المجموعة'} «${text(d['title'])}»';
    case 'chat.room_update':
      return 'عدّل «${text(d['title'])}»';
    case 'chat.members':
      if (d['role'] != null) return 'غيّر دور عضو في «${text(d['title'])}» إلى ${d['role'] == 'admin' ? 'مشرف' : 'عضو'}';
      final add = (d['added'] as List?)?.length ?? 0;
      final rem = (d['removed'] as List?)?.length ?? 0;
      return 'أعضاء «${text(d['title'])}»: ${[if (add > 0) 'أضاف $add', if (rem > 0) 'أزال $rem'].join(' و')}';
    case 'chat.lock':
      return 'قفل المحادثة «${text(d['title'])}»: ${text(d['reason'])}';
    case 'chat.unlock':
      return 'فتح المحادثة «${text(d['title'])}»';
    case 'chat.room_delete':
      return 'حذف المحادثة «${text(d['title'])}» (${text(d['messages'])} رسالة، ${text(d['files'])} مرفقاً)';
    case 'chat.message_delete':
      return 'حذف رسالة ${text(d['sender'])} في «${text(d['title'])}» بصفته مشرفاً';
    case 'security.incident_save':
      return '${d['created'] == true ? 'سجّل' : 'عدّل'} الحادثة الأمنية «${text(d['title'])}» (${text(d['status'])})';
    case 'security.incident_delete':
      return 'حذف الحادثة الأمنية «${text(d['title'])}»';
    case 'security.emergency_freeze':
      return '${d['on'] == true ? 'جمّد المنظومة' : 'رفع التجميد'}: ${text(d['reason'])}';
    case 'security.grants_suspend':
      return 'علّق ${(d['scopes'] as List?)?.length ?? 0} صلاحية دقيقة لـ ${e.projectLabel}: ${text(d['reason'])}';
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
  'residual_probability': 'الاحتمالية المستهدفة',
  'residual_impact': 'التأثير المستهدف',
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
  'time_impact_days': 'الأثر الزمني',
  'cost_impact': 'الأثر المالي',
  'contingency': 'الإجراء الاحتياطي',
  'executor': 'منفذ الإجراء',
  'reviewed_on': 'تاريخ المراجعة',
  'actions_done': 'الإجراءات المنفذة',
  'reviewer': 'المراجِع',
  'project_type': 'نوع المشروع',
  'location': 'الموقع',
  'consultant': 'الاستشاري',
  'op_status': 'الوضع التشغيلي',
  'end_date': 'تاريخ النهاية',
  'measured_on': 'تاريخ القياس',
  'planned': 'المخطط',
  'actual': 'الفعلي',
  'works': 'الأعمال المنفذة',
  'obstacles': 'المعوقات',
  'prepared_by': 'أعدّه',
  'detected_on': 'تاريخ الرصد',
  'risk_id': 'الخطر المرتبط',
  'party': 'الجهة المسؤولة',
  'sub_cause': 'السبب الفرعي',
  'delay_class': 'التصنيف التعاقدي',
  'critical': 'المسار الحرج',
  'eot_requested': 'التمديد المطلوب',
  'eot_approved': 'التمديد المعتمد',
  'refs': 'المرجع',
  'submitted_on': 'تاريخ التقديم',
  'change_type': 'نوع التغيير',
  'reason': 'السبب',
  'cost_estimate': 'الأثر المالي المقدر',
  'cost_approved': 'الأثر المالي المعتمد',
  'time_requested': 'الأثر الزمني المطلوب',
  'time_approved': 'الأثر الزمني المعتمد',
  'decided_on': 'تاريخ البت',
  'approval_ref': 'مرجع الاعتماد',
  'documented_on': 'تاريخ التوثيق',
  'domain': 'المجال',
  'lesson_type': 'نوع الدرس',
  'situation': 'الموقف',
  'root_cause': 'السبب الجذري',
  'lesson': 'الدرس',
  'apply_mechanism': 'آلية التعميم',
  'apply_party': 'جهة التطبيق',
  'applied_on': 'تاريخ التطبيق',
  'company': 'الشركة',
  'evaluated_on': 'تاريخ التقييم',
  'quality': 'جودة الأعمال',
  'safety': 'السلامة',
  'schedule': 'الالتزام بالبرنامج',
  'resources': 'الجهاز الفني والمعدات',
  'cooperation': 'الاستجابة والتعاون',
  'documentation': 'التوثيق',
  'evaluator': 'المُقيِّم',
  'title': 'العنوان',
  'ref_no': 'الرقم',
  'doc_date': 'التاريخ',
  'direction': 'الاتجاه',
  'amount': 'القيمة',
  'reply_to': 'المراسلة المرتبطة',
  'due_date': 'موعد الرد',
  'origin_project': 'العقد الأصلي',
  'work_id': 'العمل',
  'report_date': 'تاريخ التقرير',
  'weather': 'الطقس',
  'temp_c': 'درجة الحرارة',
  'workers': 'العمالة',
  'equipment': 'المعدات',
  'works_done': 'الأعمال المنفذة',
  'materials': 'المواد',
  'issues': 'المعوقات',
  'next_plan': 'خطة اليوم التالي',
  'progress_pct': 'نسبة الإنجاز التقديرية',
  'rec_date': 'التاريخ',
  'level': 'التصنيف',
  'owner_text': 'المسؤول',
  'data': 'البيانات التفصيلية',
  'parent_id': 'السجل المرتبط',
  'closed_at': 'تاريخ الإغلاق',
  'planned_start': 'البداية المخططة',
  'planned_end': 'النهاية المخططة',
  'weight': 'الوزن',
  'actual_start': 'البداية الفعلية',
  'actual_end': 'النهاية الفعلية',
  'sort': 'الترتيب',
  'show_prices': 'إظهار الأسعار',
  'list_id': 'لائحة الأسعار',
  'line_count': 'عدد البنود',
  'total': 'الإجمالي',
};

String _changed(Object? changes) {
  if (changes is! Map || changes.isEmpty) return '';
  final names = [for (final k in changes.keys) _registerFields[k.toString()] ?? k.toString()];
  return ': ${names.toSet().join('، ')}';
}

String _m(Object? v) => v is num ? '${fmtMoney(v.toDouble())} $currencyLabel' : '—';

String _p(Object? v) => v is num ? '${(v * 100).toStringAsFixed(1)}%' : '—';

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
  'pm.config': 'قوائم متابعة المشاريع وإعداداتها',
  'swot.meta': 'بيانات وثيقة تحليل SWOT',
};

String _docKind(Object? k) => switch (k?.toString()) {
      'boq' => 'المقايسة',
      'letter' => 'المراسلة',
      'design' => 'التصميم',
      'attachment' => 'مرفق ملف العقد',
      _ => 'المستند',
    };

String _unitKind(Object? k) => unitKinds[k?.toString()]?.single ?? 'سجلاً';
String _unitName(Object? u) => unitNames[u?.toString()] ?? 'وحدة';

/// نطاق الاطلاع على نسخة PDF المحفوظة (الترحيل 32).
String _access(Object? v) => switch (v) {
      'people' => 'مقيّدة بالمدير ومسؤول الأمن ومن استخرجها',
      'private' => 'سرية للمدير ومن استخرجها',
      _ => 'مفتوحة لأعضاء المنظومة',
    };

/// اسم القسم في وصف سجل التدقيق (الاسم الافتراضي؛ السجل لا يتغير بتخصيص الواجهة).
String _sectionName(Object? key) => sectionDefaultNames[key] ?? '';

/// صافي أمر التغيير في السجل: «زيادة 4,200 ونقص 4,750» أو «نقص 550».
String _varNet(Map<String, dynamic> d) {
  final a = d['added'] is num ? (d['added'] as num).toDouble() : null;
  final r = d['deducted'] is num ? (d['deducted'] as num).toDouble() : null;
  if (a != null && r != null && a > 0 && r > 0) return 'زيادة ${fmtMoney(a)} ونقص ${fmtMoney(r)}';
  return '${d['kind'] == 'deduct' ? 'نقص' : 'زيادة'} ${_m(d['amount'])}';
}

/// تعديل ضمانات العقد وتأميناته (الترحيل 37): كل ما تغيّر بقيمتيه.
String _guarantees(Map<String, dynamic> d) {
  String pct(Object? v) => v is num ? rateText(v.toDouble()) : '—';
  String ft(Object? v, String Function(Object?) f) => v is Map ? '${f(v['from'])} ← ${f(v['to'])}' : '';
  String na(Object? v) => v == true ? 'لا ينطبق' : 'ينطبق';
  String on(Object? v) => v == true ? 'مفعّل' : 'معطّل';
  final parts = [
    if (d['initial_rate'] is Map) 'نسبة الابتدائي ${ft(d['initial_rate'], pct)}',
    if (d['initial_na'] is Map) 'الابتدائي ${ft(d['initial_na'], na)}',
    if (d['final_rate'] is Map) 'نسبة النهائي ${ft(d['final_rate'], pct)}',
    if (d['final_na'] is Map) 'النهائي ${ft(d['final_na'], na)}',
    if (d['retention_deduct'] is Map) 'خصم التأمينات ${ft(d['retention_deduct'], on)}',
    if (d['retention_rate'] is Map) 'نسبة التأمين ${ft(d['retention_rate'], pct)}',
  ];
  final amounts = [
    if (d['initial'] is Map) 'الابتدائي ${ft(d['initial'], (v) => v == null ? '—' : _m(v))}',
    if (d['final'] is Map) 'النهائي ${ft(d['final'], (v) => v == null ? '—' : _m(v))}',
  ];
  final head = d['source'] == 'migration_37' ? 'صحّح الضمانين بالقرار المعتمد' : 'عدّل ضمانات العقد وتأميناته';
  return '$head: ${parts.join('، ')}${amounts.isEmpty ? '' : ' (المبلغان: ${amounts.join('، ')})'}';
}

/// تشكيل لجنة الاستلام أو تعديلها أو حذفها (الترحيل 37).
String _committee(Map<String, dynamic> d, {required bool deleted}) {
  final kind = committeeKindLabels['${d['kind'] ?? ''}'] ?? 'لجنة الاستلام';
  String names(Object? v) {
    if (v is! Map) return '';
    final chair = v['chair'] is Map ? '${(v['chair'] as Map)['name'] ?? ''}' : '';
    final members = v['members'] is List ? [for (final m in v['members'] as List) if (m is Map) '${m['name'] ?? ''}'] : const <String>[];
    return [if (chair.isNotEmpty) 'الرئيس $chair', if (members.isNotEmpty) 'الأعضاء ${members.join('، ')}'].join(' · ');
  }

  if (deleted) return 'حذف تشكيل $kind (${names(d['from'])})';
  if (d['from'] == null) return 'شكّل $kind: ${names(d['to'])}';
  return 'عدّل $kind: ${names(d['to'])}';
}

// ---------------------------------------------------------------- قسم المخازن (الترحيل 38)

const Map<String, String> _stEntityNames = {
  'department': 'الإدارة',
  'location': 'الموقع',
  'warehouse': 'المخزن',
  'category': 'التصنيف',
  'unit': 'الوحدة',
  'employee': 'الموظف',
  'item': 'الصنف',
};

String _stKind(Object? kind, Object? reverses) {
  const k = {
    'opening': 'مستند أرصدة أول المدة',
    'receipt': 'مستند الوارد',
    'issue': 'مستند الصرف',
    'return': 'مستند المرتجع',
    'transfer': 'مستند التحويل',
    'adjust': 'مستند التسوية',
  };
  final base = k['${kind ?? ''}'] ?? 'المستند';
  return reverses == null ? base : 'عكس $base';
}

String _storesEntity(String action, Map<String, dynamic> d) {
  final entity = action == 'stores.employee' ? 'employee' : (action == 'stores.item' ? 'item' : '${d['entity'] ?? ''}');
  final what = _stEntityNames[entity] ?? 'عنصر التهيئة';
  final name = '${d['name'] ?? ''}';
  final code = '${d['code'] ?? ''}';
  final label = code.isEmpty ? '«$name»' : '«$name» ($code)';
  return switch ('${d['op'] ?? ''}') {
    'create' => 'أضاف $what $label',
    'delete' => 'حذف $what $label',
    _ => 'عدّل $what $label',
  };
}

String _storesSettings(Map<String, dynamic> d) {
  final to = d['to'] is Map ? d['to'] as Map : const {};
  final parts = <String>[
    if (to['separation'] is bool) 'فصل المهام: ${to['separation'] == true ? 'مفعّل' : 'معطّل'}',
    if (to['expiry_days'] is num) 'التنبيه قبل انتهاء الصلاحية: ${(to['expiry_days'] as num).toInt()} يوماً',
  ];
  return 'إعدادات المخازن — ${parts.join(' · ')}';
}

String _storesDocAction(String action, Map<String, dynamic> d, String no) {
  final kind = _stKind(d['kind'], null);
  final note = '${d['note'] ?? ''}'.trim();
  final override = d['override'] is List && (d['override'] as List).isNotEmpty;
  return switch (action) {
    'stores.doc_submit' => 'قدّم $kind $no للاعتماد',
    'stores.doc_return' => 'أعاد $kind $no للتعديل${note.isEmpty ? '' : ' — $note'}',
    'stores.doc_reject' => 'رفض $kind $no${note.isEmpty ? '' : ' — السبب: $note'}',
    'stores.doc_approve' => 'اعتمد $kind $no${override ? ' باستثناء الاحتياطي الحرج — $note' : ''}',
    'stores.doc_post' => 'رحّل $kind $no إلى الأرصدة',
    _ => 'ألغى $kind $no${note.isEmpty ? '' : ' — $note'}',
  };
}

/// «نهاية ← بداية +2» من نوع العلاقة وانتظارها (الترحيل 36).
String _linkText(Object? kind, Object? lag) {
  const k = {'FS': 'نهاية ← بداية', 'SS': 'بداية ← بداية', 'FF': 'نهاية ← نهاية', 'SF': 'بداية ← نهاية'};
  final l = lag is num ? lag.toInt() : int.tryParse('${lag ?? ''}') ?? 0;
  return '${k['${kind ?? ''}'] ?? '—'}${l == 0 ? '' : (l > 0 ? ' +$l' : ' $l')}';
}

/// رقم بلا أصفار زائدة: 60.000 ← 60.
String _n(Object? v) {
  final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  if (d == null) return '—';
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}
