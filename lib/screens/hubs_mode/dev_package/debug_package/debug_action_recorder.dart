import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'; // ✅ ValueNotifier, VoidCallback 등
import 'package:path_provider/path_provider.dart';

/// 사용자가 누른 버튼(액션) 1건
class DebugUserAction {
  final DateTime at;
  final String name;
  final String? route;
  final Map<String, dynamic>? meta;

  DebugUserAction({
    required this.at,
    required this.name,
    this.route,
    this.meta,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'at': at.toIso8601String(),
    'name': name,
    if (route != null) 'route': route,
    if (meta != null) 'meta': meta,
  };

  static DebugUserAction fromJson(Map<String, dynamic> json) {
    return DebugUserAction(
      at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      name: json['name']?.toString() ?? '(unknown)',
      route: json['route']?.toString(),
      meta: (json['meta'] is Map) ? Map<String, dynamic>.from(json['meta'] as Map) : null,
    );
  }
}

/// 저장되는 “버튼 누름 순서” 세션 1개
class DebugActionSession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? title;
  final List<DebugUserAction> actions;

  DebugActionSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    this.title,
    required this.actions,
  });

  int get actionCount => actions.length;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
    'actions': actions.map((e) => e.toJson()).toList(),
  };

  static DebugActionSession fromJson(Map<String, dynamic> json) {
    final actionsJson = json['actions'];
    final List<DebugUserAction> actions = <DebugUserAction>[];
    if (actionsJson is List) {
      for (final x in actionsJson) {
        if (x is Map) {
          actions.add(DebugUserAction.fromJson(Map<String, dynamic>.from(x)));
        }
      }
    }

    return DebugActionSession(
      id: json['id']?.toString() ?? '',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: DateTime.tryParse(json['endedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      title: json['title']?.toString(),
      actions: actions,
    );
  }
}

///
/// 버튼 누름 순서를 기록하는 레코더
/// - start() → recordAction() 여러 번 → stopAndSave()
/// - 저장: JSONL (한 줄 = 한 세션 JSON)
/// - 회전: 2MB 초과 시 .1, .2로 rotate
///
class DebugActionRecorder {
  DebugActionRecorder._();

  static final DebugActionRecorder instance = DebugActionRecorder._();

  static const int _maxFileBytes = 2 * 1024 * 1024; // 2MB
  static const int _rotateKeep = 2;

  static const String _dirName = 'pelican_debug';
  static const String _baseName = 'ui_actions_log.txt';

  Directory? _dir;
  File? _baseFile;
  File? _rot1;
  File? _rot2;

  bool _initialized = false;
  Completer<void>? _initCompleter;

  // Recording state
  bool _recording = false;
  String? _currentSessionId;
  DateTime? _currentStartedAt;
  String? _currentTitle;
  final List<DebugUserAction> _currentActions = <DebugUserAction>[];

  // 외부(UI 등)에서 변화 감지용
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  // 파일 쓰기 직렬화
  Future<void> _writeQueue = Future<void>.value();

  bool get isRecording => _recording;

  String? get currentSessionId => _currentSessionId;

  DateTime? get currentStartedAt => _currentStartedAt;

  String? get currentTitle => _currentTitle;

  List<DebugUserAction> get currentActions => List<DebugUserAction>.unmodifiable(_currentActions);

  Future<void> init() async {
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docDir.path}/$_dirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _dir = dir;
      _baseFile = File('${dir.path}/$_baseName');
      _rot1 = File('${dir.path}/ui_actions_log.1.txt');
      _rot2 = File('${dir.path}/ui_actions_log.2.txt');

      if (!await _baseFile!.exists()) {
        await _baseFile!.create(recursive: true);
      }

      _initialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// 기록 시작 (기존 기록 중이면 무시)
  Future<void> start({String? title}) async {
    await init();
    if (_recording) return;

    _recording = true;
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentStartedAt = DateTime.now();
    _currentTitle = (title != null && title.trim().isNotEmpty) ? title.trim() : null;
    _currentActions.clear();

    _bump();
  }

  /// 기록 중단 + 세션 저장
  /// 저장 성공 시 저장된 세션을 반환, 기록 중이 아니면 null
  Future<DebugActionSession?> stopAndSave({String? titleOverride}) async {
    await init();
    if (!_recording) return null;

    final ended = DateTime.now();
    final started = _currentStartedAt ?? ended;
    final id = _currentSessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final title = (titleOverride != null && titleOverride.trim().isNotEmpty) ? titleOverride.trim() : _currentTitle;

    final session = DebugActionSession(
      id: id,
      startedAt: started,
      endedAt: ended,
      title: title,
      actions: List<DebugUserAction>.from(_currentActions),
    );

    final line = '${jsonEncode(session.toJson())}\n';
    await _enqueueAppend(line);

    // reset current
    _recording = false;
    _currentSessionId = null;
    _currentStartedAt = null;
    _currentTitle = null;
    _currentActions.clear();

    _bump();
    return session;
  }

  /// 기록 중단 (저장 안 함 / 버림)
  Future<void> discardCurrent() async {
    await init();
    if (!_recording) return;

    _recording = false;
    _currentSessionId = null;
    _currentStartedAt = null;
    _currentTitle = null;
    _currentActions.clear();

    _bump();
  }

  /// 버튼 누름 1건 기록
  void recordAction(
      String name, {
        String? route,
        Map<String, dynamic>? meta,
      }) {
    if (!_recording) return;

    _currentActions.add(
      DebugUserAction(
        at: DateTime.now(),
        name: name,
        route: route,
        meta: meta,
      ),
    );

    _bump();
  }

  /// 저장된 세션 목록 로드(회전 포함)
  Future<List<DebugActionSession>> readSessions({int? limit}) async {
    await init();

    final lines = await _readAllLinesCombined();
    final List<DebugActionSession> out = <DebugActionSession>[];

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          final session = DebugActionSession.fromJson(Map<String, dynamic>.from(decoded));
          if (session.id.isNotEmpty) out.add(session);
        }
      } catch (_) {
        // ignore malformed lines
      }
    }

    out.sort((a, b) => b.endedAt.compareTo(a.endedAt));

    if (limit != null && limit > 0 && out.length > limit) {
      return out.sublist(0, limit);
    }
    return out;
  }

  /// 특정 세션 삭제(id 기준). 성공 시 true
  Future<bool> deleteSession(String id) async {
    await init();
    final sessions = await readSessions();
    final filtered = sessions.where((s) => s.id != id).toList();
    if (filtered.length == sessions.length) return false;

    await _rewriteAll(filtered);
    _bump();
    return true;
  }

  /// 전체 삭제(회전 포함)
  Future<void> clearAll() async {
    await init();

    Future<void> del(File? f) async {
      if (f == null) return;
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    await del(_baseFile);
    await del(_rot1);
    await del(_rot2);

    // recreate base
    _baseFile = File('${_dir!.path}/$_baseName');
    try {
      await _baseFile!.create(recursive: true);
    } catch (_) {}

    _bump();
  }

  // ─────────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────────

  void _bump() {
    tick.value = tick.value + 1;
  }

  Future<void> _enqueueAppend(String line) async {
    final bytes = utf8.encode(line).length;

    _writeQueue = _writeQueue.then((_) async {
      await _rotateIfNeeded(bytes);
      await _baseFile!.writeAsString(line, mode: FileMode.append, flush: true);
    });

    return _writeQueue;
  }

  Future<void> _rotateIfNeeded(int nextWriteBytes) async {
    if (_baseFile == null) return;

    try {
      if (!await _baseFile!.exists()) {
        await _baseFile!.create(recursive: true);
        return;
      }

      final stat = await _baseFile!.stat();
      final projected = stat.size + nextWriteBytes;
      if (projected <= _maxFileBytes) return;

      if (_rotateKeep >= 2) {
        if (_rot2 != null && await _rot2!.exists()) {
          await _rot2!.delete();
        }
        if (_rot1 != null && await _rot1!.exists()) {
          await _rot1!.rename(_rot2!.path);
        }
      }

      if (_rot1 != null && await _baseFile!.exists()) {
        await _baseFile!.rename(_rot1!.path);
      }

      _baseFile = File('${_dir!.path}/$_baseName');
      await _baseFile!.create(recursive: true);
    } catch (_) {
      // rotate 실패는 치명적이지 않음
    }
  }

  Future<List<String>> _readAllLinesCombined() async {
    final List<String> lines = <String>[];

    Future<void> readIfExists(File? f) async {
      if (f == null) return;
      if (!await f.exists()) return;
      try {
        final txt = await f.readAsString();
        lines.addAll(const LineSplitter().convert(txt));
      } catch (_) {}
    }

    await readIfExists(_rot2);
    await readIfExists(_rot1);
    await readIfExists(_baseFile);

    return lines;
  }

  Future<void> _rewriteAll(List<DebugActionSession> sessions) async {
    try {
      if (_rot1 != null && await _rot1!.exists()) await _rot1!.delete();
    } catch (_) {}
    try {
      if (_rot2 != null && await _rot2!.exists()) await _rot2!.delete();
    } catch (_) {}

    final base = _baseFile ?? File('${_dir!.path}/$_baseName');
    _baseFile = base;

    try {
      await base.writeAsString('', flush: true);
    } catch (_) {}

    for (final s in sessions) {
      final line = '${jsonEncode(s.toJson())}\n';
      await base.writeAsString(line, mode: FileMode.append, flush: true);
    }
  }
}
