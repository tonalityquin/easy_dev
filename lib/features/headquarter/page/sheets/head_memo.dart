import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/auth/gmail_sender_auth.dart';
import '../../../../app/auth/google_auth_session.dart';
import '../../../../app/config/email_config.dart';
import '../../../../app/init/app_navigator.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../dev/debug/debug_api_logger.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';

part 'head_memo_side_dock.dart';

class HeadMemoTodo {
  const HeadMemoTodo({
    required this.id,
    required this.text,
    required this.done,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String text;
  final bool done;
  final DateTime createdAt;
  final DateTime updatedAt;

  HeadMemoTodo copyWith({
    String? id,
    String? text,
    bool? done,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HeadMemoTodo(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'done': done,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory HeadMemoTodo.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return HeadMemoTodo(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : HeadMemo._newId('todo'),
      text: (json['text'] as String?) ?? '',
      done: json['done'] == true,
      createdAt: HeadMemo._parseDate(json['createdAt']) ?? now,
      updatedAt: HeadMemo._parseDate(json['updatedAt']) ?? now,
    );
  }
}

class HeadMemoPage {
  const HeadMemoPage({
    required this.id,
    required this.header,
    required this.body,
    required this.todos,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String header;
  final String body;
  final List<HeadMemoTodo> todos;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get completedTodoCount => todos.where((e) => e.done).length;

  HeadMemoPage copyWith({
    String? id,
    String? header,
    String? body,
    List<HeadMemoTodo>? todos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HeadMemoPage(
      id: id ?? this.id,
      header: header ?? this.header,
      body: body ?? this.body,
      todos: todos ?? this.todos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'header': header,
      'body': body,
      'todos': todos.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory HeadMemoPage.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawTodos = json['todos'];
    final todos = rawTodos is List
        ? rawTodos
            .whereType<Map>()
            .map((e) => HeadMemoTodo.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <HeadMemoTodo>[];
    return HeadMemoPage(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : HeadMemo._newId('page'),
      header: (json['header'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      todos: todos,
      createdAt: HeadMemo._parseDate(json['createdAt']) ?? now,
      updatedAt: HeadMemo._parseDate(json['updatedAt']) ?? now,
    );
  }
}

class HeadMemoBook {
  const HeadMemoBook({
    required this.id,
    required this.name,
    required this.pages,
    required this.headerFontSize,
    required this.bodyFontSize,
    required this.accentColorId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<HeadMemoPage> pages;
  final double headerFontSize;
  final double bodyFontSize;
  final String accentColorId;
  final DateTime createdAt;
  final DateTime updatedAt;

  HeadMemoBook copyWith({
    String? id,
    String? name,
    List<HeadMemoPage>? pages,
    double? headerFontSize,
    double? bodyFontSize,
    String? accentColorId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HeadMemoBook(
      id: id ?? this.id,
      name: name ?? this.name,
      pages: pages ?? this.pages,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
      accentColorId: accentColorId ?? this.accentColorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'pages': pages.map((e) => e.toJson()).toList(),
      'headerFontSize': headerFontSize,
      'bodyFontSize': bodyFontSize,
      'accentColorId': accentColorId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory HeadMemoBook.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawPages = json['pages'];
    final pages = rawPages is List
        ? rawPages
            .whereType<Map>()
            .map((e) => HeadMemoPage.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <HeadMemoPage>[];
    return HeadMemoBook(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : HeadMemo._newId('book'),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '본사 메모북',
      pages: pages.isEmpty ? <HeadMemoPage>[HeadMemo._newPage()] : pages,
      headerFontSize: HeadMemo._readDouble(json['headerFontSize'], 24),
      bodyFontSize: HeadMemo._readDouble(json['bodyFontSize'], 16),
      accentColorId: ((json['accentColorId'] as String?) ?? 'blue').trim().isEmpty
          ? 'blue'
          : ((json['accentColorId'] as String?) ?? 'blue').trim(),
      createdAt: HeadMemo._parseDate(json['createdAt']) ?? now,
      updatedAt: HeadMemo._parseDate(json['updatedAt']) ?? now,
    );
  }
}

class HeadMemoRecipient {
  const HeadMemoRecipient({
    required this.id,
    required this.email,
    required this.label,
    required this.selected,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String label;
  final bool selected;
  final DateTime createdAt;
  final DateTime updatedAt;

  HeadMemoRecipient copyWith({
    String? id,
    String? email,
    String? label,
    bool? selected,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HeadMemoRecipient(
      id: id ?? this.id,
      email: email ?? this.email,
      label: label ?? this.label,
      selected: selected ?? this.selected,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'label': label,
      'selected': selected,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory HeadMemoRecipient.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final email = ((json['email'] as String?) ?? '').trim();
    return HeadMemoRecipient(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : HeadMemo._newId('to'),
      email: email,
      label: ((json['label'] as String?) ?? HeadMemo._recipientLabel(email))
          .trim(),
      selected: json['selected'] == true,
      createdAt: HeadMemo._parseDate(json['createdAt']) ?? now,
      updatedAt: HeadMemo._parseDate(json['updatedAt']) ?? now,
    );
  }
}


class HeadMemoRemoteBookSummary {
  const HeadMemoRemoteBookSummary({
    required this.id,
    required this.name,
    required this.order,
    required this.pageCount,
    required this.todoCount,
    required this.completedTodoCount,
    required this.characterCount,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int order;
  final int pageCount;
  final int todoCount;
  final int completedTodoCount;
  final int characterCount;
  final DateTime? updatedAt;

  String get displayName => name.trim().isEmpty ? '이름 없는 메모북' : name.trim();

  factory HeadMemoRemoteBookSummary.fromJson(Map<String, dynamic> json, {int fallbackOrder = 0}) {
    final id = ((json['id'] as String?) ?? '').trim();
    final name = ((json['name'] as String?) ?? '').trim();
    return HeadMemoRemoteBookSummary(
      id: id,
      name: name.isEmpty ? '원격 메모북' : name,
      order: HeadMemo._readInt(json['order'], fallbackOrder),
      pageCount: HeadMemo._readInt(json['pageCount'], 0),
      todoCount: HeadMemo._readInt(json['todoCount'], 0),
      completedTodoCount: HeadMemo._readInt(json['completedTodoCount'], 0),
      characterCount: HeadMemo._readInt(json['characterCount'], 0),
      updatedAt: HeadMemo._parseDate(json['updatedAt']) ??
          HeadMemo._parseDate(json['pushedAt']) ??
          HeadMemo._parseDate(json['serverUpdatedAt']),
    );
  }
}

class HeadMemoRemoteSyncResult {
  const HeadMemoRemoteSyncResult({
    required this.documentPath,
    required this.bookCount,
    required this.pageCount,
    required this.todoCount,
    required this.completedTodoCount,
    required this.activeBookName,
    required this.syncedAt,
  });

  final String documentPath;
  final int bookCount;
  final int pageCount;
  final int todoCount;
  final int completedTodoCount;
  final String activeBookName;
  final DateTime syncedAt;
}

class HeadMemo {
  HeadMemo._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(false);
  static final notes = ValueListenableNotifier<List<String>>(<String>[]);
  static final book = ValueListenableNotifier<HeadMemoBook>(_emptyBook());
  static final books = ValueListenableNotifier<List<HeadMemoBook>>(<HeadMemoBook>[]);
  static final activeBookId = ValueNotifier<String?>(null);
  static final recipients =
      ValueListenableNotifier<List<HeadMemoRecipient>>(<HeadMemoRecipient>[]);

  static const _kEnabledKey = 'head_memo_enabled_v1';
  static const _kNotesKey = 'head_memo_notes_v1';
  static const _kBookKey = 'head_memo_book_v2';
  static const _kBooksKey = 'head_memo_books_v3';
  static const _kActiveBookIdKey = 'head_memo_active_book_id_v3';
  static const _kRecipientsKey = 'head_memo_recipients_v2';
  static const _kMigratedKey = 'head_memo_migrated_v2';
  static const _kMigratedV3Key = 'head_memo_migrated_v3';

  static SharedPreferences? _prefs;
  static bool _inited = false;
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;
  static Timer? _saveDebounce;
  static bool _pendingSave = false;
  static int _idCounter = 0;

  static const String _tMemo = 'head_memo';
  static const String _tMemoUi = 'head_memo/ui';
  static const String _tMemoPrefs = 'head_memo/prefs';
  static const String _tMemoEmail = 'head_memo/email';
  static const String _tMemoFirestore = 'head_memo/firestore';
  static const String _tEmailConfig = 'email_config';
  static const String _tGmailSend = 'gmail/send';
  static const String _remoteLibraryCollection = 'head_memo_libraries';
  static const String _remoteLibraryDocument = 'headquarter_default';

  static HeadMemoBook _emptyBook({String? name}) {
    final now = DateTime.now();
    return HeadMemoBook(
      id: _newId('book'),
      name: (name ?? '본사 메모북').trim().isEmpty ? '본사 메모북' : (name ?? '본사 메모북').trim(),
      pages: <HeadMemoPage>[_newPage(now: now)],
      headerFontSize: 24,
      bodyFontSize: 16,
      accentColorId: 'blue',
      createdAt: now,
      updatedAt: now,
    );
  }

  static HeadMemoPage _newPage({DateTime? now, String? header, String? body}) {
    final t = now ?? DateTime.now();
    return HeadMemoPage(
      id: _newId('page'),
      header: header ?? '새 페이지',
      body: body ?? '',
      todos: const <HeadMemoTodo>[],
      createdAt: t,
      updatedAt: t,
    );
  }

  static String _newId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  static double _readDouble(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static String _recipientLabel(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    return email.substring(0, at);
  }

  static Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {}
  }

  static Future<void> _ensureInited() async {
    if (_inited) return;
    await init();
  }

  static Future<void> init() async {
    if (_inited) return;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;
      final loadedBooks = await _loadBooks();
      books.value = loadedBooks.isEmpty ? <HeadMemoBook>[_emptyBook()] : loadedBooks;
      final savedActive = _prefs!.getString(_kActiveBookIdKey);
      final active = _resolveActiveBook(savedActive);
      activeBookId.value = active.id;
      book.value = active;
      recipients.value = await _loadRecipients();
      _syncLegacyNotes();
      await _saveBooks();
      enabled.addListener(() {
        try {
          _prefs?.setBool(_kEnabledKey, enabled.value);
        } catch (e) {
          _logApiError(
            tag: 'HeadMemo.enabled.listener',
            message: 'enabled 토글 저장 실패(SharedPreferences)',
            error: e,
            extra: <String, dynamic>{'enabled': enabled.value},
            tags: const <String>[_tMemo, _tMemoPrefs],
          );
        }
      });
      _inited = true;
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.init',
        message: 'HeadMemo init 실패(SharedPreferences)',
        error: e,
        tags: const <String>[_tMemo, _tMemoPrefs],
      );
      rethrow;
    }
  }

  static Future<List<HeadMemoBook>> _loadBooks() async {
    final rawBooks = _prefs?.getString(_kBooksKey);
    if (rawBooks != null && rawBooks.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBooks);
        if (decoded is List) {
          final parsed = decoded
              .whereType<Map>()
              .map((e) => HeadMemoBook.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (parsed.isNotEmpty) return _sortBooks(parsed);
        }
      } catch (e) {
        await _logApiError(
          tag: 'HeadMemo._loadBooks',
          message: 'v3 메모북 목록 JSON 로드 실패',
          error: e,
          tags: const <String>[_tMemo, _tMemoPrefs],
        );
      }
    }

    final rawBook = _prefs?.getString(_kBookKey);
    if (rawBook != null && rawBook.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBook);
        if (decoded is Map) {
          final migrated = HeadMemoBook.fromJson(Map<String, dynamic>.from(decoded));
          await _prefs?.setBool(_kMigratedV3Key, true);
          return <HeadMemoBook>[migrated];
        }
      } catch (e) {
        await _logApiError(
          tag: 'HeadMemo._loadBooks',
          message: 'v2 단일 메모북 JSON 로드 실패',
          error: e,
          tags: const <String>[_tMemo, _tMemoPrefs],
        );
      }
    }

    final migrated = _prefs?.getBool(_kMigratedKey) ?? false;
    final migratedV3 = _prefs?.getBool(_kMigratedV3Key) ?? false;
    final legacy = _prefs?.getStringList(_kNotesKey) ?? const <String>[];
    if (!migrated && !migratedV3 && legacy.isNotEmpty) {
      final migratedBook = _migrateLegacyNotes(legacy);
      await _prefs?.setBool(_kMigratedKey, true);
      await _prefs?.setBool(_kMigratedV3Key, true);
      return <HeadMemoBook>[migratedBook];
    }

    return <HeadMemoBook>[_emptyBook()];
  }

  static List<HeadMemoBook> _sortBooks(List<HeadMemoBook> value) {
    final sorted = List<HeadMemoBook>.from(value);
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  static HeadMemoBook _resolveActiveBook(String? savedActive) {
    final list = books.value;
    if (list.isEmpty) return _emptyBook();
    if (savedActive != null && savedActive.trim().isNotEmpty) {
      for (final item in list) {
        if (item.id == savedActive) return item;
      }
    }
    final current = activeBookId.value;
    if (current != null && current.trim().isNotEmpty) {
      for (final item in list) {
        if (item.id == current) return item;
      }
    }
    return list.first;
  }

  static HeadMemoBook _migrateLegacyNotes(List<String> legacy) {
    final now = DateTime.now();
    final pages = <HeadMemoPage>[];
    for (final line in legacy) {
      final parsed = _parseLegacyLine(line);
      final stamp = parsed.$1 ?? now;
      final body = parsed.$2.trim();
      if (body.isEmpty) continue;
      pages.add(
        HeadMemoPage(
          id: _newId('page'),
          header: _titleFromBody(body),
          body: body,
          todos: const <HeadMemoTodo>[],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
    }
    return HeadMemoBook(
      id: _newId('book'),
      name: '본사 메모북',
      pages: pages.isEmpty ? <HeadMemoPage>[_newPage(now: now)] : pages,
      headerFontSize: 24,
      bodyFontSize: 16,
      accentColorId: 'blue',
      createdAt: pages.isEmpty ? now : pages.last.createdAt,
      updatedAt: pages.isEmpty ? now : pages.first.updatedAt,
    );
  }

  static (DateTime?, String) _parseLegacyLine(String line) {
    final split = line.indexOf('|');
    if (split < 0) return (null, line.trim());
    final time = line.substring(0, split).trim();
    final body = line.substring(split + 1).trim();
    final parsed = DateTime.tryParse(time.replaceFirst(' ', 'T'));
    return (parsed, body);
  }

  static String _titleFromBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '새 페이지';
    final cut = compact.length > 26 ? compact.substring(0, 26) : compact;
    return cut.replaceAll(RegExp(r'[,.，。]$'), '').trim();
  }

  static Future<List<HeadMemoRecipient>> _loadRecipients() async {
    final raw = _prefs?.getString(_kRecipientsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => HeadMemoRecipient.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => _isValidEmail(e.email))
              .toList();
        }
      } catch (e) {
        await _logApiError(
          tag: 'HeadMemo._loadRecipients',
          message: 'v2 수신자 목록 JSON 로드 실패',
          error: e,
          tags: const <String>[_tMemo, _tMemoPrefs, _tEmailConfig],
        );
      }
    }

    try {
      final cfg = await EmailConfig.load();
      final mails = _parseEmailList(cfg.to);
      final now = DateTime.now();
      final migrated = mails
          .map(
            (email) => HeadMemoRecipient(
              id: _newId('to'),
              email: email,
              label: _recipientLabel(email),
              selected: true,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList();
      if (migrated.isNotEmpty) {
        recipients.value = migrated;
        await _saveRecipients();
      }
      return migrated;
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo._loadRecipients',
        message: 'EmailConfig 기존 수신자 마이그레이션 실패',
        error: e,
        tags: const <String>[_tMemo, _tEmailConfig],
      );
    }

    return const <HeadMemoRecipient>[];
  }

  static List<String> _parseEmailList(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(',')) {
      final email = part.trim().toLowerCase();
      if (_isValidEmail(email) && seen.add(email)) out.add(email);
    }
    return out;
  }

  static bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  static Future<void> _saveBooks() async {
    try {
      final normalized = books.value.isEmpty ? <HeadMemoBook>[book.value] : books.value;
      await _prefs?.setString(
        _kBooksKey,
        jsonEncode(normalized.map((e) => e.toJson()).toList()),
      );
      await _prefs?.setString(_kActiveBookIdKey, book.value.id);
      await _prefs?.setString(_kBookKey, jsonEncode(book.value.toJson()));
      await _prefs?.setBool(_kMigratedV3Key, true);
      _syncLegacyNotes();
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo._saveBooks',
        message: '메모북 목록 저장 실패(SharedPreferences)',
        error: e,
        tags: const <String>[_tMemo, _tMemoPrefs],
      );
    }
  }

  static Future<void> _saveBook() => _saveBooks();

  static void _scheduleSaveBook() {
    _pendingSave = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 320), () {
      _saveDebounce = null;
      unawaited(_flushScheduledSave());
    });
  }

  static Future<void> _flushScheduledSave() async {
    await _saveBooks();
    _pendingSave = false;
  }

  static Future<void> flushPendingSave() async {
    final shouldSave = _pendingSave || _saveDebounce != null;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _pendingSave = false;
    if (shouldSave) {
      await _saveBooks();
    }
  }

  static List<HeadMemoBook> _normalizedBooksForRemote() {
    final current = book.value;
    final list = books.value.isEmpty
        ? <HeadMemoBook>[current]
        : List<HeadMemoBook>.from(books.value);
    final index = list.indexWhere((e) => e.id == current.id);
    if (index < 0) {
      list.insert(0, current);
    } else {
      list[index] = current;
    }
    return _sortBooks(list);
  }

  static int _readInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int _bookTodoCount(HeadMemoBook value) {
    return value.pages.fold<int>(0, (sum, page) => sum + page.todos.length);
  }

  static int _bookCompletedTodoCount(HeadMemoBook value) {
    return value.pages.fold<int>(
      0,
      (sum, page) => sum + page.todos.where((todo) => todo.done).length,
    );
  }

  static int _bookCharacterCount(HeadMemoBook value) {
    return value.pages.fold<int>(
      0,
      (sum, page) => sum + page.header.length + page.body.length,
    );
  }

  static int _pageCharacterCount(HeadMemoPage value) {
    return value.header.length + value.body.length;
  }

  static List<String> _bookPageIds(HeadMemoBook value) {
    return value.pages.map((page) => page.id).toList();
  }

  static Map<String, dynamic> _bookSummaryPayload(HeadMemoBook value, int order) {
    return <String, dynamic>{
      'id': value.id,
      'name': value.name,
      'order': order,
      'pageCount': value.pages.length,
      'todoCount': _bookTodoCount(value),
      'completedTodoCount': _bookCompletedTodoCount(value),
      'characterCount': _bookCharacterCount(value),
      'accentColorId': value.accentColorId,
      'createdAt': value.createdAt.toIso8601String(),
      'updatedAt': value.updatedAt.toIso8601String(),
    };
  }

  static Map<String, dynamic> _bookDocumentPayload({
    required HeadMemoBook value,
    required int order,
    required DateTime now,
    required String? uid,
    required String? email,
  }) {
    return <String, dynamic>{
      'schemaVersion': 2,
      'syncMode': 'bookPageScoped',
      'id': value.id,
      'name': value.name,
      'order': order,
      'pageIds': _bookPageIds(value),
      'headerFontSize': value.headerFontSize,
      'bodyFontSize': value.bodyFontSize,
      'accentColorId': value.accentColorId,
      'createdAt': value.createdAt.toIso8601String(),
      'updatedAt': value.updatedAt.toIso8601String(),
      'pageCount': value.pages.length,
      'todoCount': _bookTodoCount(value),
      'completedTodoCount': _bookCompletedTodoCount(value),
      'characterCount': _bookCharacterCount(value),
      'pushedAt': now.toIso8601String(),
      'pushedByUid': uid,
      'pushedByEmail': email,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Map<String, dynamic> _pageDocumentPayload({
    required HeadMemoBook parentBook,
    required HeadMemoPage value,
    required int order,
    required DateTime now,
  }) {
    final payload = Map<String, dynamic>.from(value.toJson());
    payload['schemaVersion'] = 2;
    payload['bookId'] = parentBook.id;
    payload['order'] = order;
    payload['characterCount'] = _pageCharacterCount(value);
    payload['pushedAt'] = now.toIso8601String();
    payload['serverUpdatedAt'] = FieldValue.serverTimestamp();
    return payload;
  }

  static DocumentReference<Map<String, dynamic>> get _remoteRootRef {
    return FirebaseFirestore.instance
        .collection(_remoteLibraryCollection)
        .doc(_remoteLibraryDocument);
  }

  static DocumentReference<Map<String, dynamic>> get _remoteMetaRef {
    return _remoteRootRef.collection('meta').doc('main');
  }

  static CollectionReference<Map<String, dynamic>> get _remoteBooksRef {
    return _remoteRootRef.collection('books');
  }

  static DocumentReference<Map<String, dynamic>> _remoteBookRef(String bookId) {
    return _remoteBooksRef.doc(bookId);
  }

  static CollectionReference<Map<String, dynamic>> _remotePagesRef(String bookId) {
    return _remoteBookRef(bookId).collection('pages');
  }

  static String _remoteBookPath(String bookId) {
    return '$_remoteLibraryCollection/$_remoteLibraryDocument/books/$bookId';
  }

  static String get remoteLibraryPath => _remoteBookPath(book.value.id);

  static Future<List<HeadMemoRemoteBookSummary>> fetchRemoteBookIndex() async {
    await _ensureInited();
    try {
      final metaSnapshot = await _remoteMetaRef.get();
      final metaData = metaSnapshot.data();
      final rawIndex = metaData?['bookIndex'];
      final summaries = <HeadMemoRemoteBookSummary>[];
      if (rawIndex is List) {
        for (var i = 0; i < rawIndex.length; i += 1) {
          final item = rawIndex[i];
          if (item is! Map) continue;
          final summary = HeadMemoRemoteBookSummary.fromJson(
            Map<String, dynamic>.from(item),
            fallbackOrder: i,
          );
          if (summary.id.isNotEmpty) summaries.add(summary);
        }
      }
      if (summaries.isEmpty) {
        final bookSnapshot = await _remoteBooksRef.get();
        for (var i = 0; i < bookSnapshot.docs.length; i += 1) {
          final doc = bookSnapshot.docs[i];
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = ((data['id'] as String?) ?? '').trim().isNotEmpty ? data['id'] : doc.id;
          final summary = HeadMemoRemoteBookSummary.fromJson(data, fallbackOrder: i);
          if (summary.id.isNotEmpty) summaries.add(summary);
        }
      }
      summaries.sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.displayName.compareTo(b.displayName);
      });
      return summaries;
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.fetchRemoteBookIndex',
        message: '본사 메모북 Firestore 원격 책 목록 조회 실패',
        error: e,
        extra: <String, dynamic>{
          'documentPath': '$_remoteLibraryCollection/$_remoteLibraryDocument/meta/main',
        },
        tags: const <String>[_tMemo, _tMemoFirestore],
      );
      rethrow;
    }
  }

  static Future<HeadMemoRemoteSyncResult> pullRemoteBookFromFirestore(String remoteBookId) async {
    await _ensureInited();
    final selectedBookId = remoteBookId.trim();
    if (selectedBookId.isEmpty) throw StateError('remote_book_id_empty');
    try {
      final metaSnapshot = await _remoteMetaRef.get();
      final metaData = metaSnapshot.data();
      final selectedBookSnapshot = await _remoteBookRef(selectedBookId).get();
      if (!selectedBookSnapshot.exists) {
        throw StateError('remote_head_memo_book_not_found');
      }
      final bookData = Map<String, dynamic>.from(selectedBookSnapshot.data() ?? <String, dynamic>{});
      bookData['id'] = (bookData['id'] as String?)?.trim().isNotEmpty == true ? bookData['id'] : selectedBookId;
      final rawPageIds = bookData['pageIds'];
      final pageIds = rawPageIds is List
          ? rawPageIds.whereType<String>().where((id) => id.trim().isNotEmpty).toList()
          : <String>[];
      final pageSnapshot = await _remotePagesRef(selectedBookId).orderBy('order').get();
      final entries = <MapEntry<HeadMemoPage, int>>[];
      for (var i = 0; i < pageSnapshot.docs.length; i += 1) {
        final doc = pageSnapshot.docs[i];
        if (pageIds.isNotEmpty && !pageIds.contains(doc.id)) continue;
        final pageData = Map<String, dynamic>.from(doc.data());
        pageData['id'] = (pageData['id'] as String?)?.trim().isNotEmpty == true ? pageData['id'] : doc.id;
        entries.add(
          MapEntry<HeadMemoPage, int>(
            HeadMemoPage.fromJson(pageData),
            _readInt(pageData['order'], i),
          ),
        );
      }
      entries.sort((a, b) => a.value.compareTo(b.value));
      final remotePages = entries.map((entry) => entry.key).toList();
      if (remotePages.isEmpty) {
        final rawLegacyPages = bookData['pages'];
        if (rawLegacyPages is List) {
          remotePages.addAll(
            rawLegacyPages
                .whereType<Map>()
                .map((item) => HeadMemoPage.fromJson(Map<String, dynamic>.from(item))),
          );
        }
      }
      final remoteBook = HeadMemoBook.fromJson(
        <String, dynamic>{
          ...bookData,
          'pages': remotePages.map((item) => item.toJson()).toList(),
        },
      );
      final list = List<HeadMemoBook>.from(books.value);
      final index = list.indexWhere((item) => item.id == remoteBook.id);
      if (index < 0) {
        list.add(remoteBook);
      } else {
        list[index] = remoteBook;
      }
      books.value = _sortBooks(list);
      activeBookId.value = remoteBook.id;
      book.value = remoteBook;
      final rawRecipients = metaData?['recipients'];
      if (rawRecipients is List) {
        recipients.value = rawRecipients
            .whereType<Map>()
            .map((item) => HeadMemoRecipient.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => _isValidEmail(item.email))
            .toList();
      }
      _syncLegacyNotes();
      await _saveBooks();
      await _saveRecipients();
      final syncedAt = _parseDate(bookData['pushedAt']) ??
          _parseDate(bookData['serverUpdatedAt']) ??
          DateTime.now();
      return HeadMemoRemoteSyncResult(
        documentPath: _remoteBookPath(remoteBook.id),
        bookCount: 1,
        pageCount: remoteBook.pages.length,
        todoCount: _bookTodoCount(remoteBook),
        completedTodoCount: _bookCompletedTodoCount(remoteBook),
        activeBookName: remoteBook.name,
        syncedAt: syncedAt,
      );
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.pullRemoteBookFromFirestore',
        message: '본사 메모북 Firestore 선택 원격 메모북 내려받기 실패',
        error: e,
        extra: <String, dynamic>{
          'documentPath': _remoteBookPath(selectedBookId),
          'bookId': selectedBookId,
        },
        tags: const <String>[_tMemo, _tMemoFirestore],
      );
      rethrow;
    }
  }

  static Future<HeadMemoRemoteSyncResult> pushLibraryToFirestore() async {
    await _ensureInited();
    final user = FirebaseAuth.instance.currentUser;
    final googleUser = GoogleAuthSession.instance.currentUser;
    final currentBook = book.value;
    final remoteBooks = _normalizedBooksForRemote();
    final currentBookIndex = remoteBooks.indexWhere((item) => item.id == currentBook.id);
    final order = currentBookIndex < 0 ? 0 : currentBookIndex;
    final pageCount = currentBook.pages.length;
    final todoCount = _bookTodoCount(currentBook);
    final completedTodoCount = _bookCompletedTodoCount(currentBook);
    final now = DateTime.now();
    final uid = user?.uid;
    final email = user?.email ?? googleUser?.email;
    var batch = FirebaseFirestore.instance.batch();
    var writeCount = 0;

    Future<void> commitBatchIfNeeded({bool force = false}) async {
      if (writeCount == 0) return;
      if (!force && writeCount < 450) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      writeCount = 0;
    }

    void setBatch(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> payload,
    ) {
      batch.set(ref, payload, SetOptions(merge: true));
      writeCount += 1;
    }

    final rootPayload = <String, dynamic>{
      'schemaVersion': 2,
      'syncMode': 'bookPageScoped',
      'activeBookId': currentBook.id,
      'updatedAt': now.toIso8601String(),
      'serverUpdatedAt': FieldValue.serverTimestamp(),
      'books': FieldValue.delete(),
      'bookId': FieldValue.delete(),
      'bookName': FieldValue.delete(),
      'pageCount': FieldValue.delete(),
      'todoCount': FieldValue.delete(),
      'completedTodoCount': FieldValue.delete(),
    };
    final metaPayload = <String, dynamic>{
      'schemaVersion': 2,
      'syncMode': 'bookPageScoped',
      'activeBookId': currentBook.id,
      'bookIndex': remoteBooks
          .asMap()
          .entries
          .map((entry) => _bookSummaryPayload(entry.value, entry.key))
          .toList(),
      'recipients': recipients.value.map((item) => item.toJson()).toList(),
      'bookCount': remoteBooks.length,
      'updatedAt': now.toIso8601String(),
      'pushedAt': now.toIso8601String(),
      'pushedByUid': uid,
      'pushedByEmail': email,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    };

    try {
      setBatch(_remoteRootRef, rootPayload);
      setBatch(_remoteMetaRef, metaPayload);
      setBatch(
        _remoteBookRef(currentBook.id),
        _bookDocumentPayload(
          value: currentBook,
          order: order,
          now: now,
          uid: uid,
          email: email,
        ),
      );
      for (var i = 0; i < currentBook.pages.length; i += 1) {
        final page = currentBook.pages[i];
        setBatch(
          _remotePagesRef(currentBook.id).doc(page.id),
          _pageDocumentPayload(
            parentBook: currentBook,
            value: page,
            order: i,
            now: now,
          ),
        );
        await commitBatchIfNeeded();
      }
      await commitBatchIfNeeded(force: true);
      return HeadMemoRemoteSyncResult(
        documentPath: _remoteBookPath(currentBook.id),
        bookCount: 1,
        pageCount: pageCount,
        todoCount: todoCount,
        completedTodoCount: completedTodoCount,
        activeBookName: currentBook.name,
        syncedAt: now,
      );
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.pushLibraryToFirestore',
        message: '본사 메모북 Firestore 현재 메모북 업로드 실패',
        error: e,
        extra: <String, dynamic>{
          'documentPath': _remoteBookPath(currentBook.id),
          'bookId': currentBook.id,
          'bookName': currentBook.name,
          'pageCount': pageCount,
          'todoCount': todoCount,
          'uid': uid,
          'email': email,
        },
        tags: const <String>[_tMemo, _tMemoFirestore],
      );
      rethrow;
    }
  }

  static Future<HeadMemoRemoteSyncResult> pullLibraryFromFirestore() async {
    await _ensureInited();

    try {
      final localBookId = (activeBookId.value ?? book.value.id).trim();
      final metaSnapshot = await _remoteMetaRef.get();
      final metaData = metaSnapshot.data();
      final metaActiveBookId = (metaData?['activeBookId'] as String?)?.trim();
      final preferredBookIds = <String>[
        if (localBookId.isNotEmpty) localBookId,
        if (metaActiveBookId != null && metaActiveBookId.isNotEmpty && metaActiveBookId != localBookId)
          metaActiveBookId,
      ];

      DocumentSnapshot<Map<String, dynamic>>? selectedBookSnapshot;
      var selectedBookId = '';
      for (final candidate in preferredBookIds) {
        final snapshot = await _remoteBookRef(candidate).get();
        if (snapshot.exists) {
          selectedBookSnapshot = snapshot;
          selectedBookId = candidate;
          break;
        }
      }

      if (selectedBookSnapshot == null || !selectedBookSnapshot.exists) {
        final legacySnapshot = await _remoteRootRef.get();
        final legacyData = legacySnapshot.data();
        if (legacyData != null && legacyData['books'] is List) {
          return _pullLegacyLibraryFromFirestore(legacyData);
        }
        throw StateError('remote_head_memo_book_not_found');
      }

      final bookData = Map<String, dynamic>.from(selectedBookSnapshot.data() ?? <String, dynamic>{});
      bookData['id'] = (bookData['id'] as String?)?.trim().isNotEmpty == true
          ? bookData['id']
          : selectedBookId;
      final rawPageIds = bookData['pageIds'];
      final pageIds = rawPageIds is List
          ? rawPageIds.whereType<String>().where((id) => id.trim().isNotEmpty).toList()
          : <String>[];
      final pageSnapshot = await _remotePagesRef(selectedBookId).orderBy('order').get();
      final entries = <MapEntry<HeadMemoPage, int>>[];
      for (var i = 0; i < pageSnapshot.docs.length; i += 1) {
        final doc = pageSnapshot.docs[i];
        if (pageIds.isNotEmpty && !pageIds.contains(doc.id)) continue;
        final pageData = Map<String, dynamic>.from(doc.data());
        pageData['id'] = (pageData['id'] as String?)?.trim().isNotEmpty == true
            ? pageData['id']
            : doc.id;
        entries.add(
          MapEntry<HeadMemoPage, int>(
            HeadMemoPage.fromJson(pageData),
            _readInt(pageData['order'], i),
          ),
        );
      }
      entries.sort((a, b) => a.value.compareTo(b.value));
      final remotePages = entries.map((entry) => entry.key).toList();
      if (remotePages.isEmpty) {
        final rawLegacyPages = bookData['pages'];
        if (rawLegacyPages is List) {
          remotePages.addAll(
            rawLegacyPages
                .whereType<Map>()
                .map((item) => HeadMemoPage.fromJson(Map<String, dynamic>.from(item))),
          );
        }
      }
      final remoteBook = HeadMemoBook.fromJson(
        <String, dynamic>{
          ...bookData,
          'pages': remotePages.map((item) => item.toJson()).toList(),
        },
      );
      final list = List<HeadMemoBook>.from(books.value);
      final index = list.indexWhere((item) => item.id == remoteBook.id);
      if (index < 0) {
        list.add(remoteBook);
      } else {
        list[index] = remoteBook;
      }
      books.value = _sortBooks(list);
      activeBookId.value = remoteBook.id;
      book.value = remoteBook;
      final rawRecipients = metaData?['recipients'];
      if (rawRecipients is List) {
        recipients.value = rawRecipients
            .whereType<Map>()
            .map((item) => HeadMemoRecipient.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => _isValidEmail(item.email))
            .toList();
      }
      _syncLegacyNotes();
      await _saveBooks();
      await _saveRecipients();
      final syncedAt = _parseDate(bookData['pushedAt']) ??
          _parseDate(bookData['serverUpdatedAt']) ??
          DateTime.now();
      return HeadMemoRemoteSyncResult(
        documentPath: _remoteBookPath(remoteBook.id),
        bookCount: 1,
        pageCount: remoteBook.pages.length,
        todoCount: _bookTodoCount(remoteBook),
        completedTodoCount: _bookCompletedTodoCount(remoteBook),
        activeBookName: remoteBook.name,
        syncedAt: syncedAt,
      );
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo.pullLibraryFromFirestore',
        message: '본사 메모북 Firestore 현재 메모북 내려받기 실패',
        error: e,
        extra: <String, dynamic>{
          'documentPath': remoteLibraryPath,
          'activeBookId': activeBookId.value,
        },
        tags: const <String>[_tMemo, _tMemoFirestore],
      );
      rethrow;
    }
  }

  static Future<HeadMemoRemoteSyncResult> _pullLegacyLibraryFromFirestore(
    Map<String, dynamic> data,
  ) async {
    final rawBooks = data['books'];
    final parsedBooks = rawBooks is List
        ? rawBooks
            .whereType<Map>()
            .map((item) => HeadMemoBook.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <HeadMemoBook>[];
    if (parsedBooks.isEmpty) {
      throw StateError('remote_head_memo_books_empty');
    }

    final sortedBooks = _sortBooks(parsedBooks);
    final remoteActiveId = (data['activeBookId'] as String?)?.trim();
    final selected = sortedBooks.firstWhere(
      (item) => item.id == remoteActiveId,
      orElse: () => sortedBooks.first,
    );

    final rawRecipients = data['recipients'];
    final parsedRecipients = rawRecipients is List
        ? rawRecipients
            .whereType<Map>()
            .map((item) => HeadMemoRecipient.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => _isValidEmail(item.email))
            .toList()
        : <HeadMemoRecipient>[];

    books.value = sortedBooks;
    activeBookId.value = selected.id;
    book.value = selected;
    recipients.value = parsedRecipients;
    _syncLegacyNotes();
    await _saveBooks();
    await _saveRecipients();

    final syncedAt = _parseDate(data['pushedAt']) ??
        _parseDate(data['serverUpdatedAt']) ??
        DateTime.now();
    return HeadMemoRemoteSyncResult(
      documentPath: '$_remoteLibraryCollection/$_remoteLibraryDocument',
      bookCount: sortedBooks.length,
      pageCount: sortedBooks.fold<int>(0, (sum, item) => sum + item.pages.length),
      todoCount: sortedBooks.fold<int>(0, (sum, item) => sum + _bookTodoCount(item)),
      completedTodoCount: sortedBooks.fold<int>(0, (sum, item) => sum + _bookCompletedTodoCount(item)),
      activeBookName: selected.name,
      syncedAt: syncedAt,
    );
  }

  static void _replaceActiveBook(HeadMemoBook updated, {bool sort = true}) {
    final list = List<HeadMemoBook>.from(books.value);
    final index = list.indexWhere((e) => e.id == updated.id);
    if (index < 0) {
      list.add(updated);
    } else {
      list[index] = updated;
    }
    books.value = sort ? _sortBooks(list) : list;
    activeBookId.value = updated.id;
    book.value = updated;
    _syncLegacyNotes();
  }

  static Future<void> _saveRecipients() async {
    try {
      await _prefs?.setString(
        _kRecipientsKey,
        jsonEncode(recipients.value.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      await _logApiError(
        tag: 'HeadMemo._saveRecipients',
        message: '수신자 목록 저장 실패(SharedPreferences)',
        error: e,
        tags: const <String>[_tMemo, _tMemoPrefs, _tEmailConfig],
      );
    }
  }

  static void _syncLegacyNotes() {
    notes.value = book.value.pages.map((p) {
      return '${_fmtDateTime(p.updatedAt)} | ${p.header.trim().isEmpty ? p.body : p.header}';
    }).toList();
  }

  static Future<void> selectBook(String id) async {
    await _ensureInited();
    final list = books.value;
    final index = list.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final selected = list[index];
    activeBookId.value = selected.id;
    book.value = selected;
    _syncLegacyNotes();
    await _saveBooks();
  }

  static Future<HeadMemoBook> createBook({String? name}) async {
    await _ensureInited();
    final nextName = (name ?? '').trim().isEmpty ? '새 메모북 ${books.value.length + 1}' : name!.trim();
    final created = _emptyBook(name: nextName);
    books.value = _sortBooks(<HeadMemoBook>[created, ...books.value]);
    activeBookId.value = created.id;
    book.value = created;
    _syncLegacyNotes();
    await _saveBooks();
    return created;
  }

  static Future<HeadMemoBook?> duplicateBook(String id) async {
    await _ensureInited();
    final sourceIndex = books.value.indexWhere((e) => e.id == id);
    if (sourceIndex < 0) return null;
    final source = books.value[sourceIndex];
    final now = DateTime.now();
    final copiedPages = source.pages
        .map(
          (page) => page.copyWith(
            id: _newId('page'),
            todos: page.todos
                .map(
                  (todo) => todo.copyWith(
                    id: _newId('todo'),
                    createdAt: now,
                    updatedAt: now,
                  ),
                )
                .toList(),
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();
    final copied = source.copyWith(
      id: _newId('book'),
      name: '${source.name} 복사본',
      pages: copiedPages,
      createdAt: now,
      updatedAt: now,
    );
    books.value = _sortBooks(<HeadMemoBook>[copied, ...books.value]);
    activeBookId.value = copied.id;
    book.value = copied;
    _syncLegacyNotes();
    await _saveBooks();
    return copied;
  }

  static Future<HeadMemoBook?> deleteBook(String id) async {
    await _ensureInited();
    final list = List<HeadMemoBook>.from(books.value);
    if (list.length <= 1) return null;
    final index = list.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final removed = list.removeAt(index);
    books.value = _sortBooks(list);
    final needsNewActive = activeBookId.value == removed.id || book.value.id == removed.id;
    if (needsNewActive) {
      final safeIndex = index.clamp(0, books.value.length - 1).toInt();
      final selected = books.value[safeIndex];
      activeBookId.value = selected.id;
      book.value = selected;
    }
    _syncLegacyNotes();
    await _saveBooks();
    return removed;
  }

  static Future<void> restoreBook(HeadMemoBook restored, int index) async {
    await _ensureInited();
    final list = List<HeadMemoBook>.from(books.value);
    if (list.any((e) => e.id == restored.id)) return;
    final safeIndex = index.clamp(0, list.length).toInt();
    list.insert(safeIndex, restored);
    books.value = list;
    activeBookId.value = restored.id;
    book.value = restored;
    _syncLegacyNotes();
    await _saveBooks();
  }

  static Future<void> updateBookName(String value) async {
    await _ensureInited();
    final name = value.trim().isEmpty ? '본사 메모북' : value.trim();
    final now = DateTime.now();
    _replaceActiveBook(book.value.copyWith(name: name, updatedAt: now));
    _scheduleSaveBook();
  }

  static Future<void> updateFontSizes({
    required double headerFontSize,
    required double bodyFontSize,
  }) async {
    await _ensureInited();
    final now = DateTime.now();
    _replaceActiveBook(
      book.value.copyWith(
        headerFontSize: headerFontSize.clamp(18, 38).toDouble(),
        bodyFontSize: bodyFontSize.clamp(12, 24).toDouble(),
        updatedAt: now,
      ),
    );
    _scheduleSaveBook();
  }

  static Future<void> updateBookAccentColor(String colorId) async {
    await _ensureInited();
    final normalized = colorId.trim().isEmpty ? 'blue' : colorId.trim();
    final now = DateTime.now();
    _replaceActiveBook(
      book.value.copyWith(
        accentColorId: normalized,
        updatedAt: now,
      ),
    );
    await _saveBook();
  }

  static Future<void> updatePage(
    String pageId, {
    String? header,
    String? body,
  }) async {
    await _ensureInited();
    final now = DateTime.now();
    final pages = book.value.pages.map((page) {
      if (page.id != pageId) return page;
      return page.copyWith(
        header: header ?? page.header,
        body: body ?? page.body,
        updatedAt: now,
      );
    }).toList();
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    _scheduleSaveBook();
  }

  static Future<void> addPage({String? header, String? body}) async {
    await _ensureInited();
    final now = DateTime.now();
    final pages = List<HeadMemoPage>.from(book.value.pages)
      ..add(_newPage(now: now, header: header, body: body));
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
  }

  static Future<void> insertPageAfter(String pageId) async {
    await _ensureInited();
    final now = DateTime.now();
    final pages = List<HeadMemoPage>.from(book.value.pages);
    final index = pages.indexWhere((e) => e.id == pageId);
    final insertIndex = index < 0 ? pages.length : index + 1;
    pages.insert(insertIndex, _newPage(now: now));
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
  }

  static Future<void> duplicatePage(String pageId) async {
    await _ensureInited();
    final now = DateTime.now();
    final pages = List<HeadMemoPage>.from(book.value.pages);
    final index = pages.indexWhere((e) => e.id == pageId);
    if (index < 0) return;
    final src = pages[index];
    pages.insert(
      index + 1,
      src.copyWith(
        id: _newId('page'),
        header: '${src.header.trim().isEmpty ? '페이지' : src.header} 복사본',
        todos: src.todos
            .map(
              (todo) => todo.copyWith(
                id: _newId('todo'),
                createdAt: now,
                updatedAt: now,
              ),
            )
            .toList(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
  }

  static Future<HeadMemoPage?> deletePage(String pageId) async {
    await _ensureInited();
    final pages = List<HeadMemoPage>.from(book.value.pages);
    if (pages.length <= 1) return null;
    final index = pages.indexWhere((e) => e.id == pageId);
    if (index < 0) return null;
    final removed = pages.removeAt(index);
    final now = DateTime.now();
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
    return removed;
  }

  static Future<void> restorePage(HeadMemoPage page, int index) async {
    await _ensureInited();
    final pages = List<HeadMemoPage>.from(book.value.pages);
    final safeIndex = index.clamp(0, pages.length).toInt();
    pages.insert(safeIndex, page);
    final now = DateTime.now();
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
  }

  static Future<void> addTodo(String pageId, String text) async {
    await _ensureInited();
    final value = text.trim();
    if (value.isEmpty) return;
    final now = DateTime.now();
    final pages = book.value.pages.map((page) {
      if (page.id != pageId) return page;
      final todos = List<HeadMemoTodo>.from(page.todos)
        ..add(
          HeadMemoTodo(
            id: _newId('todo'),
            text: value,
            done: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      return page.copyWith(todos: todos, updatedAt: now);
    }).toList();
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
  }

  static Future<void> updateTodo(
    String pageId,
    String todoId, {
    String? text,
    bool? done,
  }) async {
    await _ensureInited();
    final now = DateTime.now();
    final pages = book.value.pages.map((page) {
      if (page.id != pageId) return page;
      final todos = page.todos.map((todo) {
        if (todo.id != todoId) return todo;
        return todo.copyWith(
          text: text ?? todo.text,
          done: done ?? todo.done,
          updatedAt: now,
        );
      }).toList();
      return page.copyWith(todos: todos, updatedAt: now);
    }).toList();
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    if (text != null && done == null) {
      _scheduleSaveBook();
    } else {
      await _saveBook();
    }
  }

  static Future<void> deleteTodo(String pageId, String todoId) async {
    await _ensureInited();
    final now = DateTime.now();
    final pages = book.value.pages.map((page) {
      if (page.id != pageId) return page;
      final todos = List<HeadMemoTodo>.from(page.todos)
        ..removeWhere((e) => e.id == todoId);
      return page.copyWith(todos: todos, updatedAt: now);
    }).toList();
    _replaceActiveBook(book.value.copyWith(pages: pages, updatedAt: now));
    await _saveBook();
  }

  static Future<void> addRecipient(String email) async {
    await _ensureInited();
    final normalized = email.trim().toLowerCase();
    if (!_isValidEmail(normalized)) return;
    final current = List<HeadMemoRecipient>.from(recipients.value);
    if (current.any((e) => e.email.toLowerCase() == normalized)) return;
    final now = DateTime.now();
    current.add(
      HeadMemoRecipient(
        id: _newId('to'),
        email: normalized,
        label: _recipientLabel(normalized),
        selected: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    recipients.value = current;
    await _saveRecipients();
  }

  static Future<void> updateRecipientSelected(String id, bool selected) async {
    await _ensureInited();
    final now = DateTime.now();
    recipients.value = recipients.value
        .map((e) => e.id == id ? e.copyWith(selected: selected, updatedAt: now) : e)
        .toList();
    await _saveRecipients();
  }

  static Future<void> selectAllRecipients(bool selected) async {
    await _ensureInited();
    final now = DateTime.now();
    recipients.value = recipients.value
        .map((e) => e.copyWith(selected: selected, updatedAt: now))
        .toList();
    await _saveRecipients();
  }

  static Future<void> deleteRecipient(String id) async {
    await _ensureInited();
    recipients.value = List<HeadMemoRecipient>.from(recipients.value)
      ..removeWhere((e) => e.id == id);
    await _saveRecipients();
  }

  static List<HeadMemoRecipient> selectedRecipients() {
    return recipients.value
        .where((e) => e.selected && _isValidEmail(e.email))
        .toList();
  }

  static Future<void> openPanel({
    BuildContext? context,
    bool useCommonUi = false,
  }) {
    return togglePanel(
      context: context,
      useCommonUi: useCommonUi,
    );
  }

  static Future<void> togglePanel({
    BuildContext? context,
    bool useCommonUi = false,
  }) async {
    await _ensureInited();
    final ctx = context ?? _bestContext();
    if (ctx == null) {
      await _logApiError(
        tag: 'HeadMemo.togglePanel',
        message: 'Navigator context를 가져오지 못해 panel 토글을 지연',
        error: Exception('no_context'),
        tags: const <String>[_tMemo, _tMemoUi],
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => togglePanel(
          context: context,
          useCommonUi: useCommonUi,
        ),
      );
      return;
    }
    if (_isPanelOpen) {
      await flushPendingSave();
      if (ctx.mounted) {
        Navigator.of(ctx).maybePop();
      }
      return;
    }
    if (_panelFuture != null) return;
    _isPanelOpen = true;
    final future = showCommonLeftSideDock<void>(
      context: ctx,
      barrierLabel: '본사 메모',
      maxWidth: 520,
      widthFactor: .96,
      barrierDismissible: false,
      builder: (_) => const _HeadMemoSideDock(),
    );
    _panelFuture = future.whenComplete(() async {
      await flushPendingSave();
      _isPanelOpen = false;
      _panelFuture = null;
    });
    await _panelFuture;
  }

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static Future<void> add(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await addPage(header: _titleFromBody(value), body: value);
  }

  static Future<void> removeAt(int index) async {
    await _ensureInited();
    if (index < 0 || index >= book.value.pages.length) return;
    await deletePage(book.value.pages[index].id);
  }

  static Future<void> removeLine(String line) async {
    await _ensureInited();
    final index = notes.value.indexOf(line);
    if (index < 0 || index >= book.value.pages.length) return;
    await deletePage(book.value.pages[index].id);
  }

  static String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class ValueListenableNotifier<T> extends ValueNotifier<T> {
  ValueListenableNotifier(super.value);

  @override
  set value(T newValue) {
    super.value = newValue;
  }
}
