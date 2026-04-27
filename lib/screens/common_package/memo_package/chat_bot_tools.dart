import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'chat_bot_engine.dart';

enum ChillTodoMode {
  a,
  b,
}

class ChillStore {
  ChillStore._();

  static final ChillStore instance = ChillStore._();

  static const _kProfileSeed = 'chill_profile_seed_v1';
  static const _kProfileName = 'chill_profile_name_v1';
  static const _kFocusActive = 'chill_focus_active_v1';
  static const _kFocusPlannedEndMs = 'chill_focus_planned_end_ms_v1';
  static const _kFocusMinutes = 'chill_focus_minutes_v1';
  static const _kChatMessages = 'chill_chat_messages_v1';
  static const _kTodoPhrases = 'chill_todo_phrases_v1';

  static const int _kNotifFocus = 5000000;
  static const int _kNotifDailySubmission1100 = 5000011;
  static const int _kNotifDailySubmission1700 = 5000017;
  static const int _kNotifDailySubmission2000 = 5000020;
  static const Set<int> _kLegacyProtectedSubmissionNotifIds = <int>{
    5000012,
    5000016,
    5000018,
  };
  static const String _kProtectedSubmissionTitle = '매 주 마지막 근무요일에 출근부, 휴게시간 기록부는 제출';
  static const String _kProtectedEventKeyPrefix = 'protected_weekly_submission';
  static const int _kProtectedEventDays = 90;

  static int _todoNotifId(int todoId) => 2000000 + todoId;
  static int _eventNotifId(int eventId) => 3000000 + eventId;
  static int _routineNotifId(int routineId) => 4000000 + routineId;

  static const _dbName = 'chill_with_you_v2.db';
  static const _dbVersion = 3;

  int? _eventsRangeStartMs;
  int? _eventsRangeEndMs;

  final ValueNotifier<ChillCompanionProfile> profile =
  ValueNotifier<ChillCompanionProfile>(
    const ChillCompanionProfile(seed: 1, name: '챗봇'),
  );

  final ValueNotifier<ChillMood> mood =
  ValueNotifier<ChillMood>(ChillMood.calm);
  final ValueNotifier<String> headline = ValueNotifier<String>('');

  final ValueNotifier<List<ChillChatMessage>> chatMessages =
  ValueNotifier<List<ChillChatMessage>>(<ChillChatMessage>[]);

  final ValueNotifier<List<ChillTodo>> todos =
  ValueNotifier<List<ChillTodo>>(<ChillTodo>[]);
  final ValueNotifier<List<ChillNote>> notes =
  ValueNotifier<List<ChillNote>>(<ChillNote>[]);
  final ValueNotifier<List<ChillEvent>> events =
  ValueNotifier<List<ChillEvent>>(<ChillEvent>[]);
  final ValueNotifier<List<ChillRoutine>> routines =
  ValueNotifier<List<ChillRoutine>>(<ChillRoutine>[]);

  final ValueNotifier<List<String>> todoPhrases =
  ValueNotifier<List<String>>(<String>[]);

  final ValueNotifier<ChillFocusState> focus =
  ValueNotifier<ChillFocusState>(ChillFocusState.none());

  final ValueNotifier<int?> openTodoId = ValueNotifier<int?>(null);
  final ValueNotifier<int?> openEventId = ValueNotifier<int?>(null);

  SharedPreferences? _prefs;
  Database? _db;
  FlutterLocalNotificationsPlugin? _noti;

  ChillCompanionEngine? _engine;
  bool _inited = false;
  Future<void>? _initFuture;

  Future<void> init() {
    _initFuture ??= _initImpl();
    return _initFuture!;
  }

  Future<void> _initImpl() async {
    if (_inited) return;

    _prefs ??= await SharedPreferences.getInstance();
    _loadProfileFromPrefs();
    _loadChatFromPrefs();
    _loadTodoPhrasesFromPrefs();

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}

    await _initNotifications();
    await _openDb();
    await _ensureProtectedSubmissionSystem();

    await _refreshAllNoInit();
    await _syncTodoNotifications(todos.value);
    await _syncEventNotifications(events.value);
    await _restoreFocusIfAny();

    _engine = ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.greeting(name: profile.value.name);
    _bootstrapChatIfEmpty();

    _inited = true;
  }

  int? consumeOpenTodoId() {
    final v = openTodoId.value;
    openTodoId.value = null;
    return v;
  }

  int? consumeOpenEventId() {
    final v = openEventId.value;
    openEventId.value = null;
    return v;
  }

  void _handleNotificationPayload(String payload) {
    final p = payload.trim();

    int? parseId(String prefix) {
      if (!p.startsWith(prefix)) return null;
      final rest = p.substring(prefix.length);
      return int.tryParse(rest);
    }

    final todoId = parseId('todo:');
    final eventId = parseId('event:');

    if (todoId != null) openTodoId.value = todoId;
    if (eventId != null) openEventId.value = eventId;
  }

  void _loadProfileFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;
    final seed = prefs.getInt(_kProfileSeed);
    final name = (prefs.getString(_kProfileName) ?? '').trim();

    final resolvedSeed = seed ?? _stableSeedFromDeviceTime();
    final resolvedName = name.isEmpty ? '챗봇' : name;
    profile.value = ChillCompanionProfile(seed: resolvedSeed, name: resolvedName);
  }

  void _loadTodoPhrasesFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;

    final raw = prefs.getString(_kTodoPhrases);
    List<String> list = <String>[];

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final it in decoded) {
            final s = it.toString().trim();
            if (s.isNotEmpty) list.add(s);
          }
        }
      } catch (_) {}
    }

    if (!list.contains('출차 예정')) {
      list = <String>['출차 예정', ...list.where((e) => e != '출차 예정')];
    }

    todoPhrases.value = list;
  }

  Future<void> addTodoPhrase(String phrase) async {
    await init();
    final p = phrase.trim();
    if (p.isEmpty) return;
    final next = <String>[...todoPhrases.value];
    if (next.contains(p)) return;
    next.add(p);
    todoPhrases.value = next;
    await _persistTodoPhrases();
  }

  Future<void> removeTodoPhrase(String phrase) async {
    await init();
    final p = phrase.trim();
    if (p.isEmpty) return;
    final next = <String>[...todoPhrases.value]..removeWhere((e) => e == p);
    if (!next.contains('출차 예정')) {
      next.insert(0, '출차 예정');
    }
    todoPhrases.value = next;
    await _persistTodoPhrases();
  }

  Future<void> _persistTodoPhrases() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final uniq = <String>{};
    final list = <String>[];
    for (final e in todoPhrases.value) {
      final s = e.trim();
      if (s.isEmpty) continue;
      if (uniq.add(s)) list.add(s);
    }
    if (!list.contains('출차 예정')) list.insert(0, '출차 예정');
    try {
      await prefs.setString(_kTodoPhrases, jsonEncode(list));
    } catch (_) {}
  }

  int _stableSeedFromDeviceTime() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final mixed = (ms ^ (ms << 13) ^ (ms >> 7)) & 0x7fffffff;
    _prefs?.setInt(_kProfileSeed, mixed);
    return mixed;
  }

  Future<void> renameCompanion(String name) async {
    await init();
    final n = name.trim();
    if (n.isEmpty) return;
    await _prefs?.setString(_kProfileName, n);
    profile.value = profile.value.copyWith(name: n);
    _engine = ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.greeting(name: n);
  }

  Future<void> rerollCompanionSeed() async {
    await init();
    final next = math.Random().nextInt(0x7fffffff);
    await _prefs?.setInt(_kProfileSeed, next);
    profile.value = profile.value.copyWith(seed: next);
    _engine = ChillCompanionEngine(seed: next);
    headline.value = _engine!.idleHint(name: profile.value.name);
  }

  void _loadChatFromPrefs() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_kChatMessages);
    if (raw == null || raw.trim().isEmpty) {
      chatMessages.value = <ChillChatMessage>[];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        chatMessages.value = <ChillChatMessage>[];
        return;
      }
      final list = <ChillChatMessage>[];
      for (final it in decoded) {
        if (it is Map) {
          final m = <String, Object?>{};
          it.forEach((k, v) {
            m[k.toString()] = v;
          });
          final msg = ChillChatMessage.fromJson(m);
          if (msg.text.trim().isNotEmpty) list.add(msg);
        }
      }
      chatMessages.value = list;
    } catch (_) {
      chatMessages.value = <ChillChatMessage>[];
    }
  }

  void _bootstrapChatIfEmpty() {
    if (chatMessages.value.isNotEmpty) return;
    final eng = _engine;
    if (eng == null) return;
    final greet = eng.greeting(name: profile.value.name);
    final now = DateTime.now();
    final next = <ChillChatMessage>[
      ChillChatMessage(role: ChatRole.assistant, text: greet, at: now),
    ];
    chatMessages.value = next;
    unawaited(_persistChat());
  }

  Future<void> _persistChat() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final msgs = chatMessages.value;
    final trimmed = msgs.length > 200 ? msgs.sublist(msgs.length - 200) : msgs;
    final raw = jsonEncode(trimmed.map((e) => e.toJson()).toList(growable: false));
    try {
      await prefs.setString(_kChatMessages, raw);
    } catch (_) {}
  }

  Future<void> sendChatUser(String text) async {
    await init();
    final t = text.trim();
    if (t.isEmpty) return;

    final now = DateTime.now();
    final next = <ChillChatMessage>[
      ...chatMessages.value,
      ChillChatMessage(role: ChatRole.user, text: t, at: now),
    ];
    chatMessages.value = next;
    await _persistChat();

    final eng = _engine;
    if (eng == null) return;

    final focusState = focus.value;
    final reply = eng.replyToUser(
      name: profile.value.name,
      input: t,
      mood: mood.value,
      focusRunning: focusState.isRunning,
      focusRemainLabel: focusState.remainLabel(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 260));
    final next2 = <ChillChatMessage>[
      ...chatMessages.value,
      ChillChatMessage(role: ChatRole.assistant, text: reply, at: DateTime.now()),
    ];
    chatMessages.value = next2;
    headline.value = reply;
    await _persistChat();
  }

  Future<void> clearChat() async {
    await init();
    chatMessages.value = <ChillChatMessage>[];
    await _persistChat();
    _bootstrapChatIfEmpty();
  }

  Future<void> _initNotifications() async {
    _noti ??= FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);

    await _noti!.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.trim().isEmpty) return;
        _handleNotificationPayload(payload);
      },
    );
  }

  NotificationDetails _details({bool high = false}) {
    if (high) {
      const android = AndroidNotificationDetails(
        'chill_with_you',
        'Chill with You',
        channelDescription: '집중/루틴/일정/할 일 알림',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iOS = DarwinNotificationDetails();
      return const NotificationDetails(android: android, iOS: iOS);
    }

    const android = AndroidNotificationDetails(
      'chill_with_you',
      'Chill with You',
      channelDescription: '집중/루틴/일정/할 일 알림',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iOS = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: iOS);
  }

  Future<void> _scheduleOneShot({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
    bool exact = false,
    bool highImportance = false,
  }) async {
    final noti = _noti;
    if (noti == null) return;
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    Future<void> doSchedule(AndroidScheduleMode mode) async {
      await noti.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        _details(high: highImportance),
        payload: payload,
        androidScheduleMode: mode,
      );
    }

    if (!exact) {
      await doSchedule(AndroidScheduleMode.inexactAllowWhileIdle);
      return;
    }

    try {
      await doSchedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      await doSchedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> _ensureProtectedSubmissionSystem() async {
    final db = _db;
    if (db == null) return;
    await _cancelLegacyProtectedSubmissionNotifications();
    await _scheduleProtectedSubmissionNotifications();
    await _ensureProtectedSubmissionEvents(db);
  }

  Future<void> cancelProtectedSubmissionNotifications() async {
    await _initNotifications();
    final noti = _noti;
    if (noti == null) return;
    for (final id in <int>[
      _kNotifDailySubmission1100,
      _kNotifDailySubmission1700,
      _kNotifDailySubmission2000,
      ..._kLegacyProtectedSubmissionNotifIds,
    ]) {
      try {
        await noti.cancel(id);
      } catch (_) {}
    }
  }

  Future<void> _cancelLegacyProtectedSubmissionNotifications() async {
    final noti = _noti;
    if (noti == null) return;
    for (final id in _kLegacyProtectedSubmissionNotifIds) {
      try {
        await noti.cancel(id);
      } catch (_) {}
    }
  }

  Future<void> _scheduleProtectedSubmissionNotifications() async {
    await _scheduleDailyTime(
      id: _kNotifDailySubmission1100,
      time: const TimeOfDay(hour: 11, minute: 0),
      title: _kProtectedSubmissionTitle,
      body: _kProtectedSubmissionTitle,
      payload: 'system_submission:daily_1100',
      exact: true,
      highImportance: true,
    );
    await _scheduleDailyTime(
      id: _kNotifDailySubmission1700,
      time: const TimeOfDay(hour: 17, minute: 0),
      title: _kProtectedSubmissionTitle,
      body: _kProtectedSubmissionTitle,
      payload: 'system_submission:daily_1700',
      exact: true,
      highImportance: true,
    );
    await _scheduleDailyTime(
      id: _kNotifDailySubmission2000,
      time: const TimeOfDay(hour: 20, minute: 0),
      title: _kProtectedSubmissionTitle,
      body: _kProtectedSubmissionTitle,
      payload: 'system_submission:daily_2000',
      exact: true,
      highImportance: true,
    );
  }

  Future<void> _scheduleDailyTime({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
    String? payload,
    bool exact = false,
    bool highImportance = false,
    bool enabled = true,
  }) async {
    final noti = _noti;
    if (noti == null) return;
    await noti.cancel(id);
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    Future<void> doSchedule(AndroidScheduleMode mode) async {
      await noti.zonedSchedule(
        id,
        title,
        body,
        next,
        _details(high: highImportance),
        payload: payload,
        androidScheduleMode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    if (!exact) {
      await doSchedule(AndroidScheduleMode.inexactAllowWhileIdle);
      return;
    }

    try {
      await doSchedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      await doSchedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> _ensureProtectedSubmissionEvents(Database db) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final wantedKeys = <String>{};

    for (var day = 0; day < _kProtectedEventDays; day++) {
      final targetDay = today.add(Duration(days: day));
      for (final time in const <TimeOfDay>[
        TimeOfDay(hour: 11, minute: 0),
        TimeOfDay(hour: 17, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ]) {
        final startAt = DateTime(
          targetDay.year,
          targetDay.month,
          targetDay.day,
          time.hour,
          time.minute,
        );
        final key = _protectedEventKeyFor(startAt);
        wantedKeys.add(key);

        final exists = await db.query(
          'events',
          columns: ['id'],
          where: 'system_key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (exists.isNotEmpty) continue;

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await db.insert('events', {
          'title': _kProtectedSubmissionTitle,
          'start_at_ms': startAt.millisecondsSinceEpoch,
          'end_at_ms': null,
          'all_day': 0,
          'remind_at_ms': null,
          'is_done': 0,
          'is_locked': 1,
          'system_key': key,
          'created_at_ms': nowMs,
          'updated_at_ms': nowMs,
        });
      }
    }

    final stale = await db.query(
      'events',
      columns: ['id', 'system_key'],
      where: 'system_key LIKE ?',
      whereArgs: ['${_kProtectedEventKeyPrefix}%'],
    );

    for (final row in stale) {
      final id = (row['id'] as int?) ?? 0;
      final key = (row['system_key'] as String?) ?? '';
      if (id <= 0) continue;
      if (wantedKeys.contains(key)) continue;
      await db.delete('events', where: 'id = ?', whereArgs: [id]);
    }
  }

  String _protectedEventKeyFor(DateTime startAt) {
    return '$_kProtectedEventKeyPrefix:${DateFormat('yyyyMMddHHmm').format(startAt)}';
  }

  bool _isProtectedSystemKey(String? systemKey) {
    final key = (systemKey ?? '').trim();
    return key.startsWith(_kProtectedEventKeyPrefix);
  }

  bool _isHiddenFromUserEvent(ChillEvent event) {
    return _isProtectedSystemKey(event.systemKey);
  }

  List<ChillEvent> _filterVisibleEvents(Iterable<ChillEvent> source) {
    return source.where((e) => !_isHiddenFromUserEvent(e)).toList(growable: false);
  }

  Future<bool> _isProtectedEventId(Database db, int id) async {
    final rows = await db.query(
      'events',
      columns: ['is_locked', 'system_key'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final isLocked = ((row['is_locked'] as int?) ?? 0) == 1;
    final systemKey = row['system_key'] as String?;
    return isLocked || _isProtectedSystemKey(systemKey);
  }

  Future<void> _cancelNotification(int id) async {
    try {
      await _noti?.cancel(id);
    } catch (_) {}
  }

  DateTime _nextOccurrenceFromMinutes(int minutes) {
    final m = minutes.clamp(0, 23 * 60 + 59);
    final now = DateTime.now();
    var dt = DateTime(now.year, now.month, now.day, m ~/ 60, m % 60);
    if (!dt.isAfter(now)) {
      dt = dt.add(const Duration(days: 1));
    }
    return dt;
  }

  Future<void> _openDb() async {
    if (_db != null) return;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);

    Future<void> ensureEventColumns(Database db) async {
      try {
        final info = await db.rawQuery('PRAGMA table_info(events)');
        final names = <String>{};
        for (final row in info) {
          final n = row['name'];
          if (n is String) names.add(n);
        }
        if (!names.contains('is_done')) {
          await db.execute(
            'ALTER TABLE events ADD COLUMN is_done INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('is_locked')) {
          await db.execute(
            'ALTER TABLE events ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('system_key')) {
          await db.execute(
            'ALTER TABLE events ADD COLUMN system_key TEXT',
          );
        }
      } catch (_) {}
    }

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onOpen: (db) async {
        await ensureEventColumns(db);
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE todos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mode INTEGER NOT NULL,
            title TEXT NOT NULL,
            plate TEXT,
            content TEXT,
            alarm_time_minutes INTEGER,
            is_done INTEGER NOT NULL DEFAULT 0,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE notes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            content TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE events(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            start_at_ms INTEGER NOT NULL,
            end_at_ms INTEGER,
            all_day INTEGER NOT NULL DEFAULT 0,
            remind_at_ms INTEGER,
            is_done INTEGER NOT NULL DEFAULT 0,
            is_locked INTEGER NOT NULL DEFAULT 0,
            system_key TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE routines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            time_minutes INTEGER NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await ensureEventColumns(db);
      },
    );
  }

  Future<void> refreshAll() async {
    await init();
    await _refreshAllNoInit();
  }

  Future<void> refreshEventsRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;
    await _ensureProtectedSubmissionSystem();
    _eventsRangeStartMs = startInclusive.millisecondsSinceEpoch;
    _eventsRangeEndMs = endExclusive.millisecondsSinceEpoch;
    events.value = await _loadEventsRangeMs(
      db,
      _eventsRangeStartMs!,
      _eventsRangeEndMs!,
    );
    await _syncEventNotifications(events.value);
  }

  Future<ChillEvent?> fetchEventById(int id) async {
    await init();
    final db = _db;
    if (db == null) return null;
    final rows = await db.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final event = ChillEvent.fromRow(rows.first);
    if (_isHiddenFromUserEvent(event)) return null;
    return event;
  }

  Future<void> _refreshEventsAfterMutate() async {
    final db = _db;
    if (db == null) return;
    await _ensureProtectedSubmissionSystem();
    if (_eventsRangeStartMs != null && _eventsRangeEndMs != null) {
      events.value = await _loadEventsRangeMs(
        db,
        _eventsRangeStartMs!,
        _eventsRangeEndMs!,
      );
    } else {
      events.value = await _loadEvents(db);
    }
    await _syncEventNotifications(events.value);
  }

  Future<void> _refreshAllNoInit() async {
    final db = _db;
    if (db == null) return;
    await _ensureProtectedSubmissionSystem();
    todos.value = await _loadTodos(db);
    notes.value = await _loadNotes(db);
    if (_eventsRangeStartMs != null && _eventsRangeEndMs != null) {
      events.value = await _loadEventsRangeMs(
        db,
        _eventsRangeStartMs!,
        _eventsRangeEndMs!,
      );
    } else {
      events.value = await _loadEvents(db);
    }
    routines.value = await _loadRoutines(db);
  }

  Future<List<ChillTodo>> _loadTodos(Database db) async {
    final rows = await db.query(
      'todos',
      orderBy: 'is_done ASC, updated_at_ms DESC',
    );
    return rows.map(ChillTodo.fromRow).toList(growable: false);
  }

  Future<List<ChillNote>> _loadNotes(Database db) async {
    final rows = await db.query('notes', orderBy: 'updated_at_ms DESC');
    return rows.map(ChillNote.fromRow).toList(growable: false);
  }

  Future<List<ChillEvent>> _loadEvents(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'events',
      where: 'end_at_ms IS NULL OR end_at_ms >= ?',
      whereArgs: [now - 7 * 24 * 3600 * 1000],
      orderBy: 'start_at_ms ASC',
    );
    return _filterVisibleEvents(rows.map(ChillEvent.fromRow));
  }

  Future<List<ChillEvent>> _loadEventsRangeMs(
      Database db,
      int startMs,
      int endMs,
      ) async {
    final rows = await db.query(
      'events',
      where: 'start_at_ms < ? AND (end_at_ms IS NULL OR end_at_ms >= ?)',
      whereArgs: [endMs, startMs],
      orderBy: 'start_at_ms ASC',
    );
    return _filterVisibleEvents(rows.map(ChillEvent.fromRow));
  }

  Future<List<ChillRoutine>> _loadRoutines(Database db) async {
    final rows = await db.query(
      'routines',
      orderBy: 'enabled DESC, time_minutes ASC',
    );
    return rows.map(ChillRoutine.fromRow).toList(growable: false);
  }

  Future<void> _restoreFocusIfAny() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final active = prefs.getBool(_kFocusActive) ?? false;
    if (!active) return;
    final endMs = prefs.getInt(_kFocusPlannedEndMs) ?? 0;
    final mins = prefs.getInt(_kFocusMinutes) ?? 0;
    if (endMs <= 0 || mins <= 0) {
      await _clearFocusPrefs();
      return;
    }
    final endAt = DateTime.fromMillisecondsSinceEpoch(endMs);
    if (endAt.isBefore(DateTime.now())) {
      focus.value = ChillFocusState.done(plannedEndAt: endAt, minutes: mins);
      mood.value = ChillMood.proud;
      _engine ??= ChillCompanionEngine(seed: profile.value.seed);
      headline.value = _engine!.onFocusDone(name: profile.value.name);
      await _clearFocusPrefs();
      return;
    }

    focus.value = ChillFocusState.running(plannedEndAt: endAt, minutes: mins);
    mood.value = ChillMood.focus;
  }

  Future<void> startFocus({required int minutes}) async {
    await init();
    final m = minutes.clamp(1, 12 * 60);

    await stopFocus(silent: true);

    final endAt = DateTime.now().add(Duration(minutes: m));
    focus.value = ChillFocusState.running(plannedEndAt: endAt, minutes: m);
    mood.value = ChillMood.focus;

    await _prefs?.setBool(_kFocusActive, true);
    await _prefs?.setInt(_kFocusPlannedEndMs, endAt.millisecondsSinceEpoch);
    await _prefs?.setInt(_kFocusMinutes, m);

    _engine ??= ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.onFocusStart(name: profile.value.name, minutes: m);

    await _scheduleOneShot(
      id: _kNotifFocus,
      when: endAt,
      title: '집중 종료',
      body: '${m}분 완료',
      payload: 'focus_done',
    );
  }

  Future<void> stopFocus({bool silent = false}) async {
    await init();
    final st = focus.value;
    if (!st.isRunning) return;
    focus.value = ChillFocusState.none();
    mood.value = ChillMood.calm;
    await _clearFocusPrefs();
    await _cancelNotification(_kNotifFocus);
    if (!silent) {
      _engine ??= ChillCompanionEngine(seed: profile.value.seed);
      headline.value = _engine!.onFocusStop(name: profile.value.name);
    }
  }

  Future<void> markFocusDoneFromUi() async {
    await init();
    final st = focus.value;
    if (!st.isRunning) return;
    focus.value = ChillFocusState.done(
      plannedEndAt: st.plannedEndAt!,
      minutes: st.minutes,
    );
    mood.value = ChillMood.proud;
    await _clearFocusPrefs();
    await _cancelNotification(_kNotifFocus);
    _engine ??= ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.onFocusDone(name: profile.value.name);
  }

  Future<void> _clearFocusPrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setBool(_kFocusActive, false);
    await prefs.remove(_kFocusPlannedEndMs);
    await prefs.remove(_kFocusMinutes);
  }

  Future<void> _syncTodoNotifications(List<ChillTodo> list) async {
    final now = DateTime.now();
    for (final t in list) {
      try {
        final id = _todoNotifId(t.id);
        await _cancelNotification(id);

        if (t.isDone) continue;
        final alarm = t.alarmTimeMinutes;
        if (alarm == null) continue;

        final when = _nextOccurrenceFromMinutes(alarm);
        if (!when.isAfter(now)) continue;

        final body = t.mode == ChillTodoMode.b
            ? '${t.plate ?? ''} ${t.content ?? ''}'.trim()
            : t.title;

        await _scheduleOneShot(
          id: id,
          when: when,
          title: '할 일',
          body: body.isEmpty ? '확인 필요' : body,
          payload: 'todo:${t.id}',
          exact: true,
          highImportance: true,
        );
      } catch (_) {}
    }
  }

  Future<void> _syncEventNotifications(List<ChillEvent> list) async {
    final now = DateTime.now();
    for (final e in list) {
      try {
        final id = _eventNotifId(e.id);
        final when = e.remindAt;
        if (e.isLocked || _isProtectedSystemKey(e.systemKey)) {
          await _cancelNotification(id);
          continue;
        }
        if (e.isDone) {
          await _cancelNotification(id);
          continue;
        }
        if (when == null || !when.isAfter(now)) {
          await _cancelNotification(id);
          continue;
        }
        await _cancelNotification(id);
        await _scheduleOneShot(
          id: id,
          when: when,
          title: '일정',
          body: e.title,
          payload: 'event:${e.id}',
          exact: true,
          highImportance: true,
        );
      } catch (_) {}
    }
  }

  Future<void> addTodoA({required String title, int? alarmTimeMinutes}) async {
    await init();
    final db = _db;
    if (db == null) return;

    final t = title.trim();
    if (t.isEmpty) return;

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final id = await db.insert('todos', {
      'mode': ChillTodoMode.a.index,
      'title': t,
      'plate': null,
      'content': null,
      'alarm_time_minutes': alarmTimeMinutes,
      'is_done': 0,
      'created_at_ms': nowMs,
      'updated_at_ms': nowMs,
    });

    await _refreshAllNoInit();
    await _syncTodoNotifications(todos.value.where((e) => e.id == id).toList());

    _engine ??= ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.onTodoAdded(title: t);
  }

  Future<void> addTodoB({
    required String plate,
    required String content,
    int? alarmTimeMinutes,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;

    final p = plate.trim();
    final c = content.trim();
    if (p.isEmpty && c.isEmpty) return;

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final title = p.isEmpty ? '차량' : p;

    final id = await db.insert('todos', {
      'mode': ChillTodoMode.b.index,
      'title': title,
      'plate': p.isEmpty ? null : p,
      'content': c.isEmpty ? null : c,
      'alarm_time_minutes': alarmTimeMinutes,
      'is_done': 0,
      'created_at_ms': nowMs,
      'updated_at_ms': nowMs,
    });

    await _refreshAllNoInit();
    await _syncTodoNotifications(todos.value.where((e) => e.id == id).toList());

    _engine ??= ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.onTodoAdded(title: title);
  }

  Future<void> toggleTodoDone(ChillTodo todo) async {
    await init();
    final db = _db;
    if (db == null) return;
    final nextDone = todo.isDone ? 0 : 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'todos',
      {'is_done': nextDone, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [todo.id],
    );

    final updatedList = todos.value.map((e) {
      if (e.id != todo.id) return e;
      return e.copyWith(isDone: nextDone == 1);
    }).toList(growable: false);

    todos.value = updatedList;

    final notiId = _todoNotifId(todo.id);
    await _cancelNotification(notiId);

    if (nextDone == 1) {
      _engine ??= ChillCompanionEngine(seed: profile.value.seed);
      headline.value = _engine!.onTodoDone(title: todo.displayTitle());
      mood.value = ChillMood.proud;
    } else {
      mood.value = ChillMood.calm;
      await _syncTodoNotifications([todo.copyWith(isDone: false)]);
    }

    await _refreshAllNoInit();
  }

  Future<void> deleteTodo(ChillTodo todo) async {
    await init();
    final db = _db;
    if (db == null) return;
    await db.delete('todos', where: 'id = ?', whereArgs: [todo.id]);
    await _cancelNotification(_todoNotifId(todo.id));
    await _refreshAllNoInit();
  }

  Future<void> clearDoneTodos() async {
    await init();
    final db = _db;
    if (db == null) return;

    final doneIds = todos.value
        .where((e) => e.isDone)
        .map((e) => e.id)
        .toList(growable: false);
    if (doneIds.isEmpty) return;

    await db.delete('todos', where: 'is_done = 1');

    for (final id in doneIds) {
      await _cancelNotification(_todoNotifId(id));
    }

    await _refreshAllNoInit();
  }

  Future<void> upsertNote({
    int? id,
    required String title,
    required String content,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id == null) {
      await db.insert('notes', {
        'title': title.trim(),
        'content': content.trim(),
        'created_at_ms': now,
        'updated_at_ms': now,
      });
    } else {
      await db.update(
        'notes',
        {
          'title': title.trim(),
          'content': content.trim(),
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await _refreshAllNoInit();
    _engine ??= ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.onNoteSaved();
  }

  Future<void> deleteNote(ChillNote note) async {
    await init();
    final db = _db;
    if (db == null) return;
    await db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    await _refreshAllNoInit();
  }

  Future<void> addEvent({
    required String title,
    required DateTime startAt,
    DateTime? endAt,
    bool allDay = false,
    DateTime? remindAt,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;
    final t = title.trim();
    if (t.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('events', {
      'title': t,
      'start_at_ms': startAt.millisecondsSinceEpoch,
      'end_at_ms': endAt?.millisecondsSinceEpoch,
      'all_day': allDay ? 1 : 0,
      'remind_at_ms': remindAt?.millisecondsSinceEpoch,
      'created_at_ms': now,
      'updated_at_ms': now,
    });

    if (remindAt != null && remindAt.isAfter(DateTime.now())) {
      await _scheduleOneShot(
        id: _eventNotifId(id),
        when: remindAt,
        title: '일정',
        body: t,
        payload: 'event:$id',
        exact: true,
        highImportance: true,
      );
    }

    await _refreshEventsAfterMutate();
    _engine ??= ChillCompanionEngine(seed: profile.value.seed);
    headline.value = _engine!.onEventAdded();
  }

  Future<void> updateEvent({
    required int id,
    required String title,
    required DateTime startAt,
    DateTime? endAt,
    bool allDay = false,
    DateTime? remindAt,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;
    if (await _isProtectedEventId(db, id)) return;

    final t = title.trim();
    if (t.isEmpty) return;

    DateTime? resolvedEnd = endAt;
    if (resolvedEnd != null && resolvedEnd.isBefore(startAt)) {
      resolvedEnd = startAt;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'events',
      {
        'title': t,
        'start_at_ms': startAt.millisecondsSinceEpoch,
        'end_at_ms': resolvedEnd?.millisecondsSinceEpoch,
        'all_day': allDay ? 1 : 0,
        'remind_at_ms': remindAt?.millisecondsSinceEpoch,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    await _cancelNotification(_eventNotifId(id));

    if (remindAt != null && remindAt.isAfter(DateTime.now())) {
      await _scheduleOneShot(
        id: _eventNotifId(id),
        when: remindAt,
        title: '일정',
        body: t,
        payload: 'event:$id',
        exact: true,
        highImportance: true,
      );
    }

    await _refreshEventsAfterMutate();
  }

  Future<void> toggleEventDone(ChillEvent e) async {
    await init();
    final db = _db;
    if (db == null) return;
    if (e.isLocked || _isProtectedSystemKey(e.systemKey)) return;

    final nextDone = e.isDone ? 0 : 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'events',
      {'is_done': nextDone, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [e.id],
    );

    await _cancelNotification(_eventNotifId(e.id));

    if (nextDone == 0) {
      if (e.remindAt != null && e.remindAt!.isAfter(DateTime.now())) {
        await _scheduleOneShot(
          id: _eventNotifId(e.id),
          when: e.remindAt!,
          title: '일정',
          body: e.title,
          payload: 'event:${e.id}',
          exact: true,
          highImportance: true,
        );
      }
    }

    await _refreshEventsAfterMutate();
  }

  Future<int> deleteDoneEventsInRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) async {
    await init();
    final db = _db;
    if (db == null) return 0;

    final startMs = startInclusive.millisecondsSinceEpoch;
    final endMs = endExclusive.millisecondsSinceEpoch;

    final rows = await db.query(
      'events',
      columns: ['id'],
      where:
      'is_done = 1 AND COALESCE(is_locked, 0) = 0 AND start_at_ms < ? AND (end_at_ms IS NULL OR end_at_ms >= ?)',
      whereArgs: [endMs, startMs],
    );

    final ids = rows
        .map((r) => (r['id'] as int?) ?? 0)
        .where((id) => id > 0)
        .toList(growable: false);

    for (final id in ids) {
      await _cancelNotification(_eventNotifId(id));
    }

    final deleted = await db.delete(
      'events',
      where:
      'is_done = 1 AND COALESCE(is_locked, 0) = 0 AND start_at_ms < ? AND (end_at_ms IS NULL OR end_at_ms >= ?)',
      whereArgs: [endMs, startMs],
    );

    await _refreshEventsAfterMutate();
    return deleted;
  }

  Future<void> deleteEvent(ChillEvent event) async {
    await init();
    final db = _db;
    if (db == null) return;
    if (event.isLocked || _isProtectedSystemKey(event.systemKey)) return;
    await db.delete('events', where: 'id = ?', whereArgs: [event.id]);
    await _cancelNotification(_eventNotifId(event.id));
    await _refreshEventsAfterMutate();
  }

  Future<void> addRoutine({
    required String title,
    required TimeOfDay time,
    bool enabled = true,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;
    final t = title.trim();
    if (t.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minutes = time.hour * 60 + time.minute;
    final id = await db.insert('routines', {
      'title': t,
      'time_minutes': minutes,
      'enabled': enabled ? 1 : 0,
      'created_at_ms': now,
      'updated_at_ms': now,
    });

    await _scheduleDailyTime(
      id: _routineNotifId(id),
      time: time,
      title: '루틴',
      body: t,
      payload: 'routine:$id',
      enabled: enabled,
    );

    await _refreshAllNoInit();
  }

  Future<void> toggleRoutineEnabled(ChillRoutine r) async {
    await init();
    final db = _db;
    if (db == null) return;
    final next = r.enabled ? 0 : 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'routines',
      {'enabled': next, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [r.id],
    );
    final time = TimeOfDay(hour: r.timeMinutes ~/ 60, minute: r.timeMinutes % 60);
    await _scheduleDailyTime(
      id: _routineNotifId(r.id),
      time: time,
      title: '루틴',
      body: r.title,
      payload: 'routine:${r.id}',
      enabled: next == 1,
    );
    await _refreshAllNoInit();
  }

  Future<void> deleteRoutine(ChillRoutine r) async {
    await init();
    final db = _db;
    if (db == null) return;
    await db.delete('routines', where: 'id = ?', whereArgs: [r.id]);
    await _cancelNotification(_routineNotifId(r.id));
    await _refreshAllNoInit();
  }
}

class ChillTodo {
  final int id;
  final ChillTodoMode mode;
  final String title;
  final String? plate;
  final String? content;
  final int? alarmTimeMinutes;
  final bool isDone;

  const ChillTodo({
    required this.id,
    required this.mode,
    required this.title,
    required this.plate,
    required this.content,
    required this.alarmTimeMinutes,
    required this.isDone,
  });

  ChillTodo copyWith({
    int? id,
    ChillTodoMode? mode,
    String? title,
    String? plate,
    String? content,
    int? alarmTimeMinutes,
    bool? isDone,
  }) {
    return ChillTodo(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      title: title ?? this.title,
      plate: plate ?? this.plate,
      content: content ?? this.content,
      alarmTimeMinutes: alarmTimeMinutes ?? this.alarmTimeMinutes,
      isDone: isDone ?? this.isDone,
    );
  }

  String displayTitle() {
    if (mode == ChillTodoMode.b) {
      final p = (plate ?? '').trim();
      if (p.isNotEmpty) return p;
      return title.trim().isEmpty ? '차량' : title;
    }
    return title;
  }

  static ChillTodo fromRow(Map<String, Object?> r) {
    final id = (r['id'] as int?) ?? 0;
    final modeRaw = (r['mode'] as int?) ?? 0;
    final mode = modeRaw == ChillTodoMode.b.index ? ChillTodoMode.b : ChillTodoMode.a;
    final title = (r['title'] ?? '').toString();
    final plate = r['plate'] as String?;
    final content = r['content'] as String?;
    final alarm = r['alarm_time_minutes'] as int?;
    final done = ((r['is_done'] as int?) ?? 0) == 1;
    return ChillTodo(
      id: id,
      mode: mode,
      title: title,
      plate: plate,
      content: content,
      alarmTimeMinutes: alarm,
      isDone: done,
    );
  }
}

class ChillNote {
  final int id;
  final String title;
  final String content;
  final DateTime updatedAt;

  const ChillNote({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  static ChillNote fromRow(Map<String, Object?> r) {
    final id = (r['id'] as int?) ?? 0;
    final title = (r['title'] ?? '').toString();
    final content = (r['content'] ?? '').toString();
    final upMs =
        (r['updated_at_ms'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    return ChillNote(
      id: id,
      title: title,
      content: content,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(upMs),
    );
  }
}

class ChillEvent {
  final int id;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;
  final DateTime? remindAt;
  final bool isDone;
  final bool isLocked;
  final String? systemKey;

  const ChillEvent({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.remindAt,
    required this.isDone,
    required this.isLocked,
    required this.systemKey,
  });

  ChillEvent copyWith({
    int? id,
    String? title,
    DateTime? startAt,
    DateTime? endAt,
    bool? allDay,
    DateTime? remindAt,
    bool? isDone,
    bool? isLocked,
    String? systemKey,
  }) {
    return ChillEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      allDay: allDay ?? this.allDay,
      remindAt: remindAt ?? this.remindAt,
      isDone: isDone ?? this.isDone,
      isLocked: isLocked ?? this.isLocked,
      systemKey: systemKey ?? this.systemKey,
    );
  }

  static ChillEvent fromRow(Map<String, Object?> r) {
    final id = (r['id'] as int?) ?? 0;
    final title = (r['title'] ?? '').toString();
    final sMs =
        (r['start_at_ms'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final eMs = r['end_at_ms'] as int?;
    final allDay = ((r['all_day'] as int?) ?? 0) == 1;
    final remMs = r['remind_at_ms'] as int?;
    final done = ((r['is_done'] as int?) ?? 0) == 1;
    final isLocked = ((r['is_locked'] as int?) ?? 0) == 1;
    final systemKey = r['system_key'] as String?;
    return ChillEvent(
      id: id,
      title: title,
      startAt: DateTime.fromMillisecondsSinceEpoch(sMs),
      endAt: eMs == null ? null : DateTime.fromMillisecondsSinceEpoch(eMs),
      allDay: allDay,
      remindAt: remMs == null ? null : DateTime.fromMillisecondsSinceEpoch(remMs),
      isDone: done,
      isLocked: isLocked,
      systemKey: systemKey,
    );
  }
}

class ChillRoutine {
  final int id;
  final String title;
  final int timeMinutes;
  final bool enabled;

  const ChillRoutine({
    required this.id,
    required this.title,
    required this.timeMinutes,
    required this.enabled,
  });

  static ChillRoutine fromRow(Map<String, Object?> r) {
    final id = (r['id'] as int?) ?? 0;
    final title = (r['title'] ?? '').toString();
    final tm = (r['time_minutes'] as int?) ?? 0;
    final en = ((r['enabled'] as int?) ?? 1) == 1;
    return ChillRoutine(id: id, title: title, timeMinutes: tm, enabled: en);
  }
}

class ChillChatMessage {
  final ChatRole role;
  final String text;
  final DateTime at;

  const ChillChatMessage({required this.role, required this.text, required this.at});

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role == ChatRole.user ? 'u' : 'a',
      'text': text,
      'at_ms': at.millisecondsSinceEpoch,
    };
  }

  static ChillChatMessage fromJson(Map<String, Object?> j) {
    final roleRaw = (j['role'] ?? 'a').toString();
    final role = roleRaw == 'u' ? ChatRole.user : ChatRole.assistant;
    final text = (j['text'] ?? '').toString();
    final ms = (j['at_ms'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    return ChillChatMessage(
      role: role,
      text: text,
      at: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}

class ChillFocusState {
  final bool isRunning;
  final bool isDone;
  final DateTime? plannedEndAt;
  final int minutes;

  const ChillFocusState._({
    required this.isRunning,
    required this.isDone,
    required this.plannedEndAt,
    required this.minutes,
  });

  factory ChillFocusState.none() =>
      const ChillFocusState._(
        isRunning: false,
        isDone: false,
        plannedEndAt: null,
        minutes: 0,
      );

  factory ChillFocusState.running({
    required DateTime plannedEndAt,
    required int minutes,
  }) =>
      ChillFocusState._(
        isRunning: true,
        isDone: false,
        plannedEndAt: plannedEndAt,
        minutes: minutes,
      );

  factory ChillFocusState.done({
    required DateTime plannedEndAt,
    required int minutes,
  }) =>
      ChillFocusState._(
        isRunning: false,
        isDone: true,
        plannedEndAt: plannedEndAt,
        minutes: minutes,
      );

  String remainLabel() {
    if (!isRunning || plannedEndAt == null) return '';
    final diff = plannedEndAt!.difference(DateTime.now());
    final sec = diff.inSeconds;
    if (sec <= 0) return '00:00';
    final mm = (sec ~/ 60).toString().padLeft(2, '0');
    final ss = (sec % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

String chillFormatDateTime(DateTime dt) {
  return DateFormat('MM/dd(E) HH:mm', 'ko_KR').format(dt);
}

String chillFormatTimeMinutes(int minutes) {
  final m = minutes.clamp(0, 23 * 60 + 59);
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}
