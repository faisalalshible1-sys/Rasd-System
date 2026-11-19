// =====================================================================
// المراسلات الداخلية (الترحيل 24): المحادثات الخاصة والمجموعات وقنوات الأقسام، والرسائل والمرفقات،
// والتحديث اللحظي وغير المقروء. قاعدة البيانات صاحبة القرار في الوصول؛ ما هنا للعرض والإرسال.
// =====================================================================

import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';

const String chatBucket = 'chat';
const String generalChannelId = '00000000-0000-4000-8000-00000000c4a7';

/// الامتدادات المسموحة في المرفقات (تطابق حاوية المراسلات).
const Map<String, String> chatMimes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'm4a': 'audio/mp4',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'wav': 'audio/wav',
  'aac': 'audio/aac',
  'pdf': 'application/pdf',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'zip': 'application/zip',
};

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class ChatPeer {
  const ChatPeer({required this.id, required this.name, this.active = true, this.role});

  final String id;
  final String name;
  final bool active;
  final String? role;
}

class ChatPreview {
  const ChatPreview({required this.id, required this.kind, this.sender, this.senderName = '', this.at, this.text = '', this.deleted = false, this.mime});

  final int id;
  final String kind;
  final String? sender;
  final String senderName;
  final DateTime? at;
  final String text;
  final bool deleted;
  final String? mime;
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.kind,
    this.title = '',
    this.description = '',
    this.adminsOnly = false,
    this.locked = false,
    this.lockReason = '',
    this.archived = false,
    this.createdAt,
    this.lastMessageAt,
    this.myRole = 'member',
    this.muted = false,
    this.pinned = false,
    this.lastReadId = 0,
    this.unread = 0,
    this.members,
    this.peer,
    this.last,
    this.audience = const {},
    this.createdBy,
  });

  final String id;

  /// dm خاصة بين شخصين، group مجموعة، channel قناة.
  final String kind;
  final String title;
  final String description;
  final bool adminsOnly;
  final bool locked;
  final String lockReason;
  final bool archived;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final String myRole;
  final bool muted;
  final bool pinned;
  final int lastReadId;
  final int unread;
  final int? members;
  final ChatPeer? peer;
  final ChatPreview? last;
  final Map<String, dynamic> audience;
  final String? createdBy;

  bool get isDm => kind == 'dm';
  bool get isGroup => kind == 'group';
  bool get isChannel => kind == 'channel';
  bool get isAdmin => myRole == 'owner' || myRole == 'admin';
  bool get isOwner => myRole == 'owner';

  String get displayTitle => isDm ? (peer?.name ?? 'محادثة خاصة') : title;

  DateTime? get activity => lastMessageAt ?? createdAt;

  factory ChatRoom.fromMap(Map<String, dynamic> m) {
    final p = m['peer'];
    final l = m['last'];
    return ChatRoom(
      id: m['id'].toString(),
      kind: (m['kind'] ?? 'group').toString(),
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      adminsOnly: m['admins_only'] == true,
      locked: m['locked'] == true,
      lockReason: (m['lock_reason'] ?? '').toString(),
      archived: m['archived'] == true,
      createdAt: _dt(m['created_at']),
      lastMessageAt: _dt(m['last_message_at']),
      myRole: (m['my_role'] ?? 'member').toString(),
      muted: m['muted'] == true,
      pinned: m['pinned'] == true,
      lastReadId: (m['last_read_id'] as num?)?.toInt() ?? 0,
      unread: (m['unread'] as num?)?.toInt() ?? 0,
      members: (m['members'] as num?)?.toInt(),
      peer: p is Map
          ? ChatPeer(id: p['id'].toString(), name: (p['name'] ?? '').toString(), active: p['active'] != false, role: p['role'] as String?)
          : null,
      last: l is Map
          ? ChatPreview(
              id: (l['id'] as num?)?.toInt() ?? 0,
              kind: (l['kind'] ?? 'text').toString(),
              sender: l['sender'] as String?,
              senderName: (l['sender_name'] ?? '').toString(),
              at: _dt(l['at']),
              text: (l['text'] ?? '').toString(),
              deleted: l['deleted'] == true,
              mime: l['mime'] as String?,
            )
          : null,
      audience: m['audience'] is Map ? Map<String, dynamic>.from(m['audience'] as Map) : const {},
      createdBy: m['created_by'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    this.sender,
    this.kind = 'text',
    this.body = '',
    this.filePath,
    this.fileName,
    this.fileMime,
    this.fileSize,
    this.width,
    this.height,
    this.ref,
    this.replyTo,
    this.createdAt,
    this.editedAt,
    this.deletedAt,
  });

  final int id;
  final String roomId;
  final String? sender;
  final String kind;
  final String body;
  final String? filePath;
  final String? fileName;
  final String? fileMime;
  final int? fileSize;
  final int? width;
  final int? height;
  final Map<String, dynamic>? ref;
  final int? replyTo;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;
  bool get isSystem => kind == 'system';
  bool get isFile => kind == 'file' && filePath != null;
  bool get isImage => isFile && (fileMime ?? '').startsWith('image/');
  bool get isVideo => isFile && (fileMime ?? '').startsWith('video/');
  bool get isAudio => isFile && (fileMime ?? '').startsWith('audio/');

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: (m['id'] as num).toInt(),
        roomId: m['room_id'].toString(),
        sender: m['sender'] as String?,
        kind: (m['kind'] ?? 'text').toString(),
        body: (m['body'] ?? '').toString(),
        filePath: m['file_path'] as String?,
        fileName: m['file_name'] as String?,
        fileMime: m['file_mime'] as String?,
        fileSize: (m['file_size'] as num?)?.toInt(),
        width: (m['width'] as num?)?.toInt(),
        height: (m['height'] as num?)?.toInt(),
        ref: m['ref'] is Map ? Map<String, dynamic>.from(m['ref'] as Map) : null,
        replyTo: (m['reply_to'] as num?)?.toInt(),
        createdAt: _dt(m['created_at']),
        editedAt: _dt(m['edited_at']),
        deletedAt: _dt(m['deleted_at']),
      );
}

/// مرفق مختار قبل الإرسال.
class ChatAttachment {
  ChatAttachment({required this.name, required this.bytes, required this.ext, required this.mime, this.width, this.height});

  final String name;
  final Uint8List bytes;
  final String ext;
  final String mime;
  final int? width;
  final int? height;
}

(Uint8List, String, int?, int?) _shrinkChat((Uint8List, String) input) {
  final (bytes, ext) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return (bytes, ext, null, null);
  if (ext == 'gif') return (bytes, ext, decoded.width, decoded.height);
  const side = 2000;
  final big = decoded.width > side || decoded.height > side;
  if (!big && bytes.length <= 1024 * 1024) return (bytes, ext, decoded.width, decoded.height);
  final resized = big
      ? img.copyResize(decoded,
          width: decoded.width >= decoded.height ? side : null,
          height: decoded.height > decoded.width ? side : null,
          interpolation: img.Interpolation.average)
      : decoded;
  final out = Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  if (out.length >= bytes.length && !big) return (bytes, ext, decoded.width, decoded.height);
  return (out, 'jpg', resized.width, resized.height);
}

/// يختار المستخدم مرفقات (صور تُضغط، وفيديو وصوت وملفات كما هي) حتى [maxMb].
Future<List<ChatAttachment>> pickChatFiles({int maxMb = 50, bool media = false}) async {
  final exts = media ? ['jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', 'mov', 'webm'] : chatMimes.keys.toList();
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: exts, allowMultiple: true);
  final out = <ChatAttachment>[];
  for (final f in picked) {
    var ext = f.name.contains('.') ? f.name.substring(f.name.lastIndexOf('.') + 1).toLowerCase() : '';
    if (ext == 'jpeg') ext = 'jpg';
    if (!chatMimes.containsKey(ext)) {
      throw StateError('نوع الملف «${f.name}» غير مسموح في المراسلات.');
    }
    var bytes = await f.readAsBytes();
    int? w, h;
    var name = f.name;
    if (['jpg', 'png', 'webp', 'gif'].contains(ext)) {
      final r = await compute(_shrinkChat, (bytes, ext));
      bytes = r.$1;
      w = r.$3;
      h = r.$4;
      if (r.$2 != ext) {
        ext = r.$2;
        final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
        name = '$base.$ext';
      }
    }
    if (bytes.length > maxMb * 1024 * 1024) {
      throw StateError('«${f.name}» أكبر من $maxMb ميجابايت.');
    }
    out.add(ChatAttachment(name: name, bytes: bytes, ext: ext, mime: chatMimes[ext]!, width: w, height: h));
  }
  return out;
}

final Random _rnd = Random.secure();
const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

String newChatPath(String roomId, String ext) {
  final id = List.generate(22, (_) => _alphabet[_rnd.nextInt(_alphabet.length)]).join();
  return '$roomId/$id.$ext';
}

String fileSizeText(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes بايت';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} ك.ب';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} م.ب';
  return '${(bytes / 1073741824).toStringAsFixed(2)} ج.ب';
}

/// حالة المراسلات: قائمة المحادثات، والرسائل المحمّلة لكل محادثة، والتحديث اللحظي.
class ChatController extends ChangeNotifier {
  ChatController(this.app);

  final AppState app;
  SupabaseClient get client => app.client;

  List<ChatRoom> rooms = [];
  bool loaded = false;
  String? error;
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, bool> _more = {};
  final Map<String, (String, DateTime)> _urls = {};
  RealtimeChannel? _ch;
  Timer? _debounce;
  bool _disposed = false;

  /// المحادثة المفتوحة الآن (تُعلَّم مقروءة عند وصول رسائل).
  String? openRoom;

  int get unreadTotal => rooms.where((r) => !r.muted).fold(0, (s, r) => s + r.unread);

  ChatRoom? room(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<ChatMessage> messagesOf(String roomId) => _messages[roomId] ?? const [];
  bool hasMore(String roomId) => _more[roomId] ?? false;
  bool isLoaded(String roomId) => _messages.containsKey(roomId);

  ChatMessage? message(String roomId, int id) {
    for (final m in messagesOf(roomId)) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    app.chatChanged();
  }

  void start() {
    unawaited(refreshRooms());
    _subscribe();
  }

  void stop() {
    final c = _ch;
    if (c != null) client.removeChannel(c);
    _ch = null;
    rooms = [];
    loaded = false;
    _messages.clear();
    _more.clear();
    _urls.clear();
    openRoom = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    final c = _ch;
    if (c != null) client.removeChannel(c);
    super.dispose();
  }

  Future<void> refreshRooms() async {
    try {
      final res = await client.rpc('chat_my_rooms');
      rooms = [for (final x in (res as List? ?? const [])) ChatRoom.fromMap(Map<String, dynamic>.from(x as Map))];
      loaded = true;
      error = null;
    } catch (e) {
      error = e.toString();
    }
    _changed();
  }

  void _scheduleRooms() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!_disposed) refreshRooms();
    });
  }

  void _subscribe() {
    final old = _ch;
    if (old != null) client.removeChannel(old);
    final ch = client.channel('rasd-chat');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_messages',
      callback: (p) => _onMessage(p.newRecord),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'chat_messages',
      callback: (p) => _onMessage(p.newRecord, update: true),
    );
    for (final t in const ['chat_rooms', 'chat_members']) {
      ch.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => _scheduleRooms());
    }
    ch.subscribe();
    _ch = ch;
  }

  void _onMessage(Map<String, dynamic> rec, {bool update = false}) {
    if (rec.isEmpty || rec['id'] == null || rec['room_id'] == null) return;
    final m = ChatMessage.fromMap(rec);
    _merge(m);
    if (!update && openRoom == m.roomId && m.sender != app.me?.id) {
      unawaited(markRead(m.roomId, m.id));
    }
    _scheduleRooms();
  }

  void _merge(ChatMessage m) {
    final list = _messages[m.roomId];
    if (list == null) return;
    final i = list.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.add(m);
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    _changed();
  }

  Future<void> loadMessages(String roomId, {bool older = false}) async {
    final list = _messages[roomId];
    var q = client.from('chat_messages').select().eq('room_id', roomId);
    if (older && list != null && list.isNotEmpty) q = q.lt('id', list.first.id);
    final res = await q.order('id', ascending: false).limit(60);
    final got = [for (final r in res) ChatMessage.fromMap(r)].reversed.toList();
    if (older && list != null) {
      _messages[roomId] = [...got, ...list];
    } else {
      _messages[roomId] = got;
    }
    _more[roomId] = got.length >= 60;
    _changed();
  }

  Future<void> open(String roomId) async {
    openRoom = roomId;
    if (!isLoaded(roomId)) await loadMessages(roomId);
    final list = messagesOf(roomId);
    final r = room(roomId);
    if (list.isNotEmpty && (r == null || r.unread > 0 || r.lastReadId < list.last.id)) {
      await markRead(roomId, list.last.id);
    }
  }

  void close(String roomId) {
    if (openRoom == roomId) openRoom = null;
  }

  Future<void> markRead(String roomId, int last) async {
    try {
      await client.rpc('chat_mark_read', params: {'p_room': roomId, 'p_last': last});
      final i = rooms.indexWhere((r) => r.id == roomId);
      if (i >= 0 && rooms[i].unread > 0) {
        final r = rooms[i];
        rooms[i] = ChatRoom(
          id: r.id,
          kind: r.kind,
          title: r.title,
          description: r.description,
          adminsOnly: r.adminsOnly,
          locked: r.locked,
          lockReason: r.lockReason,
          archived: r.archived,
          createdAt: r.createdAt,
          lastMessageAt: r.lastMessageAt,
          myRole: r.myRole,
          muted: r.muted,
          pinned: r.pinned,
          lastReadId: last,
          unread: 0,
          members: r.members,
          peer: r.peer,
          last: r.last,
          audience: r.audience,
          createdBy: r.createdBy,
        );
        _changed();
      }
    } catch (_) {}
  }

  Future<int> send(String roomId, String text, {ChatAttachment? file, int? replyTo, Map<String, String>? ref}) async {
    Map<String, dynamic>? fileArg;
    String? uploaded;
    if (file != null) {
      final path = newChatPath(roomId, file.ext);
      await client.storage.from(chatBucket).uploadBinary(path, file.bytes, fileOptions: FileOptions(contentType: file.mime, upsert: false));
      uploaded = path;
      fileArg = {'path': path, 'name': file.name, if (file.width != null) 'width': file.width, if (file.height != null) 'height': file.height};
    }
    try {
      final res = await client.rpc('chat_send', params: {
        'p_room': roomId,
        'p_body': text,
        'p_file': fileArg,
        'p_reply_to': replyTo,
        'p_ref': ref,
      });
      final id = (res as num).toInt();
      if (isLoaded(roomId) && message(roomId, id) == null) {
        // أضفه فوراً دون انتظار التحديث اللحظي
        final rows = await client.from('chat_messages').select().eq('id', id).limit(1);
        if (rows.isNotEmpty) _merge(ChatMessage.fromMap(rows.first));
      }
      _scheduleRooms();
      return id;
    } catch (e) {
      if (uploaded != null) {
        try {
          await client.storage.from(chatBucket).remove([uploaded]);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> edit(ChatMessage m, String text) async {
    await client.rpc('chat_edit_message', params: {'p_id': m.id, 'p_body': text});
    final rows = await client.from('chat_messages').select().eq('id', m.id).limit(1);
    if (rows.isNotEmpty) _merge(ChatMessage.fromMap(rows.first));
  }

  Future<void> delete(ChatMessage m) async {
    final path = await client.rpc('chat_delete_message', params: {'p_id': m.id});
    if (path is String && path.isNotEmpty) {
      try {
        await client.storage.from(chatBucket).remove([path]);
      } catch (_) {}
    }
    final rows = await client.from('chat_messages').select().eq('id', m.id).limit(1);
    if (rows.isNotEmpty) _merge(ChatMessage.fromMap(rows.first));
    _scheduleRooms();
  }

  Future<String> openDm(String userId) async {
    final id = (await client.rpc('chat_open_dm', params: {'p_user': userId})).toString();
    await refreshRooms();
    return id;
  }

  Future<String> createGroup(String title, List<String> members, {String description = ''}) async {
    final id = (await client.rpc('chat_create_group', params: {'p_title': title, 'p_members': members, 'p_description': description})).toString();
    await refreshRooms();
    return id;
  }

  Future<String> createChannel(String title, String description, Map<String, dynamic> audience, {bool adminsOnly = false}) async {
    final id = (await client.rpc('chat_create_channel', params: {
      'p_title': title,
      'p_description': description,
      'p_audience': audience,
      'p_admins_only': adminsOnly,
    }))
        .toString();
    await refreshRooms();
    return id;
  }

  Future<void> updateRoom(String roomId, Map<String, dynamic> data) async {
    await client.rpc('chat_update_room', params: {'p_room': roomId, 'p_data': data});
    await refreshRooms();
  }

  Future<void> setMembers(String roomId, {List<String> add = const [], List<String> remove = const []}) async {
    await client.rpc('chat_set_members', params: {'p_room': roomId, 'p_add': add, 'p_remove': remove});
    await refreshRooms();
  }

  Future<void> setMemberRole(String roomId, String userId, String role) async {
    await client.rpc('chat_set_member_role', params: {'p_room': roomId, 'p_user': userId, 'p_role': role});
    await refreshRooms();
  }

  Future<void> leave(String roomId) async {
    await client.rpc('chat_leave', params: {'p_room': roomId});
    _messages.remove(roomId);
    if (openRoom == roomId) openRoom = null;
    await refreshRooms();
  }

  Future<void> setPref(String roomId, {bool? muted, bool? pinned}) async {
    await client.rpc('chat_set_pref', params: {'p_room': roomId, 'p_muted': muted, 'p_pinned': pinned});
    await refreshRooms();
  }

  Future<void> setLock(String roomId, bool locked, String reason) async {
    await client.rpc('chat_set_lock', params: {'p_room': roomId, 'p_locked': locked, 'p_reason': reason});
    await refreshRooms();
  }

  Future<void> deleteRoom(String roomId) async {
    final paths = await client.rpc('chat_delete_room', params: {'p_room': roomId});
    final list = [for (final p in (paths as List? ?? const [])) p.toString()];
    if (list.isNotEmpty) {
      try {
        await client.storage.from(chatBucket).remove(list);
      } catch (_) {}
    }
    _messages.remove(roomId);
    if (openRoom == roomId) openRoom = null;
    await refreshRooms();
  }

  /// أعضاء المحادثة الصريحون (للمجموعات والقنوات المحددة بأشخاص).
  Future<List<Map<String, dynamic>>> members(String roomId) async {
    final res = await client.from('chat_members').select('user_id, role, joined_at, explicit').eq('room_id', roomId).eq('explicit', true);
    return [for (final r in res) Map<String, dynamic>.from(r)];
  }

  /// رابط موقّع لمرفق (ساعة) مع ذاكرة قصيرة.
  Future<String> url(String path) async {
    final hit = _urls[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final u = await client.storage.from(chatBucket).createSignedUrl(path, 3600);
    _urls[path] = (u, DateTime.now().add(const Duration(minutes: 50)));
    return u;
  }

  Future<Uint8List> download(String path) => client.storage.from(chatBucket).download(path);
}
