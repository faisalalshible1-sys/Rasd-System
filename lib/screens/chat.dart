import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../chat.dart';
import '../models.dart';
import '../services/doc_files.dart' show openDocExternally;
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../units.dart';
import 'project_detail.dart';

// =====================================================================
// المراسلات الداخلية: قائمة المحادثات، والمحادثة، والإنشاء والإدارة.
// =====================================================================

String _hm(DateTime? d) => d == null ? '' : '${two(d.hour)}:${two(d.minute)}';

String _when(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return _hm(d);
  if (today.difference(day).inDays == 1) return 'أمس';
  if (today.difference(day).inDays < 7) return const ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'][d.weekday - 1];
  return fmtDate(d);
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'اليوم';
  if (today.difference(day).inDays == 1) return 'أمس';
  return fmtDate(d);
}

IconData _roomIcon(ChatRoom r) => switch (r.kind) {
      'channel' => r.id == generalChannelId ? Icons.apartment_rounded : Icons.campaign_rounded,
      'group' => Icons.groups_rounded,
      _ => Icons.person_rounded,
    };

String _preview(AppState app, ChatRoom r) {
  final l = r.last;
  if (l == null) return r.isDm ? 'ابدأ المحادثة' : (r.description.isNotEmpty ? r.description : 'لا رسائل بعد');
  if (l.deleted) return 'حُذفت رسالة';
  final who = l.sender == app.me?.id ? 'أنت' : l.senderName.split(' ').first;
  final body = switch (l.kind) {
    'file' => '${(l.mime ?? '').startsWith('image/') ? '🖼' : (l.mime ?? '').startsWith('video/') ? '🎬' : '📎'} ${l.text}',
    'link' => '🔗 ${l.text}',
    _ => l.text,
  };
  if (l.kind == 'system' || r.isDm && l.sender != app.me?.id) return body;
  return '$who: $body';
}

String _audienceText(AppState app, Map<String, dynamic> a) {
  if (a['all'] == true) return 'كل المكتب';
  final parts = <String>[];
  for (final r in (a['roles'] as List? ?? const [])) {
    parts.add(parseRole(r)?.label ?? r.toString());
  }
  for (final d in (a['departments'] as List? ?? const [])) {
    parts.add(app.departments.where((x) => x.key == d).map((x) => x.name).firstOrNull ?? d.toString());
  }
  for (final u in (a['units'] as List? ?? const [])) {
    parts.add(unitNames[u] ?? u.toString());
  }
  final users = (a['users'] as List? ?? const []).length;
  if (users > 0) parts.add('$users شخصاً');
  return parts.isEmpty ? '—' : parts.join('، ');
}

/// صفحة المراسلات: [channels] لقنوات الأقسام، وإلا المحادثات الخاصة والمجموعات.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.channels = false, this.initialRoom});

  final bool channels;

  /// محادثة تُفتح مباشرة (على الشاشات العريضة).
  final String? initialRoom;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _search = TextEditingController();
  late String? _selected = widget.initialRoom;
  String _filter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChatRoom> _rooms(AppState app) {
    final q = _search.text.trim();
    return [
      for (final r in app.chat.rooms)
        if (widget.channels == r.isChannel)
          if (_filter != 'unread' || r.unread > 0)
            if (_filter != 'dm' || r.isDm)
              if (_filter != 'groups' || r.isGroup)
                if (_filter != 'archived' ? !r.archived : r.archived)
                  if (q.isEmpty || r.displayTitle.contains(q) || (r.last?.text ?? '').contains(q) || r.description.contains(q)) r,
    ];
  }

  Future<void> _open(BuildContext context, String id, bool wide) async {
    if (wide) {
      setState(() => _selected = id);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConversationScreen(roomId: id)));
  }

  Future<void> _newDm(BuildContext context, bool wide) async {
    final app = AppScope.read(context);
    final picked = await pickPeople(context, title: 'محادثة خاصة جديدة', single: true);
    if (picked == null || picked.isEmpty || !context.mounted) return;
    try {
      final id = await app.chat.openDm(picked.first);
      if (context.mounted) await _open(context, id, wide);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _newGroup(BuildContext context, bool wide) async {
    final id = await showDialog<String>(context: context, builder: (_) => const _GroupDialog());
    if (id != null && context.mounted) await _open(context, id, wide);
  }

  Future<void> _newChannel(BuildContext context, bool wide) async {
    final id = await showDialog<String>(context: context, builder: (_) => const ChannelDialog());
    if (id != null && context.mounted) await _open(context, id, wide);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v12Ready) {
      return const PageBody(children: [
        EmptyState(
          icon: Icons.forum_outlined,
          title: 'المراسلات الداخلية غير مفعّلة بعد',
          message: 'تعمل بعد تحديث قاعدة البيانات بالملف 20261119000024_chat.sql.',
        ),
      ]);
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final rooms = _rooms(app);
    if (wide && _selected != null && app.chat.room(_selected!) == null && app.chat.loaded) _selected = null;
    final enabled = app.settings.raw['chat.config'] is! Map || (app.settings.raw['chat.config'] as Map)['enabled'] != false;
    final groupsAllowed =
        app.isDirector || app.settings.raw['chat.config'] is! Map || (app.settings.raw['chat.config'] as Map)['groups'] != false;

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Row(children: [
          Expanded(
            child: Text(widget.channels ? 'قنوات الأقسام' : 'المحادثات',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (!widget.channels && enabled) ...[
            IconButton.filledTonal(
              tooltip: 'محادثة خاصة جديدة',
              onPressed: () => _newDm(context, wide),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            const SizedBox(width: 6),
            if (groupsAllowed)
              IconButton.filledTonal(
                tooltip: 'مجموعة جديدة',
                onPressed: () => _newGroup(context, wide),
                icon: const Icon(Icons.group_add_rounded),
              ),
          ],
          if (widget.channels && app.isDirector)
            FilledButton.tonalIcon(
              onPressed: () => _newChannel(context, wide),
              icon: const Icon(Icons.add_rounded),
              label: const Text('قناة جديدة'),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco('بحث في المحادثات', prefixIcon: const Icon(Icons.search_rounded)),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(children: [
          for (final f in [
            ('all', 'الكل'),
            ('unread', 'غير المقروءة'),
            if (!widget.channels) ('dm', 'الخاصة'),
            if (!widget.channels) ('groups', 'المجموعات'),
            ('archived', 'المؤرشفة'),
          ])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: _filter == f.$1,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
            ),
        ]),
      ),
      if (!enabled)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: InfoBanner(text: 'أوقف مدير المكتب المراسلات مؤقتاً؛ تُقرأ المحادثات ولا تُرسل رسائل جديدة.', level: 'warning'),
        ),
      Expanded(
        child: !app.chat.loaded
            ? const Center(child: CircularProgressIndicator())
            : rooms.isEmpty
                ? ListView(children: [
                    EmptyState(
                      icon: widget.channels ? Icons.campaign_outlined : Icons.forum_outlined,
                      title: _search.text.isNotEmpty || _filter != 'all' ? 'لا نتائج' : (widget.channels ? 'لا قنوات بعد' : 'لا محادثات بعد'),
                      message: widget.channels
                          ? 'قنوات الأقسام ينشئها مدير المكتب، ويدخلها تلقائياً كل من يطابق جمهورها.'
                          : 'ابدأ محادثة خاصة مع زميل، أو أنشئ مجموعة لأشخاص معينين.',
                    ),
                  ])
                : RefreshIndicator(
                    onRefresh: app.chat.refreshRooms,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
                      itemCount: rooms.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (_, i) => _RoomTile(
                        room: rooms[i],
                        selected: wide && rooms[i].id == _selected,
                        onTap: () => _open(context, rooms[i].id, wide),
                      ),
                    ),
                  ),
      ),
    ]);

    if (!wide) return list;
    return Row(children: [
      SizedBox(width: 370, child: list),
      VerticalDivider(width: 1, color: sem.rule),
      Expanded(
        child: _selected == null
            ? Center(
                child: EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'اختر محادثة',
                  message: widget.channels
                      ? 'اختر قناة من القائمة لقراءة إعلاناتها.'
                      : 'اختر محادثة من القائمة، أو ابدأ محادثة خاصة أو مجموعة جديدة.',
                ),
              )
            : ConversationView(key: ValueKey(_selected), roomId: _selected!, embedded: true),
      ),
    ]);
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.selected, required this.onTap});

  final ChatRoom room;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = room;
    final unread = r.unread > 0;
    return Material(
      color: selected ? cs.primaryContainer.withValues(alpha: 0.55) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            if (r.isDm)
              InitialsAvatar(name: r.displayTitle, size: 44)
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(13)),
                child: Icon(_roomIcon(r), color: cs.onSecondaryContainer),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(r.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 14.5)),
                  ),
                  if (r.pinned) Icon(Icons.push_pin_rounded, size: 14, color: sem.muted),
                  if (r.muted) Icon(Icons.notifications_off_outlined, size: 14, color: sem.muted),
                  if (r.locked) Icon(Icons.lock_rounded, size: 14, color: sem.danger),
                  const SizedBox(width: 6),
                  Text(_when(r.activity), style: TextStyle(fontSize: 11.5, color: unread ? cs.primary : sem.muted)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text(_preview(app, r),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: unread ? null : sem.muted, fontSize: 12.5, fontWeight: unread ? FontWeight.w600 : null)),
                  ),
                  if (unread)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: r.muted ? sem.muted : cs.primary, borderRadius: BorderRadius.circular(99)),
                      child: Text('${r.unread}', style: TextStyle(color: cs.onPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// المحادثة في صفحة مستقلة (الهاتف).
class ConversationScreen extends StatelessWidget {
  const ConversationScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: ConversationView(roomId: roomId)));
}

class ConversationView extends StatefulWidget {
  const ConversationView({super.key, required this.roomId, this.embedded = false});

  final String roomId;
  final bool embedded;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final List<ChatAttachment> _files = [];
  ChatMessage? _reply;
  ChatMessage? _editing;
  bool _sending = false;
  bool _loadingOlder = false;
  ChatController? _chat;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chat = AppScope.read(context).chat;
      _chat!.open(widget.roomId).catchError((Object e) {
        if (mounted) showToast(context, friendlyError(e), error: true);
      });
    });
  }

  @override
  void dispose() {
    _chat?.close(widget.roomId);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final c = _chat;
    if (c == null || _loadingOlder || !c.hasMore(widget.roomId)) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadingOlder = true;
      c.loadMessages(widget.roomId, older: true).whenComplete(() => _loadingOlder = false);
    }
  }

  int get _maxMb {
    final cfg = AppScope.read(context).settings.raw['chat.config'];
    final v = cfg is Map ? cfg['max_file_mb'] : null;
    return v is num ? v.toInt().clamp(1, 50) : 50;
  }

  Future<void> _attach({bool media = false}) async {
    try {
      final picked = await pickChatFiles(maxMb: _maxMb, media: media);
      if (picked.isEmpty || !mounted) return;
      setState(() => _files.addAll(picked.take(10 - _files.length)));
    } catch (e) {
      if (mounted) showToast(context, e is StateError ? e.message : friendlyError(e), error: true);
    }
  }

  Future<void> _shareContract() async {
    final app = AppScope.read(context);
    final picked = await showDialog<Project>(context: context, builder: (_) => const _ContractPicker());
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await app.chat.send(widget.roomId, '', ref: {
        'type': 'project',
        'id': picked.id,
        'label': picked.label,
        'sub': picked.company,
      });
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final app = AppScope.read(context);
    final text = _text.text.trim();
    if (_sending) return;
    if (_editing != null) {
      final m = _editing!;
      setState(() => _sending = true);
      try {
        await app.chat.edit(m, text);
        _text.clear();
        setState(() => _editing = null);
      } catch (e) {
        if (mounted) showToast(context, friendlyError(e), error: true);
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }
    if (text.isEmpty && _files.isEmpty) return;
    setState(() => _sending = true);
    try {
      if (_files.isEmpty) {
        await app.chat.send(widget.roomId, text, replyTo: _reply?.id);
      } else {
        for (var i = 0; i < _files.length; i++) {
          await app.chat.send(widget.roomId, i == 0 ? text : '', file: _files[i], replyTo: i == 0 ? _reply?.id : null);
        }
      }
      _text.clear();
      setState(() {
        _files.clear();
        _reply = null;
      });
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _focus.requestFocus();
  }

  bool _canEdit(AppState app, ChatMessage m) {
    if (m.sender != app.me?.id || m.deleted || m.isSystem || m.kind == 'link') return false;
    final cfg = app.settings.raw['chat.config'];
    final minutes = cfg is Map && cfg['edit_minutes'] is num ? (cfg['edit_minutes'] as num).toInt() : 60;
    return m.createdAt != null && DateTime.now().difference(m.createdAt!).inMinutes < minutes;
  }

  Future<void> _messageAction(ChatRoom room, ChatMessage m, String action) async {
    final app = AppScope.read(context);
    switch (action) {
      case 'reply':
        setState(() {
          _reply = m;
          _editing = null;
        });
        _focus.requestFocus();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) showToast(context, 'نُسخ النص');
      case 'edit':
        setState(() {
          _editing = m;
          _reply = null;
          _text.text = m.body;
        });
        _focus.requestFocus();
      case 'delete':
        final mine = m.sender == app.me?.id;
        final ok = await confirmDialog(context,
            title: 'حذف الرسالة',
            message: mine ? 'تُحذف الرسالة ومرفقها عند الجميع، ويبقى أثر «حُذفت هذه الرسالة».' : 'تحذفها بصفتك مشرف المحادثة، ويُسجَّل ذلك في سجل التدقيق.',
            confirmLabel: 'حذف',
            danger: true);
        if (!ok) return;
        try {
          await app.chat.delete(m);
        } catch (e) {
          if (mounted) showToast(context, friendlyError(e), error: true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final c = app.chat;
    final room = c.room(widget.roomId);
    if (room == null) {
      return Center(child: c.loaded ? const EmptyState(title: 'المحادثة غير متاحة', icon: Icons.lock_outline) : const CircularProgressIndicator());
    }
    final msgs = c.messagesOf(widget.roomId);
    final enabled = app.settings.raw['chat.config'] is! Map || (app.settings.raw['chat.config'] as Map)['enabled'] != false;
    final canPost = enabled && !room.locked && !room.archived && (!room.adminsOnly || room.isAdmin);
    final items = msgs.reversed.toList();

    return Column(children: [
      _Header(room: room, embedded: widget.embedded),
      if (room.locked)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: InfoBanner(
              text: 'المحادثة مقفلة بقرار أمني${room.lockReason.isNotEmpty ? ': ${room.lockReason}' : ''}. تُقرأ ولا تُرسل فيها رسائل.',
              level: 'critical',
              icon: Icons.lock_rounded),
        ),
      Expanded(
        child: !c.isLoaded(widget.roomId)
            ? const Center(child: CircularProgressIndicator())
            : msgs.isEmpty
                ? const Center(child: EmptyState(icon: Icons.waving_hand_outlined, title: 'لا رسائل بعد', message: 'اكتب أول رسالة في الأسفل.'))
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    itemCount: items.length + (c.hasMore(widget.roomId) ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      final m = items[i];
                      final older = i + 1 < items.length ? items[i + 1] : null;
                      final newDay = m.createdAt != null &&
                          (older?.createdAt == null ||
                              DateTime(older!.createdAt!.year, older.createdAt!.month, older.createdAt!.day) !=
                                  DateTime(m.createdAt!.year, m.createdAt!.month, m.createdAt!.day));
                      final sameSender = older != null && !newDay && older.sender == m.sender && !older.isSystem && !m.isSystem;
                      return Column(children: [
                        if (newDay) _DayChip(label: _dayLabel(m.createdAt!)),
                        _Bubble(
                          room: room,
                          message: m,
                          showSender: !sameSender && !room.isDm,
                          reply: m.replyTo == null ? null : c.message(widget.roomId, m.replyTo!),
                          canEdit: _canEdit(app, m),
                          canDelete: !m.deleted && !m.isSystem && (m.sender == app.me?.id || room.isAdmin || (room.isChannel && app.isDirector)),
                          onAction: (a) => _messageAction(room, m, a),
                        ),
                      ]);
                    },
                  ),
      ),
      if (canPost) _composer(context, room, sem) else _readOnlyBar(context, room, enabled, sem),
    ]);
  }

  Widget _readOnlyBar(BuildContext context, ChatRoom room, bool enabled, Sem sem) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: sem.rule))),
        child: Text(
          !enabled
              ? 'المراسلات موقوفة مؤقتاً من مدير المكتب.'
              : room.locked
                  ? 'المحادثة مقفلة.'
                  : room.archived
                      ? 'المحادثة مؤرشفة.'
                      : 'هذه قناة إعلانات: يرسل فيها مشرفوها فقط.',
          textAlign: TextAlign.center,
          style: TextStyle(color: sem.muted),
        ),
      );

  Widget _composer(BuildContext context, ChatRoom room, Sem sem) {
    final cs = Theme.of(context).colorScheme;
    final app = AppScope.read(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: sem.rule))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_reply != null || _editing != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(
              color: sem.surface2,
              borderRadius: BorderRadius.circular(10),
              border: BorderDirectional(start: BorderSide(color: cs.primary, width: 3)),
            ),
            child: Row(children: [
              Icon(_editing != null ? Icons.edit_rounded : Icons.reply_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _editing != null
                      ? 'تعديل الرسالة'
                      : 'ردّ على ${_reply!.sender == app.me?.id ? 'رسالتك' : app.people[_reply!.sender]?.displayName ?? ''}: '
                          '${_reply!.body.isNotEmpty ? _reply!.body : (_reply!.fileName ?? '')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'إلغاء',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  if (_editing != null) _text.clear();
                  _reply = null;
                  _editing = null;
                }),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ]),
          ),
        if (_files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in _files)
                InputChip(
                  avatar: Icon(f.mime.startsWith('image/') ? Icons.image_outlined : f.mime.startsWith('video/') ? Icons.movie_outlined : Icons.attach_file_rounded,
                      size: 18),
                  label: Text('${f.name} · ${fileSizeText(f.bytes.length)}', overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _files.remove(f)),
                ),
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (_editing == null)
            PopupMenuButton<String>(
              tooltip: 'إرفاق',
              icon: const Icon(Icons.add_circle_outline_rounded),
              onSelected: (v) => switch (v) {
                'media' => _attach(media: true),
                'file' => _attach(),
                _ => _shareContract(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'media', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('صور وفيديو'), dense: true)),
                PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.attach_file_rounded), title: Text('ملف (PDF، Word، Excel، صوت…)'), dense: true)),
                PopupMenuItem(value: 'contract', child: ListTile(leading: Icon(Icons.link_rounded), title: Text('رابط عقد من المنظومة'), dense: true)),
              ],
            ),
          Expanded(
            child: Focus(
              onKeyEvent: (node, e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                  _send();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _text,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                maxLength: 8000,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: _files.isNotEmpty ? 'تعليق على المرفق (اختياري)' : 'اكتب رسالة… (Shift+Enter لسطر جديد)',
                  filled: true,
                  fillColor: sem.surface2,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: _editing != null ? 'حفظ التعديل' : 'إرسال',
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded),
          ),
        ]),
      ]),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(99), border: Border.all(color: sem.rule)),
          child: Text(label, style: TextStyle(fontSize: 11.5, color: sem.muted, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.room, required this.embedded});

  final ChatRoom room;
  final bool embedded;

  Future<void> _action(BuildContext context, String a) async {
    final app = AppScope.read(context);
    final c = app.chat;
    try {
      switch (a) {
        case 'pin':
          await c.setPref(room.id, pinned: !room.pinned);
        case 'mute':
          await c.setPref(room.id, muted: !room.muted);
        case 'members':
          await showDialog<void>(context: context, builder: (_) => _MembersDialog(room: room));
        case 'edit':
          await showDialog<void>(context: context, builder: (_) => room.isChannel ? ChannelDialog(room: room) : _GroupDialog(room: room));
        case 'archive':
          await c.updateRoom(room.id, {'archived': !room.archived});
        case 'lock':
          if (room.locked) {
            await c.setLock(room.id, false, '');
          } else {
            final reason = await textInputDialog(context,
                title: 'قفل المحادثة',
                message: 'لا تُرسل فيها رسائل حتى تُفتح، وتبقى قراءتها متاحة لأعضائها. يُسجَّل القفل وسببه في سجل التدقيق.',
                label: 'سبب القفل',
                confirmLabel: 'قفل',
                required: true);
            if (reason == null) return;
            await c.setLock(room.id, true, reason);
          }
        case 'leave':
          final ok = await confirmDialog(context,
              title: 'مغادرة المجموعة', message: 'لن ترى رسائلها بعد المغادرة إلا إن أضافك مشرفها من جديد.', confirmLabel: 'مغادرة', danger: true);
          if (!ok) return;
          await c.leave(room.id);
          if (context.mounted && !embedded) Navigator.of(context).pop();
        case 'delete':
          final ok = await confirmDialog(context,
              title: 'حذف المحادثة',
              message: 'تُحذف المحادثة برسائلها ومرفقاتها عند كل أعضائها نهائياً، ويُسجَّل الحذف في سجل التدقيق.',
              confirmLabel: 'حذف نهائياً',
              danger: true);
          if (!ok) return;
          await c.deleteRoom(room.id);
          if (context.mounted && !embedded) Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final sub = switch (room.kind) {
      'dm' => [
          room.peer?.role == null ? '' : parseRole(room.peer!.role)?.label ?? '',
          if (room.peer?.active == false) 'غير مفعّل',
        ].where((s) => s.isNotEmpty).join(' · '),
      'group' => '${room.members ?? 0} عضواً${room.description.isNotEmpty ? ' · ${room.description}' : ''}',
      _ => '${_audienceText(app, room.audience)}${room.adminsOnly ? ' · إعلانات' : ''}',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: sem.rule))),
      child: Row(children: [
        if (!embedded) const BackButton(),
        const SizedBox(width: 6),
        if (room.isDm)
          InitialsAvatar(name: room.displayTitle, size: 38)
        else
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(11)),
            child: Icon(_roomIcon(room), color: cs.onSecondaryContainer, size: 21),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(room.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12)),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: 'خيارات المحادثة',
          onSelected: (v) => _action(context, v),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'pin', child: Text(room.pinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى')),
            PopupMenuItem(value: 'mute', child: Text(room.muted ? 'تشغيل التنبيه' : 'كتم التنبيه')),
            if (!room.isDm) const PopupMenuItem(value: 'members', child: Text('الأعضاء')),
            if (!room.isDm && (room.isAdmin || (room.isChannel && app.isDirector)))
              const PopupMenuItem(value: 'edit', child: Text('تعديل الاسم والوصف')),
            if (!room.isDm && (room.isAdmin || (room.isChannel && app.isDirector)))
              PopupMenuItem(value: 'archive', child: Text(room.archived ? 'إلغاء الأرشفة' : 'أرشفة')),
            if (app.canAudit) PopupMenuItem(value: 'lock', child: Text(room.locked ? 'فتح المحادثة' : 'قفل المحادثة (أمني)')),
            if (room.isGroup) const PopupMenuItem(value: 'leave', child: Text('مغادرة المجموعة')),
            if (room.id != generalChannelId && (app.isDirector || (room.isGroup && room.isOwner)))
              const PopupMenuItem(value: 'delete', child: Text('حذف المحادثة')),
          ],
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.room,
    required this.message,
    required this.showSender,
    required this.reply,
    required this.canEdit,
    required this.canDelete,
    required this.onAction,
  });

  final ChatRoom room;
  final ChatMessage message;
  final bool showSender;
  final ChatMessage? reply;
  final bool canEdit;
  final bool canDelete;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final m = message;
    if (m.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(m.body, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: sem.muted, fontStyle: FontStyle.italic)),
        ),
      );
    }
    final mine = m.sender == app.me?.id;
    final senderName = app.people[m.sender]?.displayName ?? 'مستخدم';
    final bg = mine ? cs.primaryContainer : sem.surface2;
    final fg = mine ? cs.onPrimaryContainer : null;
    final width = MediaQuery.sizeOf(context).width;
    final maxW = (width >= 900 ? 560.0 : width * 0.82);

    Widget body;
    if (m.deleted) {
      body = Text('حُذفت هذه الرسالة', style: TextStyle(fontStyle: FontStyle.italic, color: sem.muted));
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (reply != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: BorderDirectional(start: BorderSide(color: cs.primary, width: 3)),
            ),
            child: Text(
              '${reply!.sender == app.me?.id ? 'أنت' : app.people[reply!.sender]?.displayName ?? ''}: '
              '${reply!.deleted ? 'رسالة محذوفة' : reply!.body.isNotEmpty ? reply!.body : (reply!.fileName ?? reply!.ref?['label'] ?? '')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: sem.muted),
            ),
          ),
        if (m.isFile) _FileView(message: m),
        if (m.kind == 'link' && m.ref != null) _LinkCard(ref: m.ref!),
        if (m.body.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: m.isFile ? 6 : 0),
            child: SelectableText(m.body, style: TextStyle(color: fg, height: 1.45, fontSize: 14)),
          ),
      ]);
    }

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(
          padding: EdgeInsets.only(top: showSender ? 8 : 2, bottom: 2),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (showSender && !mine)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 10, bottom: 2),
                child: Text(senderName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.primary)),
              ),
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (mine && !m.deleted) _menu(context),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    body,
                    const SizedBox(height: 3),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (m.editedAt != null && !m.deleted) Text('معدّلة · ', style: TextStyle(fontSize: 10.5, color: sem.muted)),
                      Text(_hm(m.createdAt), style: TextStyle(fontSize: 10.5, color: sem.muted)),
                    ]),
                  ]),
                ),
              ),
              if (!mine && !m.deleted) _menu(context),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'خيارات الرسالة',
        icon: Icon(Icons.more_horiz_rounded, size: 18, color: Sem.of(context).muted),
        padding: EdgeInsets.zero,
        onSelected: onAction,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'reply', child: Text('ردّ')),
          if (message.body.isNotEmpty) const PopupMenuItem(value: 'copy', child: Text('نسخ النص')),
          if (canEdit) const PopupMenuItem(value: 'edit', child: Text('تعديل')),
          if (canDelete) const PopupMenuItem(value: 'delete', child: Text('حذف')),
        ],
      );
}

class _FileView extends StatelessWidget {
  const _FileView({required this.message});

  final ChatMessage message;

  Future<void> _open(BuildContext context) async {
    try {
      final url = await AppScope.read(context).chat.url(message.filePath!);
      await openDocExternally(url);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final m = message;
    if (m.isImage) {
      final ratio = (m.width != null && m.height != null && m.height! > 0) ? m.width! / m.height! : 4 / 3;
      return GestureDetector(
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 420),
            child: AspectRatio(
              aspectRatio: ratio.clamp(0.5, 2.2),
              child: FutureBuilder<String>(
                future: app.chat.url(m.filePath!),
                builder: (_, s) => s.hasData
                    ? Image.network(s.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: sem.surface2))
                    : Container(color: sem.surface2, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
          ),
        ),
      );
    }
    final icon = m.isVideo
        ? Icons.play_circle_fill_rounded
        : m.isAudio
            ? Icons.graphic_eq_rounded
            : (m.fileMime ?? '').contains('pdf')
                ? Icons.picture_as_pdf_rounded
                : (m.fileMime ?? '').contains('sheet')
                    ? Icons.grid_on_rounded
                    : (m.fileMime ?? '').contains('word')
                        ? Icons.description_rounded
                        : Icons.insert_drive_file_rounded;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(m.fileName ?? 'مرفق', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${m.isVideo ? 'فيديو' : m.isAudio ? 'تسجيل صوتي' : 'ملف'} · ${fileSizeText(m.fileSize)} · اضغط للفتح',
                  style: TextStyle(fontSize: 11.5, color: sem.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.ref});

  final Map<String, dynamic> ref;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final sem = Sem.of(context);
    final id = (ref['id'] ?? '').toString();
    final exists = ref['type'] == 'project' && app.project(id) != null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: exists ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: id))) : null,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10), border: Border.all(color: sem.rule)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_rounded, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text((ref['label'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
              if ((ref['sub'] ?? '').toString().isNotEmpty) Text(ref['sub'].toString(), style: TextStyle(fontSize: 12, color: sem.muted)),
              Text(exists ? 'فتح العقد' : 'العقد غير متاح', style: TextStyle(fontSize: 11.5, color: exists ? cs.primary : sem.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// اختيار شخص أو أكثر من مستخدمي المنظومة المفعّلين.
Future<List<String>?> pickPeople(BuildContext context, {required String title, bool single = false, Set<String> exclude = const {}}) =>
    showDialog<List<String>>(context: context, builder: (_) => _PeoplePicker(title: title, single: single, exclude: exclude));

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.title, required this.single, required this.exclude});

  final String title;
  final bool single;
  final Set<String> exclude;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  final _q = TextEditingController();
  final Set<String> _picked = {};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final q = _q.text.trim();
    final people = app.people.values
        .where((p) => p.active && p.role != null && p.id != app.me?.id && !widget.exclude.contains(p.id))
        .where((p) => q.isEmpty || p.displayName.contains(q) || p.email.contains(q))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: fieldDeco('بحث بالاسم أو البريد', prefixIcon: const Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: people.isEmpty
                ? Center(child: Text('لا أحد', style: TextStyle(color: sem.muted)))
                : ListView(children: [
                    for (final p in people)
                      widget.single
                          ? ListTile(
                              leading: InitialsAvatar(name: p.displayName, size: 34),
                              title: Text(p.displayName),
                              subtitle: Text([p.role?.label ?? '', if (p.unit != null) unitNames[p.unit] ?? ''].where((s) => s.isNotEmpty).join(' · ')),
                              onTap: () => Navigator.of(context).pop([p.id]),
                            )
                          : CheckboxListTile(
                              value: _picked.contains(p.id),
                              onChanged: (v) => setState(() => v == true ? _picked.add(p.id) : _picked.remove(p.id)),
                              secondary: InitialsAvatar(name: p.displayName, size: 34),
                              title: Text(p.displayName),
                              subtitle: Text(p.role?.label ?? ''),
                            ),
                  ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        if (!widget.single)
          FilledButton(
            onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop(_picked.toList()),
            child: Text('اختيار (${_picked.length})'),
          ),
      ],
    );
  }
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({this.room});

  final ChatRoom? room;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final _title = TextEditingController(text: widget.room?.title ?? '');
  late final _desc = TextEditingController(text: widget.room?.description ?? '');
  final List<String> _members = [];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      if (widget.room == null) {
        final id = await app.chat.createGroup(_title.text.trim(), _members, description: _desc.text.trim());
        if (mounted) Navigator.of(context).pop(id);
      } else {
        await app.chat.updateRoom(widget.room!.id, {'title': _title.text.trim(), 'description': _desc.text.trim()});
        if (mounted) Navigator.of(context).pop(widget.room!.id);
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final edit = widget.room != null;
    return AlertDialog(
      title: Text(edit ? 'تعديل المجموعة' : 'مجموعة جديدة'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _title, autofocus: true, maxLength: 80, decoration: fieldDeco('اسم المجموعة'), onChanged: (_) => setState(() {})),
          TextField(controller: _desc, maxLength: 500, minLines: 1, maxLines: 3, decoration: fieldDeco('الوصف (اختياري)')),
          if (!edit) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final id in _members)
                InputChip(label: Text(app.people[id]?.displayName ?? id), onDeleted: () => setState(() => _members.remove(id))),
              ActionChip(
                avatar: const Icon(Icons.person_add_alt_rounded, size: 18),
                label: const Text('إضافة أعضاء'),
                onPressed: () async {
                  final picked = await pickPeople(context, title: 'أعضاء المجموعة', exclude: _members.toSet());
                  if (picked != null) setState(() => _members.addAll(picked));
                },
              ),
            ]),
            const SizedBox(height: 8),
            Text('تكون أنت مالك المجموعة، وتعيّن مشرفين يضيفون الأعضاء ويحذفون الرسائل.',
                style: TextStyle(color: Sem.of(context).muted, fontSize: 12.5)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy || _title.text.trim().length < 2 || (!edit && _members.isEmpty) ? null : _save,
          child: Text(edit ? 'حفظ' : 'إنشاء'),
        ),
      ],
    );
  }
}

/// إنشاء قناة أو تعديلها (للمدير): الاسم والوصف والجمهور، وهل الإرسال للمشرفين فقط.
class ChannelDialog extends StatefulWidget {
  const ChannelDialog({super.key, this.room});

  final ChatRoom? room;

  @override
  State<ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<ChannelDialog> {
  late final _title = TextEditingController(text: widget.room?.title ?? '');
  late final _desc = TextEditingController(text: widget.room?.description ?? '');
  late bool _all = widget.room?.audience['all'] == true;
  late final Set<String> _roles = {for (final x in (widget.room?.audience['roles'] as List? ?? const [])) x.toString()};
  late final Set<String> _depts = {for (final x in (widget.room?.audience['departments'] as List? ?? const [])) x.toString()};
  late final Set<String> _units = {for (final x in (widget.room?.audience['units'] as List? ?? const [])) x.toString()};
  late bool _adminsOnly = widget.room?.adminsOnly ?? false;
  bool _busy = false;

  Map<String, dynamic> get _audience => _all
      ? {'all': true}
      : {
          if (_roles.isNotEmpty) 'roles': _roles.toList(),
          if (_depts.isNotEmpty) 'departments': _depts.toList(),
          if (_units.isNotEmpty) 'units': _units.toList(),
          if ((widget.room?.audience['users'] as List?)?.isNotEmpty ?? false) 'users': widget.room!.audience['users'],
        };

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      if (widget.room == null) {
        final id = await app.chat.createChannel(_title.text.trim(), _desc.text.trim(), _audience, adminsOnly: _adminsOnly);
        if (mounted) Navigator.of(context).pop(id);
      } else {
        await app.chat.updateRoom(widget.room!.id, {
          'title': _title.text.trim(),
          'description': _desc.text.trim(),
          'admins_only': _adminsOnly,
          if (widget.room!.id != generalChannelId) 'audience': _audience,
        });
        if (mounted) Navigator.of(context).pop(widget.room!.id);
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final general = widget.room?.id == generalChannelId;
    Widget chips(String label, List<(String, String)> items, Set<String> set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final it in items)
                FilterChip(
                  label: Text(it.$2),
                  selected: set.contains(it.$1),
                  onSelected: _all ? null : (v) => setState(() => v ? set.add(it.$1) : set.remove(it.$1)),
                ),
            ]),
          ],
        );
    final empty = !_all && _roles.isEmpty && _depts.isEmpty && _units.isEmpty;
    return AlertDialog(
      title: Text(widget.room == null ? 'قناة جديدة' : 'تعديل القناة'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _title, maxLength: 80, decoration: fieldDeco('اسم القناة'), onChanged: (_) => setState(() {})),
            TextField(controller: _desc, maxLength: 500, minLines: 1, maxLines: 3, decoration: fieldDeco('الوصف')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _adminsOnly,
              onChanged: (v) => setState(() => _adminsOnly = v),
              title: const Text('قناة إعلانات'),
              subtitle: const Text('يرسل فيها المدير ومن يعيّنه مشرفاً فقط، ويقرأ الباقون.'),
            ),
            if (!general) ...[
              const Divider(),
              Text('الجمهور: يدخل القناة تلقائياً كل من يطابق أحد الاختيارات', style: TextStyle(color: sem.muted)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _all,
                onChanged: (v) => setState(() => _all = v),
                title: const Text('كل المكتب'),
              ),
              chips('الأدوار', [for (final r in AppRole.values) if (r != AppRole.director) (r.db, r.label)], _roles),
              chips('الأقسام', [for (final d in app.departments) (d.key, d.name)], _depts),
              chips('الوحدات', [for (final u in unitKeys) (u, unitNames[u] ?? u)], _units),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy || _title.text.trim().length < 2 || (!general && empty) ? null : _save,
          child: Text(widget.room == null ? 'إنشاء' : 'حفظ'),
        ),
      ],
    );
  }
}

class _MembersDialog extends StatefulWidget {
  const _MembersDialog({required this.room});

  final ChatRoom room;

  @override
  State<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends State<_MembersDialog> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).chat.members(widget.room.id);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final room = app.chat.room(widget.room.id) ?? widget.room;
    final manage = room.isAdmin || (room.isChannel && app.isDirector);
    final rows = _rows;
    return AlertDialog(
      title: Text('أعضاء «${room.displayTitle}»'),
      content: SizedBox(
        width: 480,
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (room.isChannel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBanner(text: 'الجمهور: ${_audienceText(app, room.audience)}. المذكورون أدناه مشرفون أو أعضاء أُضيفوا بالاسم.'),
            ),
          Expanded(
            child: rows == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(child: Text('لا أعضاء مضافين بالاسم', style: TextStyle(color: sem.muted)))
                    : ListView(children: [
                        for (final r in rows)
                          ListTile(
                            leading: InitialsAvatar(name: app.people[r['user_id']]?.displayName ?? '؟', size: 34),
                            title: Text(app.people[r['user_id']]?.displayName ?? 'مستخدم'),
                            subtitle: Text(switch (r['role']) { 'owner' => 'المالك', 'admin' => 'مشرف', _ => 'عضو' }),
                            trailing: !manage || r['role'] == 'owner' || r['user_id'] == app.me?.id
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (v) => _run(() => switch (v) {
                                          'admin' => app.chat.setMemberRole(room.id, r['user_id'].toString(), 'admin'),
                                          'member' => app.chat.setMemberRole(room.id, r['user_id'].toString(), 'member'),
                                          _ => app.chat.setMembers(room.id, remove: [r['user_id'].toString()]),
                                        }),
                                    itemBuilder: (_) => [
                                      if (r['role'] != 'admin' && (room.isOwner || app.isDirector))
                                        const PopupMenuItem(value: 'admin', child: Text('تعيين مشرفاً')),
                                      if (r['role'] == 'admin' && (room.isOwner || app.isDirector))
                                        const PopupMenuItem(value: 'member', child: Text('إلغاء الإشراف')),
                                      const PopupMenuItem(value: 'remove', child: Text('إزالة')),
                                    ],
                                  ),
                          ),
                      ]),
          ),
        ]),
      ),
      actions: [
        if (manage)
          TextButton.icon(
            onPressed: () async {
              final picked = await pickPeople(context,
                  title: room.isChannel ? 'إضافة إلى القناة' : 'إضافة أعضاء', exclude: {for (final r in rows ?? const []) r['user_id'].toString()});
              if (picked != null && picked.isNotEmpty) await _run(() => app.chat.setMembers(room.id, add: picked));
            },
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('إضافة'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
      ],
    );
  }
}

class _ContractPicker extends StatefulWidget {
  const _ContractPicker();

  @override
  State<_ContractPicker> createState() => _ContractPickerState();
}

class _ContractPickerState extends State<_ContractPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = _q.text.trim();
    final list = app.projects.where((p) => q.isEmpty || p.label.contains(q) || p.company.contains(q)).take(80).toList();
    return AlertDialog(
      title: const Text('رابط عقد'),
      content: SizedBox(
        width: 480,
        height: 440,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: fieldDeco('بحث برقم العقد أو اسمه أو الشركة', prefixIcon: const Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final p in list)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(p.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: p.company.isEmpty ? null : Text(p.company),
                  onTap: () => Navigator.of(context).pop(p),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء'))],
    );
  }
}

/// إعدادات المراسلات (للمدير).
class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  Map<String, dynamic>? _cfg;
  bool _busy = false;

  Map<String, dynamic> _current(AppState app) {
    final v = app.settings.raw['chat.config'];
    return {
      'enabled': true,
      'groups': true,
      'max_file_mb': 50,
      'edit_minutes': 60,
      if (v is Map) ...Map<String, dynamic>.from(v),
    };
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await app.setSetting('chat.config', _cfg);
      if (mounted) showToast(context, 'حُفظت إعدادات المراسلات');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cfg = _cfg ??= _current(app);
    final mb = (cfg['max_file_mb'] as num).toDouble().clamp(1, 50).toDouble();
    final mins = (cfg['edit_minutes'] as num).toDouble().clamp(0, 1440).toDouble();
    return PageBody(maxWidth: 820, children: [
      const PageHeader(
        title: 'إعدادات المراسلات',
        subtitle: 'تُطبَّق على كل المستخدمين فوراً. القفل الأمني للمحادثات من صلاحية مسؤول الأمن والمدير.',
        icon: Icons.settings_outlined,
      ),
      SectionCard(
        title: 'التشغيل',
        child: Column(children: [
          SwitchListTile(
            value: cfg['enabled'] == true,
            onChanged: (v) => setState(() => cfg['enabled'] = v),
            title: const Text('المراسلات مفعّلة'),
            subtitle: const Text('عند الإيقاف تبقى المحادثات مقروءة ولا تُرسل رسائل جديدة.'),
          ),
          SwitchListTile(
            value: cfg['groups'] == true,
            onChanged: (v) => setState(() => cfg['groups'] = v),
            title: const Text('يُنشئ الموظفون مجموعات خاصة'),
            subtitle: const Text('عند الإيقاف ينشئ المجموعات مدير المكتب وحده.'),
          ),
        ]),
      ),
      SectionCard(
        title: 'الحدود',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('أكبر حجم للمرفق: ${mb.round()} ميجابايت'),
          Slider(value: mb, min: 1, max: 50, divisions: 49, label: '${mb.round()}', onChanged: (v) => setState(() => cfg['max_file_mb'] = v.round())),
          const SizedBox(height: 8),
          Text(mins == 0 ? 'لا يُسمح بتعديل الرسائل بعد إرسالها' : 'تعديل الرسالة متاح خلال ${mins.round()} دقيقة من إرسالها'),
          Slider(value: mins, min: 0, max: 1440, divisions: 96, label: '${mins.round()}', onChanged: (v) => setState(() => cfg['edit_minutes'] = v.round())),
        ]),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
      ),
    ]);
  }
}
