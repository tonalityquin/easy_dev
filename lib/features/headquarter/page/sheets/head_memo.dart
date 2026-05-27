import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/auth/google_auth_session.dart';
import '../../../../app/config/email_config.dart';
import '../../../../app/init/app_navigator.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../dev/debug/debug_api_logger.dart';

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
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<HeadMemoPage> pages;
  final double headerFontSize;
  final double bodyFontSize;
  final DateTime createdAt;
  final DateTime updatedAt;

  HeadMemoBook copyWith({
    String? id,
    String? name,
    List<HeadMemoPage>? pages,
    double? headerFontSize,
    double? bodyFontSize,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HeadMemoBook(
      id: id ?? this.id,
      name: name ?? this.name,
      pages: pages ?? this.pages,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
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
  static int _idCounter = 0;

  static const String _tMemo = 'head_memo';
  static const String _tMemoUi = 'head_memo/ui';
  static const String _tMemoPrefs = 'head_memo/prefs';
  static const String _tMemoEmail = 'head_memo/email';
  static const String _tEmailConfig = 'email_config';
  static const String _tGmailSend = 'gmail/send';

  static HeadMemoBook _emptyBook({String? name}) {
    final now = DateTime.now();
    return HeadMemoBook(
      id: _newId('book'),
      name: (name ?? '본사 메모북').trim().isEmpty ? '본사 메모북' : (name ?? '본사 메모북').trim(),
      pages: <HeadMemoPage>[_newPage(now: now)],
      headerFontSize: 24,
      bodyFontSize: 16,
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
    await _saveBook();
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
    await _saveBook();
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
    await _saveBook();
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

  static Future<void> openPanel() => togglePanel();

  static Future<void> togglePanel() async {
    await _ensureInited();
    final ctx = _bestContext();
    if (ctx == null) {
      await _logApiError(
        tag: 'HeadMemo.togglePanel',
        message: 'Navigator context를 가져오지 못해 panel 토글을 지연',
        error: Exception('no_context'),
        tags: const <String>[_tMemo, _tMemoUi],
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }
    if (_isPanelOpen) {
      Navigator.of(ctx).maybePop();
      return;
    }
    if (_panelFuture != null) return;
    _isPanelOpen = true;
    _panelFuture = showModalBottomSheet<void>(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HeadMemoSheet(),
    ).whenComplete(() {
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

class _HeadMemoSheet extends StatefulWidget {
  const _HeadMemoSheet();

  @override
  State<_HeadMemoSheet> createState() => _HeadMemoSheetState();
}

class _HeadMemoSheetState extends State<_HeadMemoSheet> {
  final PageController _pageController = PageController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _recipientCtrl = TextEditingController();
  final TextEditingController _todoCtrl = TextEditingController();

  bool _sending = false;
  bool _preview = false;
  bool _recipientValid = true;
  int _currentPage = 0;
  String _query = '';
  String? _activeBookRenderId;

  static const int _mimeB64LineLength = 76;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = HeadMemo.book.value.name;
    _nameCtrl.addListener(() {
      final value = _nameCtrl.text.trim();
      if (value.isNotEmpty && value != HeadMemo.book.value.name) {
        HeadMemo.updateBookName(value);
      }
    });
    _searchCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim());
    });
    _recipientCtrl.addListener(() {
      final value = _recipientCtrl.text.trim();
      final valid = value.isEmpty || HeadMemo._isValidEmail(value.toLowerCase());
      if (mounted && valid != _recipientValid) {
        setState(() => _recipientValid = valid);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _recipientCtrl.dispose();
    _todoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final heightFactor = bottomInset > 0 ? 0.98 : 0.94;
    final cs = Theme.of(context).colorScheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: ValueListenableBuilder<HeadMemoBook>(
                valueListenable: HeadMemo.book,
                builder: (context, book, _) {
                  if (_activeBookRenderId != book.id) {
                    _activeBookRenderId = book.id;
                    _nameCtrl.text = book.name;
                    _todoCtrl.clear();
                    _query = '';
                    _currentPage = 0;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_searchCtrl.text.isNotEmpty) {
                        _searchCtrl.clear();
                      }
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(0);
                      }
                    });
                  } else if (_nameCtrl.text.trim() != book.name && !_nameCtrl.selection.isValid) {
                    _nameCtrl.text = book.name;
                  }
                  final pageCount = book.pages.length + 2;
                  if (_currentPage >= pageCount) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _currentPage = pageCount - 1);
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(pageCount - 1);
                      }
                    });
                  }
                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      const _DragHandle(),
                      _buildHeader(book),
                      _buildToolbar(book),
                      _buildSearchPanel(book),
                      Expanded(child: _buildPageView(book)),
                      _buildBottomNavigator(book),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(HeadMemoBook book) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.secondaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.menu_book_rounded, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameCtrl,
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '메모 이름',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: TextStyle(color: cs.outline),
                  ),
                ),
                Text(
                  '${book.pages.length}쪽 작성 · ${HeadMemo._fmtDateTime(book.updatedAt)} 저장',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: HeadMemo.enabled,
            builder: (_, on, __) {
              return Switch.adaptive(
                value: on,
                onChanged: (value) {
                  HeadMemo.enabled.value = value;
                  HapticFeedback.selectionClick();
                },
              );
            },
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(HeadMemoBook book) {
    final cs = Theme.of(context).colorScheme;
    final selectedTo = HeadMemo.selectedRecipients().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarButton(
              icon: Icons.library_books_rounded,
              label: '책장 ${HeadMemo.books.value.length}권',
              strong: true,
              onTap: _openBookshelfSheet,
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: _preview ? Icons.edit_note_rounded : Icons.visibility_rounded,
              label: _preview ? '편집' : '미리보기',
              strong: _preview,
              onTap: () => setState(() => _preview = !_preview),
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: Icons.text_fields_rounded,
              label: '글자 크기',
              onTap: () => _openFontDialog(book),
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: Icons.person_add_alt_1_rounded,
              label: '수신자 $selectedTo명',
              onTap: _openRecipientsSheet,
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: _sending ? Icons.hourglass_top_rounded : Icons.attach_email_rounded,
              label: _sending ? '전송 중' : 'PDF+MD 전송',
              color: cs.primaryContainer,
              foreground: cs.onPrimaryContainer,
              onTap: _sending ? null : _sendBookByEmail,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPanel(HeadMemoBook book) {
    final cs = Theme.of(context).colorScheme;
    final matches = _matchedPageIndexes(book);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: _searchCtrl.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              hintText: '페이지 헤더, 본문, 투두 검색',
              filled: true,
              fillColor: cs.surfaceContainerHighest.withOpacity(.55),
              border: _inputBorder(),
              enabledBorder: _inputBorder(),
              focusedBorder: _inputBorder(focused: true, cs: cs),
              isDense: true,
            ),
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MiniPill(
                    icon: Icons.manage_search_rounded,
                    text: matches.isEmpty ? '검색 결과 없음' : '${matches.length}개 페이지 일치',
                    strong: matches.isNotEmpty,
                  ),
                  for (final index in matches.take(4))
                    ActionChip(
                      label: Text('${index + 3}p ${_pageTitle(book.pages[index])}'),
                      onPressed: () => _jumpTo(index + 2),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageView(HeadMemoBook book) {
    final pageCount = book.pages.length + 2;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: PageView.builder(
        controller: _pageController,
        itemCount: pageCount,
        onPageChanged: (index) {
          _todoCtrl.clear();
          setState(() => _currentPage = index);
        },
        itemBuilder: (context, index) {
          if (index == 0) return _buildCoverPage(book);
          if (index == 1) return _buildTocPage(book);
          final page = book.pages[index - 2];
          return _preview ? _buildPreviewContentPage(book, page, index) : _buildEditContentPage(book, page, index);
        },
      ),
    );
  }

  Widget _buildCoverPage(HeadMemoBook book) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Container(
        constraints: const BoxConstraints(minHeight: 460),
        padding: const EdgeInsets.all(28),
        decoration: _pageDecoration(strong: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'HEAD MEMO BOOK',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 34),
            Text(
              book.name,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '첫 페이지는 메모 이름, 다음 페이지는 목차, 이후 페이지는 사용자가 작성한 본문으로 구성됩니다.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 34),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniPill(icon: Icons.article_rounded, text: '${book.pages.length}쪽'),
                _MiniPill(icon: Icons.text_fields_rounded, text: '헤더 ${book.headerFontSize.round()}'),
                _MiniPill(icon: Icons.format_size_rounded, text: '본문 ${book.bodyFontSize.round()}'),
                _MiniPill(icon: Icons.schedule_rounded, text: HeadMemo._fmtDateTime(book.updatedAt)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTocPage(HeadMemoBook book) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Container(
        constraints: const BoxConstraints(minHeight: 460),
        padding: const EdgeInsets.all(22),
        decoration: _pageDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_numbered_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '목차',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < book.pages.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Material(
                  color: cs.surfaceContainerHighest.withOpacity(.55),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _jumpTo(i + 2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${i + 3}',
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _pageTitle(book.pages[i]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${i + 3}p',
                            style: theme.textTheme.labelLarge?.copyWith(color: cs.outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditContentPage(HeadMemoBook book, HeadMemoPage page, int visualIndex) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _pageDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _MiniPill(icon: Icons.article_outlined, text: '$visualIndex / ${book.pages.length + 2}'),
                const SizedBox(width: 8),
                _MiniPill(
                  icon: Icons.check_circle_outline_rounded,
                  text: '${page.completedTodoCount}/${page.todos.length}',
                  strong: page.todos.isNotEmpty,
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: '페이지 복제',
                  onPressed: () async {
                    await HeadMemo.duplicatePage(page.id);
                    _jumpTo(visualIndex + 1);
                  },
                  icon: const Icon(Icons.copy_all_rounded),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: '페이지 삭제',
                  onPressed: book.pages.length <= 1 ? null : () => _deletePage(book, page),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: ValueKey('header_${page.id}'),
              initialValue: page.header,
              textInputAction: TextInputAction.next,
              style: TextStyle(
                fontSize: book.headerFontSize,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.15,
              ),
              decoration: InputDecoration(
                labelText: '페이지 헤더',
                hintText: '목차에 들어갈 헤더를 입력하세요',
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.5),
                border: _inputBorder(radius: 18),
                enabledBorder: _inputBorder(radius: 18),
                focusedBorder: _inputBorder(focused: true, cs: cs, radius: 18),
              ),
              onChanged: (value) => HeadMemo.updatePage(page.id, header: value),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: ValueKey('body_${page.id}'),
              initialValue: page.body,
              minLines: 8,
              maxLines: 22,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: TextStyle(
                fontSize: book.bodyFontSize,
                color: cs.onSurface,
                height: 1.55,
              ),
              decoration: InputDecoration(
                labelText: '본문',
                alignLabelWithHint: true,
                hintText: '책을 집필하듯이 본문을 작성하세요',
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.42),
                border: _inputBorder(radius: 18),
                enabledBorder: _inputBorder(radius: 18),
                focusedBorder: _inputBorder(focused: true, cs: cs, radius: 18),
              ),
              onChanged: (value) => HeadMemo.updatePage(page.id, body: value),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.checklist_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '투두',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final todo in page.todos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TodoTile(
                  key: ValueKey(todo.id),
                  todo: todo,
                  onDone: (value) => HeadMemo.updateTodo(page.id, todo.id, done: value),
                  onText: (value) => HeadMemo.updateTodo(page.id, todo.id, text: value),
                  onDelete: () => HeadMemo.deleteTodo(page.id, todo.id),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _todoCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: '투두 추가',
                      prefixIcon: const Icon(Icons.add_task_rounded),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(.5),
                      border: _inputBorder(radius: 16),
                      enabledBorder: _inputBorder(radius: 16),
                      focusedBorder: _inputBorder(focused: true, cs: cs, radius: 16),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTodo(page.id),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _addTodo(page.id),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('추가'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContentPage(HeadMemoBook book, HeadMemoPage page, int visualIndex) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: _pageDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MiniPill(icon: Icons.visibility_rounded, text: '$visualIndex / ${book.pages.length + 2}', strong: true),
                const Spacer(),
                Text(
                  HeadMemo._fmtDateTime(page.updatedAt),
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.outline),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              _pageTitle(page),
              style: TextStyle(
                fontSize: book.headerFontSize,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              page.body.trim().isEmpty ? '본문이 비어 있습니다.' : page.body.trim(),
              style: TextStyle(
                fontSize: book.bodyFontSize,
                color: page.body.trim().isEmpty ? cs.outline : cs.onSurface,
                height: 1.62,
              ),
            ),
            if (page.todos.isNotEmpty) ...[
              const SizedBox(height: 22),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'Todo',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final todo in page.todos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        todo.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        size: 20,
                        color: todo.done ? cs.primary : cs.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          todo.text,
                          style: TextStyle(
                            color: todo.done ? cs.outline : cs.onSurface,
                            decoration: todo.done ? TextDecoration.lineThrough : TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigator(HeadMemoBook book) {
    final cs = Theme.of(context).colorScheme;
    final total = book.pages.length + 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.75))),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: '이전 페이지',
            onPressed: _currentPage <= 0 ? null : () => _jumpTo(_currentPage - 1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pageLabel(book),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: total <= 1 ? 1 : (_currentPage + 1) / total,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: '다음 페이지',
            onPressed: _currentPage >= total - 1 ? null : () => _jumpTo(_currentPage + 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () async {
              await HeadMemo.addPage();
              _jumpTo(HeadMemo.book.value.pages.length + 1);
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('페이지'),
          ),
        ],
      ),
    );
  }

  BoxDecoration _pageDecoration({bool strong = false}) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: strong ? cs.primaryContainer.withOpacity(.22) : cs.surface,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: cs.outlineVariant.withOpacity(.8)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.05),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  OutlineInputBorder _inputBorder({
    bool focused = false,
    ColorScheme? cs,
    double radius = 14,
    bool valid = true,
  }) {
    final scheme = cs ?? Theme.of(context).colorScheme;
    final color = valid
        ? focused
            ? scheme.primary
            : scheme.outlineVariant
        : scheme.error;
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: focused ? 1.4 : 1),
    );
  }

  void _jumpTo(int page) {
    final total = HeadMemo.book.value.pages.length + 2;
    final target = page.clamp(0, total - 1).toInt();
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) setState(() => _currentPage = target);
  }

  void _addTodo(String pageId) {
    final value = _todoCtrl.text.trim();
    if (value.isEmpty) return;
    HeadMemo.addTodo(pageId, value);
    _todoCtrl.clear();
    HapticFeedback.lightImpact();
  }

  Future<void> _deletePage(HeadMemoBook book, HeadMemoPage page) async {
    final index = book.pages.indexWhere((e) => e.id == page.id);
    final removed = await HeadMemo.deletePage(page.id);
    if (removed == null || !mounted) return;
    HapticFeedback.selectionClick();
    _jumpTo((index + 1).clamp(0, HeadMemo.book.value.pages.length + 1).toInt());
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${_pageTitle(removed)} 페이지를 삭제했습니다.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          persist: false,
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              HeadMemo.restorePage(removed, index);
            },
          ),
        ),
      );
  }

  String _pageTitle(HeadMemoPage page) {
    final header = page.header.trim();
    if (header.isNotEmpty) return header;
    final body = page.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty) return '제목 없는 페이지';
    return body.length > 22 ? body.substring(0, 22) : body;
  }

  String _pageLabel(HeadMemoBook book) {
    if (_currentPage == 0) return '1p 표지';
    if (_currentPage == 1) return '2p 목차';
    final index = _currentPage - 2;
    if (index >= 0 && index < book.pages.length) {
      return '${_currentPage + 1}p ${_pageTitle(book.pages[index])}';
    }
    return '${_currentPage + 1}p';
  }

  List<int> _matchedPageIndexes(HeadMemoBook book) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const <int>[];
    final matches = <int>[];
    for (int i = 0; i < book.pages.length; i++) {
      final page = book.pages[i];
      final source = <String>[
        page.header,
        page.body,
        for (final todo in page.todos) todo.text,
      ].join('\n').toLowerCase();
      if (source.contains(query)) matches.add(i);
    }
    return matches;
  }

  Future<void> _openBookshelfSheet() async {
    final shelfSearchCtrl = TextEditingController();
    String shelfQuery = '';
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: FractionallySizedBox(
              heightFactor: MediaQuery.of(ctx).viewInsets.bottom > 0 ? .92 : .82,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Material(
                  color: Theme.of(ctx).colorScheme.surface,
                  child: SafeArea(
                    top: false,
                    child: StatefulBuilder(
                      builder: (context, setSheetState) {
                        final cs = Theme.of(context).colorScheme;
                        final theme = Theme.of(context);
                        return ValueListenableBuilder<List<HeadMemoBook>>(
                          valueListenable: HeadMemo.books,
                          builder: (context, library, _) {
                            final activeId = HeadMemo.activeBookId.value ?? HeadMemo.book.value.id;
                            final filtered = _filteredBooks(library, shelfQuery);
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _DragHandle(),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(.08),
                                              blurRadius: 14,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: Icon(Icons.library_books_rounded, color: cs.onPrimaryContainer),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '메모북 책장',
                                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                                            ),
                                            Text(
                                              '${library.length}권 보관 · 책등을 눌러 꺼내 편집',
                                              style: theme.textTheme.labelMedium?.copyWith(color: cs.outline),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton.filledTonal(
                                        tooltip: '새 메모북',
                                        onPressed: () => _createBookFromShelf(context),
                                        icon: const Icon(Icons.add_rounded),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        tooltip: '닫기',
                                        onPressed: () => Navigator.of(ctx).pop(),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: shelfSearchCtrl,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.search_rounded),
                                      hintText: '메모북 이름, 헤더, 본문, 투두 검색',
                                      filled: true,
                                      fillColor: cs.surfaceContainerHighest.withOpacity(.55),
                                      border: _inputBorder(),
                                      enabledBorder: _inputBorder(),
                                      focusedBorder: _inputBorder(focused: true, cs: cs),
                                      suffixIcon: shelfQuery.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: '검색어 지우기',
                                              onPressed: () {
                                                shelfSearchCtrl.clear();
                                                setSheetState(() => shelfQuery = '');
                                              },
                                              icon: const Icon(Icons.close_rounded),
                                            ),
                                    ),
                                    onChanged: (value) => setSheetState(() => shelfQuery = value.trim()),
                                  ),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: filtered.isEmpty
                                        ? _BookshelfEmptyState(onCreate: () => _createBookFromShelf(context))
                                        : SingleChildScrollView(
                                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                                                  decoration: BoxDecoration(
                                                    color: cs.surfaceContainerHighest.withOpacity(.38),
                                                    borderRadius: BorderRadius.circular(26),
                                                    border: Border.all(color: cs.outlineVariant.withOpacity(.78)),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Padding(
                                                        padding: const EdgeInsets.only(left: 4, bottom: 10),
                                                        child: Text(
                                                          '책등을 살짝 뽑아 선택하세요',
                                                          style: theme.textTheme.labelLarge?.copyWith(
                                                            color: cs.onSurfaceVariant,
                                                            fontWeight: FontWeight.w900,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 240,
                                                        child: SingleChildScrollView(
                                                          scrollDirection: Axis.horizontal,
                                                          child: Row(
                                                            crossAxisAlignment: CrossAxisAlignment.end,
                                                            children: [
                                                              for (int i = 0; i < filtered.length; i++)
                                                                Padding(
                                                                  padding: const EdgeInsets.only(right: 8),
                                                                  child: _BookshelfBookSpine(
                                                                    book: filtered[i],
                                                                    active: filtered[i].id == activeId,
                                                                    index: i,
                                                                    onOpen: () async {
                                                                      await _selectBookAndClose(filtered[i], ctx);
                                                                    },
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        height: 16,
                                                        decoration: BoxDecoration(
                                                          color: cs.primary.withOpacity(.14),
                                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                                                          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.75))),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                for (int i = 0; i < filtered.length; i++)
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 10),
                                                    child: _BookshelfBookCard(
                                                      book: filtered[i],
                                                      active: filtered[i].id == activeId,
                                                      onOpen: () => _selectBookAndClose(filtered[i], ctx),
                                                      onDuplicate: () => _duplicateBookFromShelf(filtered[i], ctx),
                                                      onDelete: library.length <= 1 ? null : () => _deleteBookFromShelf(filtered[i], i, ctx),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      shelfSearchCtrl.dispose();
    }
  }

  List<HeadMemoBook> _filteredBooks(List<HeadMemoBook> library, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return library;
    return library.where((book) {
      final source = <String>[
        book.name,
        for (final page in book.pages) page.header,
        for (final page in book.pages) page.body,
        for (final page in book.pages)
          for (final todo in page.todos) todo.text,
      ].join('\n').toLowerCase();
      return source.contains(q);
    }).toList();
  }

  Future<void> _createBookFromShelf(BuildContext sheetContext) async {
    final created = await _openCreateBookDialog(sheetContext);
    if (created == null) return;
    await HeadMemo.createBook(name: created);
    if (!mounted) return;
    setState(() {
      _preview = false;
      _currentPage = 0;
      _nameCtrl.text = HeadMemo.book.value.name;
    });
    HapticFeedback.mediumImpact();
  }

  Future<String?> _openCreateBookDialog(BuildContext sheetContext) async {
    final ctrl = TextEditingController();
    try {
      return await showDialog<String>(
        context: sheetContext,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('새 메모북 만들기'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '메모북 이름',
                hintText: '예: 본사 운영 개선안',
              ),
              onSubmitted: (value) {
                final name = value.trim();
                if (name.isNotEmpty) Navigator.of(dialogContext).pop(name);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final name = ctrl.text.trim();
                  if (name.isNotEmpty) Navigator.of(dialogContext).pop(name);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('생성'),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _selectBookAndClose(HeadMemoBook selected, BuildContext sheetContext) async {
    await HeadMemo.selectBook(selected.id);
    if (!mounted) return;
    setState(() {
      _preview = false;
      _currentPage = 0;
      _nameCtrl.text = selected.name;
    });
    HapticFeedback.selectionClick();
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  }

  Future<void> _duplicateBookFromShelf(HeadMemoBook source, BuildContext sheetContext) async {
    final copied = await HeadMemo.duplicateBook(source.id);
    if (copied == null || !mounted) return;
    setState(() {
      _preview = false;
      _currentPage = 0;
      _nameCtrl.text = copied.name;
    });
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${source.name} 복사본을 책장에 꽂았습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteBookFromShelf(HeadMemoBook target, int visualIndex, BuildContext sheetContext) async {
    final originalIndex = HeadMemo.books.value.indexWhere((e) => e.id == target.id);
    final removed = await HeadMemo.deleteBook(target.id);
    if (removed == null || !mounted) return;
    setState(() {
      _preview = false;
      _currentPage = 0;
      _nameCtrl.text = HeadMemo.book.value.name;
    });
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${removed.name} 메모북을 책장에서 뺐습니다.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          persist: false,
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              HeadMemo.restoreBook(
                removed,
                originalIndex < 0 ? visualIndex : originalIndex,
              );
            },
          ),
        ),
      );
  }

  Future<void> _openFontDialog(HeadMemoBook book) async {
    double header = book.headerFontSize;
    double body = book.bodyFontSize;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('글자 크기'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FontSlider(
                    label: '헤더',
                    value: header,
                    min: 18,
                    max: 38,
                    onChanged: (value) => setDialogState(() => header = value),
                  ),
                  const SizedBox(height: 12),
                  _FontSlider(
                    label: '본문',
                    value: body,
                    min: 12,
                    max: 24,
                    onChanged: (value) => setDialogState(() => body = value),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(.55),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('헤더 미리보기', style: TextStyle(fontSize: header, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text('본문 미리보기입니다. 문서와 PDF에 같은 크기가 반영됩니다.', style: TextStyle(fontSize: body, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await HeadMemo.updateFontSizes(headerFontSize: header, bodyFontSize: body);
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('적용'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openRecipientsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: FractionallySizedBox(
            heightFactor: MediaQuery.of(ctx).viewInsets.bottom > 0 ? .86 : .72,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: Material(
                color: Theme.of(ctx).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: ValueListenableBuilder<List<HeadMemoRecipient>>(
                    valueListenable: HeadMemo.recipients,
                    builder: (context, list, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _DragHandle(),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(Icons.alternate_email_rounded, color: Theme.of(ctx).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('수신자 보관함', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _recipientCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      hintText: 'email@example.com',
                                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                                      filled: true,
                                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(.55),
                                      isDense: true,
                                      errorText: _recipientValid ? null : '이메일 형식을 확인하세요',
                                      border: _inputBorder(valid: _recipientValid),
                                      enabledBorder: _inputBorder(valid: _recipientValid),
                                      focusedBorder: _inputBorder(focused: true, valid: _recipientValid, cs: Theme.of(ctx).colorScheme),
                                    ),
                                    onSubmitted: (_) => _addRecipient(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: _recipientValid ? _addRecipient : null,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('추가'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: list.isEmpty ? null : () => HeadMemo.selectAllRecipients(true),
                                  icon: const Icon(Icons.done_all_rounded),
                                  label: const Text('전체 선택'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: list.isEmpty ? null : () => HeadMemo.selectAllRecipients(false),
                                  icon: const Icon(Icons.remove_done_rounded),
                                  label: const Text('선택 해제'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: list.isEmpty
                                  ? const _RecipientEmptyState()
                                  : ListView.separated(
                                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                      itemCount: list.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final recipient = list[index];
                                        return _RecipientTile(
                                          recipient: recipient,
                                          onSelected: (value) => HeadMemo.updateRecipientSelected(recipient.id, value),
                                          onDelete: () => HeadMemo.deleteRecipient(recipient.id),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addRecipient() async {
    final email = _recipientCtrl.text.trim().toLowerCase();
    final valid = HeadMemo._isValidEmail(email);
    if (!valid) {
      setState(() => _recipientValid = false);
      return;
    }
    await HeadMemo.addRecipient(email);
    _recipientCtrl.clear();
    setState(() => _recipientValid = true);
    HapticFeedback.selectionClick();
  }

  Future<void> _sendBookByEmail() async {
    final selected = HeadMemo.selectedRecipients();
    if (selected.isEmpty) {
      await StatusDialog.showFailure(
        context,
        title: '수신자 선택 필요',
        description: '수신자 보관함에서 전송할 이메일을 선택하세요.',
      );
      if (!mounted) return;
      await _openRecipientsSheet();
      return;
    }

    if (GoogleAuthSession.instance.isSessionBlocked) {
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._sendBookByEmail',
        message: '구글 세션 차단(ON) 상태로 이메일 전송 차단됨',
        error: StateError('google_session_blocked'),
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tMemoEmail],
      );
      if (!mounted) return;
      await StatusDialog.showFailure(
        context,
        title: '메일 전송 실패',
        description: '구글 세션이 차단되어 전송할 수 없습니다.',
      );
      return;
    }

    setState(() => _sending = true);
    final book = HeadMemo.book.value;
    final now = DateTime.now();
    final safe = _safeFileName(book.name);
    final tag = _fmtCompact(now);
    final pdfName = '${safe}_$tag.pdf';
    final mdName = '${safe}_$tag.md';

    try {
      final pdfBytes = await _buildPdfBytes(book, now);
      final markdown = _buildMarkdown(book, now);
      final toCsv = selected.map((e) => e.email).join(', ');
      final subject = '${book.name} 메모 문서 (${_fmtYMD(now)})';
      final bodyText = '본사 메모 문서를 첨부합니다.\r\n\r\nPDF는 열람과 공유용 문서이며, Markdown은 재편집과 백업용 원본입니다.';
      final mime = _buildMimeMessage(
        toCsv: toCsv,
        subject: subject,
        bodyText: bodyText,
        pdfName: pdfName,
        pdfBytes: pdfBytes,
        markdownName: mdName,
        markdownText: markdown,
        boundary: 'headmemo_${now.microsecondsSinceEpoch}',
      );
      final raw = base64UrlEncode(utf8.encode(mime)).replaceAll('=', '');
      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;
      await api.users.messages.send(message, 'me');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await StatusDialog.showSuccess(
        context,
        title: '메일 전송 완료',
        description: '${book.name} 메모북을 ${selected.length}명에게 전송했습니다.\n첨부: PDF, Markdown',
      );
    } catch (e) {
      await HeadMemo._logApiError(
        tag: '_HeadMemoSheet._sendBookByEmail',
        message: 'Gmail 메모북 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'pages': book.pages.length,
          'recipients': selected.length,
        },
        tags: const <String>[HeadMemo._tMemo, HeadMemo._tMemoEmail, HeadMemo._tGmailSend],
      );
      if (!mounted) return;
      await StatusDialog.showFailure(
        context,
        title: '메일 전송 실패',
        description: 'PDF와 Markdown 전송에 실패했습니다. 수신자, 구글 세션, 네트워크 상태를 확인하세요.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _buildMimeMessage({
    required String toCsv,
    required String subject,
    required String bodyText,
    required String pdfName,
    required Uint8List pdfBytes,
    required String markdownName,
    required String markdownText,
    required String boundary,
  }) {
    const crlf = '\r\n';
    final pdfB64 = _wrapBase64Lines(base64.encode(pdfBytes));
    final mdB64 = _wrapBase64Lines(base64.encode(utf8.encode(markdownText)));
    final bodyB64 = _wrapBase64Lines(base64.encode(utf8.encode(bodyText)));
    final mime = StringBuffer()
      ..write('MIME-Version: 1.0$crlf')
      ..write('To: $toCsv$crlf')
      ..write('Subject: ${_encodeSubjectRfc2047(subject)}$crlf')
      ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
      ..write(crlf)
      ..write('--$boundary$crlf')
      ..write('Content-Type: text/plain; charset="utf-8"$crlf')
      ..write('Content-Transfer-Encoding: base64$crlf')
      ..write(crlf)
      ..write(bodyB64)
      ..write(crlf)
      ..write('--$boundary$crlf')
      ..write('Content-Type: application/pdf; name="$pdfName"$crlf')
      ..write('Content-Disposition: attachment; filename="$pdfName"$crlf')
      ..write('Content-Transfer-Encoding: base64$crlf')
      ..write(crlf)
      ..write(pdfB64)
      ..write(crlf)
      ..write('--$boundary$crlf')
      ..write('Content-Type: text/markdown; charset="utf-8"; name="$markdownName"$crlf')
      ..write('Content-Disposition: attachment; filename="$markdownName"$crlf')
      ..write('Content-Transfer-Encoding: base64$crlf')
      ..write(crlf)
      ..write(mdB64)
      ..write(crlf)
      ..write('--$boundary--$crlf');
    return mime.toString();
  }

  Future<Uint8List> _buildPdfBytes(HeadMemoBook book, DateTime exportedAt) async {
    pw.Font? regular;
    pw.Font? bold;
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(data);
    } catch (_) {}
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(data);
    } catch (_) {
      bold = regular;
    }

    final theme = regular == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(
            base: regular,
            bold: bold ?? regular,
            italic: regular,
            boldItalic: bold ?? regular,
          );
    final doc = pw.Document();
    const ink = PdfColor.fromInt(0xff111827);
    const muted = PdfColor.fromInt(0xff6b7280);
    const line = PdfColor.fromInt(0xffd1d5db);
    const soft = PdfColor.fromInt(0xfff3f4f6);
    const accent = PdfColor.fromInt(0xff2563eb);
    const accentSoft = PdfColor.fromInt(0xffdbeafe);

    pw.TextStyle titleStyle(double size) => pw.TextStyle(fontSize: size, color: ink, fontWeight: pw.FontWeight.bold);
    pw.TextStyle bodyStyle(double size, {PdfColor color = ink}) => pw.TextStyle(fontSize: size, color: color, height: 1.45);

    pw.Widget footer(pw.Context ctx) {
      return pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line, width: .6))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(book.name, style: bodyStyle(8, color: muted)),
            pw.Text('${HeadMemo._fmtDateTime(exportedAt)} · ${ctx.pageNumber} / ${ctx.pagesCount}', style: bodyStyle(8, color: muted)),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        build: (ctx) {
          return pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(34),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(18),
              border: pw.Border.all(color: line, width: .8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: pw.BoxDecoration(color: accentSoft, borderRadius: pw.BorderRadius.circular(999)),
                  child: pw.Text('HEAD MEMO BOOK', style: pw.TextStyle(fontSize: 10, color: accent, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
                ),
                pw.SizedBox(height: 38),
                pw.Text(book.name, style: titleStyle(34)),
                pw.SizedBox(height: 16),
                pw.Text('표지 · 목차 · 본문 페이지 · 투두 체크리스트를 포함한 본사 메모 문서입니다.', style: bodyStyle(12, color: muted)),
                pw.SizedBox(height: 34),
                pw.Row(
                  children: [
                    _pdfMetric('본문 페이지', '${book.pages.length}', soft, ink, muted),
                    pw.SizedBox(width: 10),
                    _pdfMetric('생성일', HeadMemo._fmtDateTime(book.createdAt), soft, ink, muted),
                    pw.SizedBox(width: 10),
                    _pdfMetric('수정일', HeadMemo._fmtDateTime(book.updatedAt), soft, ink, muted),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('목차', style: titleStyle(24)),
              pw.SizedBox(height: 16),
              for (int i = 0; i < book.pages.length; i++)
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  padding: const pw.EdgeInsets.all(11),
                  decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(10)),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 30,
                        height: 24,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(color: accentSoft, borderRadius: pw.BorderRadius.circular(8)),
                        child: pw.Text('${i + 3}', style: pw.TextStyle(color: accent, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(child: pw.Text(_pageTitle(book.pages[i]), style: titleStyle(11))),
                      pw.Text('${i + 3}p', style: bodyStyle(9, color: muted)),
                    ],
                  ),
                ),
              pw.Spacer(),
              footer(ctx),
            ],
          );
        },
      ),
    );

    for (int i = 0; i < book.pages.length; i++) {
      final page = book.pages[i];
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(42, 46, 42, 42),
          footer: footer,
          build: (ctx) {
            return [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 12),
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: .8))),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(child: pw.Text(_pageTitle(page), style: titleStyle(book.headerFontSize))),
                    pw.Text('${i + 3}p', style: bodyStyle(9, color: muted)),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Text(page.body.trim().isEmpty ? '본문이 비어 있습니다.' : page.body.trim(), style: bodyStyle(book.bodyFontSize)),
              if (page.todos.isNotEmpty) ...[
                pw.SizedBox(height: 22),
                pw.Container(height: .8, color: line),
                pw.SizedBox(height: 12),
                pw.Text('Todo', style: titleStyle(13)),
                pw.SizedBox(height: 8),
                for (final todo in page.todos)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(todo.done ? '☑' : '☐', style: bodyStyle(11, color: todo.done ? accent : muted)),
                        pw.SizedBox(width: 7),
                        pw.Expanded(child: pw.Text(todo.text, style: bodyStyle(10, color: todo.done ? muted : ink))),
                      ],
                    ),
                  ),
              ],
            ];
          },
        ),
      );
    }

    return doc.save();
  }

  pw.Widget _pdfMetric(String label, String value, PdfColor fill, PdfColor ink, PdfColor muted) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: fill, borderRadius: pw.BorderRadius.circular(12)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8.5, color: muted, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(value, style: pw.TextStyle(fontSize: 11, color: ink, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _buildMarkdown(HeadMemoBook book, DateTime exportedAt) {
    final b = StringBuffer();
    b.writeln('# ${book.name}');
    b.writeln();
    b.writeln('- 생성: ${HeadMemo._fmtDateTime(book.createdAt)}');
    b.writeln('- 수정: ${HeadMemo._fmtDateTime(book.updatedAt)}');
    b.writeln('- 내보내기: ${HeadMemo._fmtDateTime(exportedAt)}');
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('## 목차');
    b.writeln();
    for (int i = 0; i < book.pages.length; i++) {
      b.writeln('${i + 1}. ${_pageTitle(book.pages[i])}');
    }
    for (int i = 0; i < book.pages.length; i++) {
      final page = book.pages[i];
      b.writeln();
      b.writeln('---');
      b.writeln();
      b.writeln('## ${_pageTitle(page)}');
      b.writeln();
      b.writeln(page.body.trim().isEmpty ? '_본문이 비어 있습니다._' : page.body.trim());
      if (page.todos.isNotEmpty) {
        b.writeln();
        b.writeln('### Todo');
        b.writeln();
        for (final todo in page.todos) {
          b.writeln('- [${todo.done ? 'x' : ' '}] ${todo.text}');
        }
      }
    }
    b.writeln();
    return b.toString();
  }

  String _fmt2(int n) => n.toString().padLeft(2, '0');

  String _fmtYMD(DateTime d) => '${d.year}-${_fmt2(d.month)}-${_fmt2(d.day)}';

  String _fmtCompact(DateTime d) => '${d.year}${_fmt2(d.month)}${_fmt2(d.day)}_${_fmt2(d.hour)}${_fmt2(d.minute)}${_fmt2(d.second)}';

  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _encodeSubjectRfc2047(String subject) {
    final hasNonAscii = subject.codeUnits.any((c) => c > 127);
    if (!hasNonAscii) return subject;
    final subjectB64 = base64.encode(utf8.encode(subject));
    return '=?utf-8?B?$subjectB64?=';
  }

  String _safeFileName(String raw) {
    final base = raw.trim().isEmpty ? 'head_memo_book' : raw.trim();
    final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final ascii = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '');
    return ascii.trim().isEmpty ? 'head_memo_book' : ascii;
  }
}

class _BookshelfBookSpine extends StatelessWidget {
  const _BookshelfBookSpine({
    required this.book,
    required this.active,
    required this.index,
    required this.onOpen,
  });

  final HeadMemoBook book;
  final bool active;
  final int index;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = 154.0 + ((index % 4) * 12.0);
    final width = active ? 62.0 : 54.0;
    final fill = active ? cs.primaryContainer : cs.surface;
    final foreground = active ? cs.onPrimaryContainer : cs.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, active ? -14 : 0, 0),
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? cs.primary.withOpacity(.5) : cs.outlineVariant.withOpacity(.9),
                width: active ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(active ? .18 : .08),
                  blurRadius: active ? 20 : 10,
                  offset: Offset(0, active ? 10 : 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 7,
                  top: 10,
                  bottom: 10,
                  child: Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: active ? cs.primary.withOpacity(.55) : cs.primary.withOpacity(.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          book.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 7,
                  bottom: 8,
                  child: Icon(
                    active ? Icons.bookmark_rounded : Icons.auto_stories_rounded,
                    size: 16,
                    color: active ? cs.primary : cs.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookshelfBookCard extends StatelessWidget {
  const _BookshelfBookCard({
    required this.book,
    required this.active,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  final HeadMemoBook book;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  int get _todoCount => book.pages.fold<int>(0, (sum, page) => sum + page.todos.length);

  int get _doneCount => book.pages.fold<int>(0, (sum, page) => sum + page.completedTodoCount);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Material(
      color: active ? cs.primaryContainer.withOpacity(.5) : cs.surfaceContainerHighest.withOpacity(.45),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 66,
                decoration: BoxDecoration(
                  color: active ? cs.primary : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.08),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  active ? Icons.menu_book_rounded : Icons.menu_book_rounded,
                  color: active ? cs.onPrimary : cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            book.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '편집 중',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniPill(icon: Icons.article_rounded, text: '${book.pages.length}쪽'),
                        _MiniPill(icon: Icons.checklist_rounded, text: '$_doneCount/$_todoCount'),
                        _MiniPill(icon: Icons.schedule_rounded, text: HeadMemo._fmtDateTime(book.updatedAt)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: '꺼내서 편집',
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '복제',
                        onPressed: onDuplicate,
                        icon: const Icon(Icons.copy_all_rounded),
                      ),
                      IconButton(
                        tooltip: '삭제',
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookshelfEmptyState extends StatelessWidget {
  const _BookshelfEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(.7),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(Icons.library_books_rounded, size: 42, color: cs.outline),
            ),
            const SizedBox(height: 14),
            Text(
              '책장에서 찾을 메모북이 없습니다.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '새 메모북을 꽂아두고 필요할 때 꺼내 편집하세요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('새 메모북'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.strong = false,
    this.color,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool strong;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color ?? (strong ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(.72)),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground ?? (strong ? cs.onPrimaryContainer : cs.primary)),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: foreground ?? (strong ? cs.onPrimaryContainer : cs.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.text, this.strong = false});

  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: strong ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: strong ? cs.onPrimaryContainer : cs.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: strong ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    super.key,
    required this.todo,
    required this.onDone,
    required this.onText,
    required this.onDelete,
  });

  final HeadMemoTodo todo;
  final ValueChanged<bool> onDone;
  final ValueChanged<String> onText;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: todo.done,
            onChanged: (value) => onDone(value ?? false),
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('todo_text_${todo.id}'),
              initialValue: todo.text,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(
                decoration: todo.done ? TextDecoration.lineThrough : TextDecoration.none,
                color: todo.done ? cs.outline : cs.onSurface,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '투두 내용',
                isDense: true,
              ),
              onChanged: onText,
            ),
          ),
          IconButton(
            tooltip: '투두 삭제',
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.recipient,
    required this.onSelected,
    required this.onDelete,
  });

  final HeadMemoRecipient recipient;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = recipient.label.trim().isEmpty
        ? '@'
        : recipient.label.trim().substring(0, 1).toUpperCase();
    return Material(
      color: recipient.selected
          ? cs.primaryContainer.withOpacity(.45)
          : cs.surfaceContainerHighest.withOpacity(.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onSelected(!recipient.selected),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: recipient.selected
                  ? cs.primary.withOpacity(.35)
                  : cs.outlineVariant.withOpacity(.7),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: recipient.selected,
                onChanged: (value) => onSelected(value ?? false),
              ),
              CircleAvatar(
                backgroundColor: recipient.selected ? cs.primary : cs.surface,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: recipient.selected ? cs.onPrimary : cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipient.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recipient.selected ? '전송 대상' : '보관됨',
                      style: TextStyle(color: cs.outline),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '수신자 삭제',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientEmptyState extends StatelessWidget {
  const _RecipientEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_unread_outlined, size: 44, color: cs.outline),
            const SizedBox(height: 10),
            Text('저장된 수신자가 없습니다.', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('이메일을 추가한 뒤 선택해서 PDF와 Markdown 전송에 사용하세요.', textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
          ],
        ),
      ),
    );
  }
}

class _FontSlider extends StatelessWidget {
  const _FontSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            const Spacer(),
            Text(value.round().toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: (max - min).round(),
          value: value.clamp(min, max).toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class ValueListenableNotifier<T> extends ValueNotifier<T> {
  ValueListenableNotifier(super.value);

  @override
  set value(T newValue) {
    super.value = newValue;
  }
}
